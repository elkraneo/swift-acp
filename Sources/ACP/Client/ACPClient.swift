//
//  ACPClient.swift
//  swift-acp
//
//  Main client for ACP communication.
//

import Foundation
import OSLog

/// Main client for communicating with an ACP-compatible agent
@MainActor
public final class ACPClient: Sendable {

    // MARK: - Properties

    private static let logger = Logger(subsystem: "io.210x7.swift-acp", category: "client")
    private static var isVerboseLoggingEnabled: Bool {
        ProcessInfo.processInfo.environment["ACP_VERBOSE"] == "1"
    }

    private let transport: ACPTransport
    private let clientInfo: ClientInfo
    private let capabilities: ClientCapabilities

    private var agentInfo: AgentInfo?
    private var agentCapabilities: AgentCapabilities?
    private var currentSessionId: SessionID?
    private let timingEnabled = ProcessInfo.processInfo.environment["ACP_TIMING"] == "1"
    private var promptTimings: [SessionID: PromptTiming] = [:]
    private var promptSequenceBySession: [SessionID: Int] = [:]
    private var toolTimings: [String: DispatchTime] = [:]
    private let batchingEnabled = ProcessInfo.processInfo.environment["ACP_BATCHING"] != "0"
    private let batchIntervalNs: UInt64 = {
        if let raw = ProcessInfo.processInfo.environment["ACP_BATCH_MS"],
           let ms = UInt64(raw) {
            return ms * 1_000_000
        }
        return 50_000_000
    }()
    private var updateBuffers: [SessionID: UpdateBuffer] = [:]
    private var flushTasks: [SessionID: Task<Void, Never>] = [:]

    private struct PromptTiming {
        let sequence: Int
        let start: DispatchTime
        var responseAt: DispatchTime?
        var firstMessageAt: DispatchTime?
        var firstToolCallAt: DispatchTime?
        var messageChunkCount: Int
        var totalTextBytes: Int
    }

    private struct UpdateBuffer {
        var messageChunks: [MessageChunk] = []
        var toolCalls: [ToolCallUpdate] = []
        var plan: Plan?
        var commands: [SlashCommand]?
        var modes: SessionModeState?

        mutating func merge(_ update: SessionUpdate) {
            if let chunks = update.messageChunks {
                messageChunks.append(contentsOf: chunks)
            }
            if let calls = update.toolCalls {
                toolCalls.append(contentsOf: calls)
            }
            if let plan = update.plan {
                self.plan = plan
            }
            if let commands = update.commands {
                self.commands = commands
            }
            if let modes = update.modes {
                self.modes = modes
            }
        }

        func toSessionUpdate() -> SessionUpdate? {
            let hasChunks = !messageChunks.isEmpty
            let hasCalls = !toolCalls.isEmpty
            if !hasChunks, !hasCalls, plan == nil, commands == nil, modes == nil {
                return nil
            }
            return SessionUpdate(
                messageChunks: hasChunks ? messageChunks : nil,
                toolCalls: hasCalls ? toolCalls : nil,
                plan: plan,
                commands: commands,
                modes: modes
            )
        }
    }

    /// Delegate for handling agent requests and notifications
    public weak var delegate: ACPClientDelegate?

    /// Whether the client is connected to an agent
    public var isConnected: Bool {
        get async { await transport.isConnected }
    }

    /// Current session ID (if any)
    public var sessionId: SessionID? { currentSessionId }

    // MARK: - Initialization

    /// Create a new ACP client with a process transport (for local CLI agents)
    /// - Parameters:
    ///   - command: Agent CLI command (e.g., "claude", "gemini")
    ///   - arguments: Command line arguments (e.g., ["--acp"])
    ///   - clientInfo: Information about this client application
    ///   - capabilities: Capabilities this client supports
    public convenience init(
        command: String,
        arguments: [String] = [],
        clientInfo: ClientInfo = ClientInfo(name: "MyApp", version: "1.0"),
        capabilities: ClientCapabilities = .default
    ) {
        let transport = ACPTransport.process(command: command, arguments: arguments)
        self.init(transport: transport, clientInfo: clientInfo, capabilities: capabilities)
    }

    /// Create a new ACP client with an HTTP transport (for remote servers)
    /// - Parameters:
    ///   - serverURL: The base URL of the ACP server (e.g., "http://localhost:8000")
    ///   - clientInfo: Information about this client application
    ///   - capabilities: Capabilities this client supports
    public convenience init(
        serverURL: URL,
        clientInfo: ClientInfo = ClientInfo(name: "MyApp", version: "1.0"),
        capabilities: ClientCapabilities = .default
    ) {
        let transport = ACPTransport.http(url: serverURL)
        self.init(transport: transport, clientInfo: clientInfo, capabilities: capabilities)
    }

