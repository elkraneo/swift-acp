//
//  ACPClient.swift
//  swift-acp
//
//  Main client for ACP communication.
//

import Foundation

/// Main client for communicating with an ACP-compatible agent
@MainActor
public final class ACPClient: Sendable {

    // MARK: - Properties

    private let transport: ACPTransport
    private let clientInfo: ClientInfo
    private let capabilities: ClientCapabilities

    private var agentInfo: AgentInfo?
    private var agentCapabilities: AgentCapabilities?
    private var currentSessionId: SessionID?

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
        
        print("[ACP] 🤝 Connected to agent: \(response.agentInfo.name) (\(response.agentInfo.version))")
        if let agentCaps = response.capabilities.mcpCapabilities {
            print("[ACP]    Agent MCP capabilities: \(agentCaps)")
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

        print("[ACP] 🎫 Session created: \(response.sessionId)")
        if let modes = response.modes {
            print("[ACP]    Available modes: \(modes.available.map { $0.id })")
        }
        if let models = response.models {
            print("[ACP]    Available models: \(models.availableModels.map { $0.name })")
            print("[ACP]    Current model: \(models.currentModelId ?? "none")")
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

        let request = PromptRequest(sessionId: sid, text: text)

        let response: PromptResponse = try await transport.sendRequest(
            method: "session/prompt",
            params: request
        )

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

        let request = PromptRequest(sessionId: sid, content: content)

        let response: PromptResponse = try await transport.sendRequest(
            method: "session/prompt",
            params: request
        )

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
            print("[ACP] 📥 Received notification: \(method)")
        case .request(let id, let method, _):
            print("[ACP] 📥 Received request: \(method) (id: \(id))")
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
                delegate?.client(self, didReceiveUpdate: notification.update)
            }
        default:
            break
        }
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
                print("[ACPClient] 🛠️ Received tools/list request")
                if let tools = await delegate?.listTools(self) {
                    print("[ACPClient]   Providing \(tools.count) tools")
                    let response = ListToolsResponse(tools: tools)
                    try await transport.sendResponse(id: id, result: response)
                } else {
                    print("[ACPClient]   No tools provided (delegate nil)")
                    let response = ListToolsResponse(tools: [])
                    try await transport.sendResponse(id: id, result: response)
                }

            case "tools/call":
                print("[ACPClient] ⚡️ Received tools/call request")
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
            print("[ACP] Failed to respond to \(method): \(error)")
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
