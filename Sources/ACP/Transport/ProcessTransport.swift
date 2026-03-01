#if os(macOS)

//
//  ProcessTransport.swift
//  swift-acp
//
//  Transport layer for ACP communication via spawned process stdin/stdout.
//

import Foundation
import OSLog

/// Transport layer that communicates with an agent process via stdin/stdout
actor ProcessTransport {
    
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: "io.210x7.swift-acp", category: "transport")
    private static var isVerboseLoggingEnabled: Bool {
        ProcessInfo.processInfo.environment["ACP_VERBOSE"] == "1"
    }

    private let command: String
    private let arguments: [String]
    private let workingDirectory: URL?
    
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    
    
    private var pendingRequests: [RequestID: CheckedContinuation<Data, Error>] = [:]
    private var requestCounter: Int = 0
    private var requestTimings: [RequestID: RequestTiming] = [:]
    private var readingTask: Task<Void, Never>?
    private var errorReadingTask: Task<Void, Never>?
    private let timingEnabled = ProcessInfo.processInfo.environment["ACP_TIMING"] == "1"

    private struct RequestTiming {
        let method: String
        let start: DispatchTime
        let payloadBytes: Int
    }
    
    private var messageHandler: (@Sendable (IncomingMessage) async -> Void)?
    
    public var isConnected: Bool {
        process?.isRunning ?? false
    }
    
    // MARK: - Initialization
    
    /// Create a transport for the given agent command
    /// - Parameters:
    ///   - command: The agent CLI command (e.g., "claude", "gemini")
    ///   - arguments: Command line arguments (e.g., ["--acp"])
    ///   - workingDirectory: Working directory for the process
    public init(command: String, arguments: [String] = [], workingDirectory: URL? = nil) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
    
    // MARK: - Connection
    
    /// Set the handler for incoming messages (notifications and requests from agent)
    public func setMessageHandler(_ handler: @escaping @Sendable (IncomingMessage) async -> Void) {
        self.messageHandler = handler
    }
    
    /// Start the agent process and establish communication
    public func connect() async throws {
        guard process == nil else {
            throw TransportError.alreadyConnected
        }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = arguments
        
        // Ignore SIGPIPE to prevent crash if the subprocess dies unexpectedly
        signal(SIGPIPE, SIG_IGN)
        
        // Inject common paths into the process environment
        var env = ProcessInfo.processInfo.environment
        // Include user's local bin, homebrew, and npm global paths
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let userLocalPaths = "\(homeDir)/.local/bin:\(homeDir)/.npm-global/bin"
        let commonPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let allPaths = "\(userLocalPaths):\(commonPaths)"
        if let existingPath = env["PATH"] {
            env["PATH"] = allPaths + ":" + existingPath
        } else {
            env["PATH"] = allPaths
        }
        proc.environment = env
        
        if let workingDirectory {
            proc.currentDirectoryURL = workingDirectory
        }
        
        // Set up pipes
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr
        
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.process = proc
        
        if Self.isVerboseLoggingEnabled {
            let fullCommand = "\(command) \(arguments.joined(separator: " "))"
            Self.logger.debug("[ACP Transport] Launching: \(fullCommand, privacy: .public)")
            Self.logger.debug("[ACP Transport] Working directory: \(self.workingDirectory?.path ?? "default", privacy: .public)")
            Self.logger.debug("[ACP Transport] PATH includes: \(String(env["PATH"]?.prefix(200) ?? "nil"), privacy: .public)...")
        }
        
        // Launch the process first
        do {
            try proc.run()
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP Transport] Process launched with PID: \(proc.processIdentifier, privacy: .public)")
            }
        } catch {
            Self.logger.error("[ACP Transport] Failed to launch: \(String(describing: error), privacy: .public)")
            throw TransportError.failedToLaunch(error)
        }
        
        // Start reading stdout and stderr AFTER process is running
        startReadingOutput()
        startReadingError()
    }
    
    /// Disconnect from the agent process
    public func disconnect() {
        // Cancel reading tasks first
        readingTask?.cancel()
        readingTask = nil
        errorReadingTask?.cancel()
        errorReadingTask = nil
        
        // Close file handles to force async sequences to exit
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()
        try? stdinPipe?.fileHandleForWriting.close()
        
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        
        // Reset request counter for new connection
        requestCounter = 0
        
        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: TransportError.disconnected)
        }
        pendingRequests.removeAll()
    }
    
    // MARK: - Sending Messages
    
    public func nextRequestID() -> RequestID {
        requestCounter += 1
        return .string("\(requestCounter)")
    }
    
    /// Send a request and wait for response
    public func sendRequest<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        method: String,
        params: Params?
    ) async throws -> Result {
        let id = nextRequestID()
        let request = JSONRPCRequest(id: id, method: method, params: params)
        
        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingRequests[id] = continuation
            
            Task {
                do {
                    if timingEnabled {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .withoutEscapingSlashes
                        let payloadBytes = (try? encoder.encode(request).count) ?? 0
                        requestTimings[id] = RequestTiming(
                            method: method,
                            start: DispatchTime.now(),
                            payloadBytes: payloadBytes
                        )
                        Self.logger.info("[ACP Timing] request.start id=\(id, privacy: .public) method=\(method, privacy: .public) bytes=\(payloadBytes, privacy: .public)")
                    }
                    try await send(request)
                } catch {
                    pendingRequests.removeValue(forKey: id)
                    if timingEnabled {
                        requestTimings.removeValue(forKey: id)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
        
        return try JSONDecoder().decode(Result.self, from: responseData)
    }
    
    /// Send a notification (no response expected)
    public func sendNotification<Params: Encodable & Sendable>(
        method: String,
        params: Params?
    ) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        try await send(notification)
    }
    
    /// Send a response to an agent request
    public func sendResponse<Result: Encodable & Sendable>(
        id: RequestID,
        result: Result
    ) async throws {
        // Encode using JSONSerialization for the outer structure
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let resultData = try encoder.encode(result)
        let resultJSON = try JSONSerialization.jsonObject(with: resultData)
        
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.jsonSerializableValue,
            "result": resultJSON
        ]
        let data = try JSONSerialization.data(withJSONObject: response)
        
        // Debug log the response
        if ProcessInfo.processInfo.environment["ACP_VERBOSE"] == "1",
           let jsonStr = String(data: data, encoding: .utf8) {
            Self.logger.debug("[ACP Transport] -> \(jsonStr, privacy: .public)")
        }
        
        guard let stdin = stdinPipe else {
            throw TransportError.notConnected
        }
        
        var messageData = data
        messageData.append(contentsOf: [0x0A])
        
        do {
            try stdin.fileHandleForWriting.write(contentsOf: messageData)
        } catch {
            let terminationReason = process?.terminationReason
            let exitCode = process?.terminationStatus
            throw TransportError.sendFailed("Write failed: \(error.localizedDescription) (Process status: \(String(describing: terminationReason)), exit: \(String(describing: exitCode)))")
        }
    }
    
    /// Send an error response
    public func sendErrorResponse(
        id: RequestID,
        code: Int,
        message: String
    ) async throws {
        struct ErrorResponse: Encodable {
            let jsonrpc: String = "2.0"
            let id: RequestID
            let error: ErrorPayload
            
            struct ErrorPayload: Encodable {
                let code: Int
                let message: String
            }
        }
        let response = ErrorResponse(id: id, error: .init(code: code, message: message))
        try await send(response)
    }
    
    // MARK: - Private
    
    private func send<T: Encodable>(_ message: T) async throws {
        guard let stdin = stdinPipe else {
            throw TransportError.notConnected
        }
        
        let encoder = JSONEncoder()
        // CRITICAL: Prevent Swift from escaping forward slashes ("/" → "\/")
        // which breaks parsers like codex-acp that expect unescaped slashes
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(message)
        
        // Debug Log
        if ProcessInfo.processInfo.environment["ACP_VERBOSE"] == "1",
           let jsonStr = String(data: data, encoding: .utf8) {
            Self.logger.debug("[ACP Transport] -> \(jsonStr, privacy: .public)")
        }
        
        // ACP uses newline-delimited JSON
        var messageData = data
        messageData.append(contentsOf: [0x0A]) // newline
        
        do {
            try stdin.fileHandleForWriting.write(contentsOf: messageData)
        } catch {
            let terminationReason = process?.terminationReason
            let exitCode = process?.terminationStatus
            throw TransportError.sendFailed("Write failed: \(error.localizedDescription) (Process status: \(String(describing: terminationReason)), exit: \(String(describing: exitCode)))")
        }
    }
    
    private func startReadingError() {
        guard let stderr = stderrPipe else { return }
        
        let fileHandle = stderr.fileHandleForReading
        
        errorReadingTask = Task.detached {
            do {
                for try await line in fileHandle.bytes.lines {
                    Self.logger.error("[ACP Agent Error] \(line, privacy: .public)")
                }
            } catch {
                // Ignore cancellation errors
                if !(error is CancellationError) {
                    Self.logger.error("[ACP] stderr read error: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
    
    private func startReadingOutput() {
        guard let stdout = stdoutPipe else { return }
        
        let fileHandle = stdout.fileHandleForReading
        
        // Use a background thread to poll for available data
        // This is more reliable than bytes.lines for process output
        readingTask = Task.detached { [weak self] in
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP Transport] Started reading stdout")
            }
            var lineBuffer = ""
            
            do {
                while true {
                    // Check for cancellation
                    try Task.checkCancellation()
                    
                    // Read available data
                    let data = fileHandle.availableData
                    
                    if data.isEmpty {
                        // Empty data means EOF - pipe closed
                        if Self.isVerboseLoggingEnabled {
                            Self.logger.debug("[ACP Transport] stdout EOF reached")
                        }
                        
                        // Process any remaining data in buffer
                        if !lineBuffer.isEmpty {
                            await self?.handleIncomingLine(lineBuffer)
                        }
                        break
                    }
                    
                    guard let str = String(data: data, encoding: .utf8) else {
                        continue
                    }
                    
                    // Add to buffer and process complete lines
                    lineBuffer += str
                    
                    while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
                        let line = String(lineBuffer[..<newlineIndex])
                        lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])
                        
                        if !line.isEmpty {
                            await self?.handleIncomingLine(line)
                        }
                    }
                }
            } catch is CancellationError {
                // Normal cancellation - ignore
            } catch {
                Self.logger.error("[ACP Transport] Read error: \(String(describing: error), privacy: .public)")
            }
            
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP Transport] stdout reader exiting")
            }
        }
    }
    
    private func handleIncomingLine(_ line: String) async {
        // Skip empty lines
        guard !line.isEmpty else { return }
        
        // Skip if it doesn't look like JSON (should start with '{')
        guard line.hasPrefix("{") else {
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP] Skipping non-JSON line: \(String(line.prefix(100)), privacy: .public)")
            }
            return
        }
        
        guard let data = line.data(using: .utf8) else {
            Self.logger.error("[ACP] Failed to convert line to data")
            return
        }
        
        if Self.isVerboseLoggingEnabled {
            Self.logger.debug("[ACP Transport] <- \(line, privacy: .public)")
        }
        
        do {
            let message = try IncomingMessage.parse(data)
            await handleMessage(message)
        } catch {
            Self.logger.error("[ACP] Failed to parse message (length: \(line.count, privacy: .public)): \(String(describing: error), privacy: .public)")
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP] Message preview: \(String(line.prefix(200)), privacy: .public)...\(String(line.suffix(100)), privacy: .public)")
            }
        }
    }
    
    private func handleMessage(_ message: IncomingMessage) async {
        switch message {
        case .response(let id, let result):
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP Transport] Handling response for id: \(id, privacy: .public)")
            }
            if timingEnabled, let timing = requestTimings.removeValue(forKey: id) {
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
                Self.logger.info("[ACP Timing] request.end id=\(id, privacy: .public) method=\(timing.method, privacy: .public) ms=\(String(format: "%.2f", elapsedMs), privacy: .public) responseBytes=\(result.count, privacy: .public)")
            }
            if let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: result)
            }
            
        case .error(let id, let error):
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP Transport] Handling error for id: \(String(describing: id), privacy: .public)")
            }
            if timingEnabled, let id, let timing = requestTimings.removeValue(forKey: id) {
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
                Self.logger.info("[ACP Timing] request.error id=\(id, privacy: .public) method=\(timing.method, privacy: .public) ms=\(String(format: "%.2f", elapsedMs), privacy: .public) error=\(error.message, privacy: .public)")
            }
            if let id, let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(throwing: error)
            }
            // Also forward to handler for visibility
            await messageHandler?(message)
            
        case .notification(let method, _):
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP Transport] Handling notification: \(method, privacy: .public)")
            }
            await messageHandler?(message)
            
        case .request(let id, let method, _):
            if Self.isVerboseLoggingEnabled {
                Self.logger.debug("[ACP Transport] Handling request: \(method, privacy: .public), id: \(id, privacy: .public)")
            }
            await messageHandler?(message)
        }
    }
}