    /// Create a new ACP client with a custom transport
    /// - Parameters:
    ///   - transport: The transport to use
    ///   - clientInfo: Information about this client application
    ///   - capabilities: Capabilities this client supports
    public init(
        transport: ACPTransport,
        clientInfo: ClientInfo = ClientInfo(name: "MyApp", version: "1.0"),
        capabilities: ClientCapabilities = .default
    ) {
        self.transport = transport
        self.clientInfo = clientInfo
        self.capabilities = capabilities
    }

    // MARK: - Connection

    /// Connect to the agent and initialize the protocol
    @discardableResult
    public func connect() async throws -> InitializeResponse {
        // Set up message handler
        transport.setMessageHandler { [weak self] message in
            Task { @MainActor in
                await self?.handleIncomingMessage(message)
            }
        }

        // Connect to the transport
        try await transport.connect()

        // Send initialize request
        let request = InitializeRequest(
            supportedVersions: [.current],
            capabilities: capabilities,
            clientInfo: clientInfo
        )

        let response: InitializeResponse = try await transport.sendRequest(
            method: "initialize",
            params: request
        )

        self.agentInfo = response.agentInfo
        self.agentCapabilities = response.capabilities
        
        if Self.isVerboseLoggingEnabled {
            Self.logger.debug("[ACP] Connected to agent: \(response.agentInfo.name, privacy: .public) (\(response.agentInfo.version, privacy: .public))")
            if let agentCaps = response.capabilities.mcpCapabilities {
                Self.logger.debug("[ACP] Agent MCP capabilities: \(String(describing: agentCaps), privacy: .public)")
            }
        }

        return response
    }

    /// Fetch the manifest for an agent, including status metrics and metadata
    /// - Parameter name: Agent name (defaults to current connected agent)
    /// - Returns: Agent manifest with status/usage info
    public func getAgentManifest(name: String? = nil) async throws -> AgentManifest {
        let agentName = name ?? agentInfo?.name ?? ""
        guard !agentName.isEmpty else {
            throw ACPError.protocolError("No agent name available. Provide a name or connect first.")
        }
        
        return try await transport.sendRequest(
            method: "agents/get",
            params: ["name": agentName]
        )
    }

    /// Disconnect from the agent
    public func disconnect() async {
        transport.disconnect()
        currentSessionId = nil
        agentInfo = nil
        agentCapabilities = nil
    }

    // MARK: - Session Management

    /// Create a new conversation session
    /// - Parameters:
    ///   - workingDirectory: Working directory for the session
    ///   - model: Model to use (e.g., "haiku", "sonnet", "opus")
    /// - Returns: The full session response including available models
    @discardableResult
    public func newSession(workingDirectory: URL? = nil, model: String? = nil, meta: [String: AnyCodable]? = nil) async throws -> NewSessionResponse {
        let request = NewSessionRequest(
            cwd: workingDirectory?.path ?? FileManager.default.currentDirectoryPath,
            mcpServers: capabilities.mcpServers ?? [],
            model: model,
            _meta: meta
        )

        let response: NewSessionResponse = try await transport.sendRequest(
            method: "session/new",
            params: request
        )

        if Self.isVerboseLoggingEnabled {
            Self.logger.debug("[ACP] Session created: \(response.sessionId, privacy: .public)")
            if let modes = response.modes {
                Self.logger.debug("[ACP] Available modes: \(modes.available.map { $0.id }.joined(separator: \",\"), privacy: .public)")
            }
            if let models = response.models {
                Self.logger.debug("[ACP] Available models: \(models.availableModels.map { $0.name }.joined(separator: \",\"), privacy: .public)")
                Self.logger.debug("[ACP] Current model: \(models.currentModelId ?? "none", privacy: .public)")
            }
        }

        currentSessionId = response.sessionId
        return response
    }


    /// Load an existing session
    /// - Parameter sessionId: Session ID to load
    @discardableResult
    public func loadSession(_ sessionId: SessionID) async throws -> SessionID {
        let request = LoadSessionRequest(sessionId: sessionId)

        let response: LoadSessionResponse = try await transport.sendRequest(
            method: "session/load",
            params: request
        )

        currentSessionId = response.sessionId
        return response.sessionId
    }

    // MARK: - Prompting