#else

import Foundation

/// visionOS/iOS fallback: process spawning transport is unavailable.
actor ProcessTransport {
    private let command: String
    private let arguments: [String]
    private let workingDirectory: URL?
    private var requestCounter: Int = 0

    public var isConnected: Bool { false }

    public init(command: String, arguments: [String] = [], workingDirectory: URL? = nil) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    public func setMessageHandler(_ handler: @escaping @Sendable (IncomingMessage) async -> Void) {}

    public func connect() async throws {
        let details = "Process transport is unsupported on this platform (\(command) \(arguments.joined(separator: " ")))."
        throw TransportError.failedToLaunch(
            NSError(domain: "io.210x7.swift-acp", code: 1, userInfo: [NSLocalizedDescriptionKey: details])
        )
    }

    public func disconnect() {}

    public func nextRequestID() -> RequestID {
        requestCounter += 1
        return .string("\(requestCounter)")
    }

    public func sendRequest<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        method: String,
        params: Params?
    ) async throws -> Result {
        _ = method
        _ = params
        throw TransportError.disconnected
    }

    public func sendNotification<Params: Encodable & Sendable>(
        method: String,
        params: Params?
    ) async throws {
        _ = method
        _ = params
        throw TransportError.disconnected
    }

    public func sendResponse<Result: Encodable & Sendable>(
        id: RequestID,
        result: Result
    ) async throws {
        _ = id
        _ = result
        throw TransportError.disconnected
    }

    public func sendErrorResponse(
        id: RequestID,
        code: Int,
        message: String
    ) async throws {
        _ = id
        _ = code
        _ = message
        throw TransportError.disconnected
    }
}

#endif