    /// Send a text prompt to the agent
    /// - Parameters:
    ///   - text: The prompt text
    ///   - sessionId: Session ID (uses current if not specified)
    /// - Returns: The prompt response with stop reason
    public func prompt(_ text: String, sessionId: SessionID? = nil) async throws -> PromptResponse {
        guard let sid = sessionId ?? currentSessionId else {
            throw ACPError.noActiveSession
        }

        startPromptTiming(sessionId: sid, label: "text")
        let request = PromptRequest(sessionId: sid, text: text)

        let response: PromptResponse = try await transport.sendRequest(
            method: "session/prompt",
            params: request
        )
        markPromptResponse(sessionId: sid)

        return response
    }

    /// Send a prompt with multiple content types
    /// - Parameters:
    ///   - content: Array of prompt content
    ///   - sessionId: Session ID (uses current if not specified)
    /// - Returns: The prompt response
    public func prompt(content: [PromptContent], sessionId: SessionID? = nil) async throws -> PromptResponse {
        guard let sid = sessionId ?? currentSessionId else {
            throw ACPError.noActiveSession
        }

        startPromptTiming(sessionId: sid, label: "content")
        let request = PromptRequest(sessionId: sid, content: content)

        let response: PromptResponse = try await transport.sendRequest(
            method: "session/prompt",
            params: request
        )
        markPromptResponse(sessionId: sid)

        return response
    }

    /// Cancel an ongoing prompt
    /// - Parameter sessionId: Session ID (uses current if not specified)
    public func cancel(sessionId: SessionID? = nil) async throws {
        guard let sid = sessionId ?? currentSessionId else {
            throw ACPError.noActiveSession
        }

        let notification = CancelNotification(sessionId: sid)

        try await transport.sendNotification(
            method: "session/cancel",
            params: notification
        )
    }

    /// Change the model for the current session without reconnecting
    /// - Parameters:
    ///   - modelId: The model ID to switch to
    ///   - sessionId: Session ID (uses current if not specified)
    public func setSessionModel(_ modelId: String, sessionId: SessionID? = nil) async throws {
        guard let sid = sessionId ?? currentSessionId else {
            throw ACPError.noActiveSession
        }

        let request = SetSessionModelRequest(sessionId: sid, modelId: modelId)

        let _: SetSessionModelResponse = try await transport.sendRequest(
            method: "session/set_model",
            params: request
        )
    }

    /// Change the mode for the current session without reconnecting
    /// - Parameters:
    ///   - modeId: The mode ID to switch to
    ///   - sessionId: Session ID (uses current if not specified)
    public func setSessionMode(_ modeId: String, sessionId: SessionID? = nil) async throws {
        guard let sid = sessionId ?? currentSessionId else {
            throw ACPError.noActiveSession
        }

        let request = SetSessionModeRequest(sessionId: sid, modeId: modeId)

        let _: SetSessionModeResponse = try await transport.sendRequest(
            method: "session/set_mode",
            params: request
        )
    }

    // MARK: - Message Handling

    private func handleIncomingMessage(_ message: IncomingMessage) async {
        switch message {
        case .notification(let method, _):
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP] Received notification: \(method, privacy: .public)")
            }
        case .request(let id, let method, _):
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP] Received request: \(method, privacy: .public) (id: \(String(describing: id), privacy: .public))")
            }
        default:
            break
        }
        
        switch message {
        case .notification(let method, let params):
            await handleNotification(method: method, params: params)

        case .request(let id, let method, let params):
            await handleAgentRequest(id: id, method: method, params: params)

        case .response, .error:
            break
        }
    }

    private func handleNotification(method: String, params: Data?) async {
        guard let params else { return }
        let decoder = JSONDecoder()

        switch method {
        case "session/update":
            if let notification = try? decoder.decode(SessionUpdateNotification.self, from: params) {
                handleSessionUpdateTiming(sessionId: notification.sessionId, update: notification.update)
                if batchingEnabled {
                    enqueueUpdate(sessionId: notification.sessionId, update: notification.update)
                } else {
                    delegate?.client(self, didReceiveUpdate: notification.update)
                }
            }
        default:
            break
        }
    }

    private func startPromptTiming(sessionId: SessionID, label: String) {
        guard timingEnabled else { return }
        let nextSeq = (promptSequenceBySession[sessionId] ?? 0) + 1
        promptSequenceBySession[sessionId] = nextSeq
        promptTimings[sessionId] = PromptTiming(
            sequence: nextSeq,
            start: DispatchTime.now(),
            responseAt: nil,
            firstMessageAt: nil,
            firstToolCallAt: nil,
            messageChunkCount: 0,
            totalTextBytes: 0
        )
        Self.logger.info("[ACP Timing] prompt.start session=\(sessionId, privacy: .public) seq=\(nextSeq, privacy: .public) label=\(label, privacy: .public)")
    }

    private func markPromptResponse(sessionId: SessionID) {
        guard timingEnabled, var timing = promptTimings[sessionId] else { return }
        let now = DispatchTime.now()
        timing.responseAt = now
        promptTimings[sessionId] = timing
        let elapsedMs = Double(now.uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
        Self.logger.info("[ACP Timing] prompt.response session=\(sessionId, privacy: .public) seq=\(timing.sequence, privacy: .public) ms=\(String(format: "%.2f", elapsedMs), privacy: .public)")
    }

    private func handleSessionUpdateTiming(sessionId: SessionID, update: SessionUpdate) {
        guard timingEnabled, var timing = promptTimings[sessionId] else { return }
        let now = DispatchTime.now()

        if let chunks = update.messageChunks {
            for chunk in chunks {
                timing.messageChunkCount += 1
                if let text = chunk.text {
                    timing.totalTextBytes += text.utf8.count
                } else if let data = chunk.data {
                    timing.totalTextBytes += data.utf8.count
                }
                if timing.firstMessageAt == nil {
                    timing.firstMessageAt = now
                    let sinceStart = Double(now.uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
                    if let responseAt = timing.responseAt {
                        let sinceResponse = Double(now.uptimeNanoseconds - responseAt.uptimeNanoseconds) / 1_000_000
                        Self.logger.info("[ACP Timing] prompt.first_message session=\(sessionId, privacy: .public) seq=\(timing.sequence, privacy: .public) ms=\(String(format: "%.2f", sinceStart), privacy: .public) sinceResponse=\(String(format: "%.2f", sinceResponse), privacy: .public)")
                    } else {
                        Self.logger.info("[ACP Timing] prompt.first_message session=\(sessionId, privacy: .public) seq=\(timing.sequence, privacy: .public) ms=\(String(format: "%.2f", sinceStart), privacy: .public)")
                    }
                } else if timing.messageChunkCount % 200 == 0 {
                    let sinceStart = Double(now.uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
                    Self.logger.info("[ACP Timing] prompt.chunk_progress session=\(sessionId, privacy: .public) seq=\(timing.sequence, privacy: .public) chunks=\(timing.messageChunkCount, privacy: .public) bytes=\(timing.totalTextBytes, privacy: .public) ms=\(String(format: "%.2f", sinceStart), privacy: .public)")
                }
            }
        }

        if let toolCalls = update.toolCalls {
            for call in toolCalls {
                if timing.firstToolCallAt == nil {
                    timing.firstToolCallAt = now
                    let sinceStart = Double(now.uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
                    Self.logger.info("[ACP Timing] prompt.first_tool_call session=\(sessionId, privacy: .public) seq=\(timing.sequence, privacy: .public) ms=\(String(format: "%.2f", sinceStart), privacy: .public) toolId=\(call.id, privacy: .public) status=\(call.status.rawValue, privacy: .public)")
                }

                if toolTimings[call.id] == nil, call.status == .running || call.status == .pending {
                    toolTimings[call.id] = now
                    let sinceStart = Double(now.uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
                    Self.logger.info("[ACP Timing] tool.start session=\(sessionId, privacy: .public) seq=\(timing.sequence, privacy: .public) toolId=\(call.id, privacy: .public) status=\(call.status.rawValue, privacy: .public) ms=\(String(format: "%.2f", sinceStart), privacy: .public)")
                }

                if call.status == .complete || call.status == .failed || call.status == .cancelled {
                    if let startedAt = toolTimings.removeValue(forKey: call.id) {
                        let toolMs = Double(now.uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
                        Self.logger.info("[ACP Timing] tool.end session=\(sessionId, privacy: .public) seq=\(timing.sequence, privacy: .public) toolId=\(call.id, privacy: .public) status=\(call.status.rawValue, privacy: .public) ms=\(String(format: "%.2f", toolMs), privacy: .public)")
                    }
                }
            }
        }

        promptTimings[sessionId] = timing
    }

    private func enqueueUpdate(sessionId: SessionID, update: SessionUpdate) {
        var buffer = updateBuffers[sessionId] ?? UpdateBuffer()
        buffer.merge(update)
        updateBuffers[sessionId] = buffer

        if flushTasks[sessionId] == nil {
            let interval = batchIntervalNs
            flushTasks[sessionId] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: interval)
                await MainActor.run {
                    self?.flushBufferedUpdates(sessionId: sessionId)
                }
            }
        }
    }

    private func flushBufferedUpdates(sessionId: SessionID) {
        flushTasks[sessionId] = nil
        guard let buffer = updateBuffers.removeValue(forKey: sessionId),
              let update = buffer.toSessionUpdate()
        else {
            return
        }
        delegate?.client(self, didReceiveUpdate: update)
    }

    private func handleAgentRequest(id: RequestID, method: String, params: Data?) async {
        let decoder = JSONDecoder()

        do {
            switch method {
            case "session/request_permission":
                guard let params else {
                    try await transport.sendErrorResponse(id: id, code: JSONRPCError.invalidParams, message: "Missing params")
                    return
                }

                do {
                    let request = try decoder.decode(RequestPermissionRequest.self, from: params)

                    if let delegate {
                        let optionId = await delegate.client(self, requestPermission: request)
                        let response = RequestPermissionResponse(optionId: optionId)
                        try await transport.sendResponse(id: id, result: response)
                    } else {
                        let response = RequestPermissionResponse(optionId: "reject_once")
                        try await transport.sendResponse(id: id, result: response)
                    }
                } catch {
                    try await transport.sendErrorResponse(id: id, code: JSONRPCError.invalidParams, message: "Invalid params: \(error.localizedDescription)")
                }

            case "fs/read_text_file":
                guard let params,
                      let request = try? decoder.decode(ReadTextFileRequest.self, from: params) else {
                    try await transport.sendErrorResponse(id: id, code: JSONRPCError.invalidParams, message: "Invalid params")
                    return
                }

                do {
                    let content = try await delegate?.client(self, readFile: request.path) ?? ""
                    let response = ReadTextFileResponse(content: content)
                    try await transport.sendResponse(id: id, result: response)
                } catch {
                    try await transport.sendErrorResponse(id: id, code: JSONRPCError.resourceNotFound, message: error.localizedDescription)
                }

            case "fs/write_text_file":
                guard let params,
                      let request = try? decoder.decode(WriteTextFileRequest.self, from: params) else {
                    try await transport.sendErrorResponse(id: id, code: JSONRPCError.invalidParams, message: "Invalid params")
                    return
                }

                do {
                    try await delegate?.client(self, writeFile: request.path, content: request.content)
                    let response = WriteTextFileResponse(success: true)
                    try await transport.sendResponse(id: id, result: response)
                } catch {
                    try await transport.sendErrorResponse(id: id, code: JSONRPCError.internalError, message: error.localizedDescription)
                }

            case "tools/list":
                if Self.isVerboseLoggingEnabled {
                    Self.logger.debug("[ACPClient] Received tools/list request")
                }
                if let tools = await delegate?.listTools(self) {
                    if Self.isVerboseLoggingEnabled {
                        Self.logger.debug("[ACPClient] Providing \(tools.count, privacy: .public) tools")
                    }
                    let response = ListToolsResponse(tools: tools)
                    try await transport.sendResponse(id: id, result: response)
                } else {
                    if Self.isVerboseLoggingEnabled {
                        Self.logger.debug("[ACPClient] No tools provided (delegate nil)")
                    }
                    let response = ListToolsResponse(tools: [])
                    try await transport.sendResponse(id: id, result: response)
                }

            case "tools/call":
                if Self.isVerboseLoggingEnabled {
                    Self.logger.debug("[ACPClient] Received tools/call request")
                }
                guard let params,
                      let request = try? decoder.decode(CallToolRequest.self, from: params) else {
                    try await transport.sendErrorResponse(id: id, code: JSONRPCError.invalidParams, message: "Invalid params")
                    return
                }

                if let delegate {
                    do {
                        let response = try await delegate.client(self, callTool: request.name, arguments: request.arguments.mapValues { $0.value })
                        try await transport.sendResponse(id: id, result: response)
                    } catch {
                        try await transport.sendErrorResponse(id: id, code: JSONRPCError.internalError, message: error.localizedDescription)
                    }
                } else {
                    try await transport.sendErrorResponse(id: id, code: JSONRPCError.methodNotFound, message: "No tool handler registered")
                }

            default:
                try await transport.sendErrorResponse(id: id, code: JSONRPCError.methodNotFound, message: "Method not found: \(method)")
            }
        } catch {
            // Failed to send response
            Self.logger.error("[ACP] Failed to respond to \(method, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Errors

public enum ACPError: Error, LocalizedError {
    case noActiveSession
    case connectionFailed(String)
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session. Call newSession() first."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .protocolError(let reason):
            return "Protocol error: \(reason)"
        }
    }
}
