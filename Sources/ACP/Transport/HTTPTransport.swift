//
//  HTTPTransport.swift
//  swift-acp
//
//  Transport layer for ACP communication via HTTP.
//

import Foundation
import OSLog

/// HTTP transport for connecting to ACP servers
actor HTTPTransport {

    // MARK: - Properties

    private static let logger = Logger(subsystem: "io.210x7.swift-acp", category: "transport")
    private let baseURL: URL
    private let session: URLSession

    private var pendingRequests: [RequestID: CheckedContinuation<Data, Error>] = [:]
    private var requestCounter: Int = 0
    private var requestTimings: [RequestID: RequestTiming] = [:]

    private let timingEnabled = ProcessInfo.processInfo.environment["ACP_TIMING"] == "1"

    private struct RequestTiming {
        let method: String
        let start: DispatchTime
        let payloadBytes: Int
    }

    private var messageHandler: (@Sendable (IncomingMessage) async -> Void)?
    private var pollingTask: Task<Void, Never>?

    public var isConnected: Bool {
        true // HTTP is always "connected" once initialized
    }

    // MARK: - Initialization

    /// Create an HTTP transport for the given server URL
    /// - Parameter baseURL: The base URL of the ACP server (e.g., "http://localhost:8000")
    public init(baseURL: URL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    /// Create an HTTP transport from a string URL
    /// - Parameter urlString: The base URL string (e.g., "http://localhost:8000")
    public init(urlString: String) {
        self.baseURL = URL(string: urlString)!
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Connection

    /// Set the handler for incoming messages (notifications and requests from agent)
    public func setMessageHandler(_ handler: @escaping @Sendable (IncomingMessage) async -> Void) {
        self.messageHandler = handler
    }

    /// Connect to the HTTP server
    public func connect() async throws {
        // Verify the server is reachable
        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TransportError.connectionFailed("Server not reachable at \(baseURL)")
        }

        // Start polling for server-initiated messages
        startPolling()
    }

    /// Disconnect from the HTTP server
    public func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: TransportError.disconnected)
        }
        pendingRequests.removeAll()

        requestCounter = 0
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

        try await postJSON(data)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(message)
        try await postJSON(data)
    }

    private func postJSON(_ data: Data) async throws {
        let url = baseURL.appendingPathComponent("message")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError.sendFailed("Invalid response type")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TransportError.sendFailed("Server returned status \(httpResponse.statusCode)")
        }
    }

    private func startPolling() {
        pollingTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    try await self?.pollForMessages()
                } catch {
                    // Silently continue polling
                }

                // Wait before next poll
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
    }

    private func pollForMessages() async throws {
        let url = baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            // 204 No Content means no messages available
            if httpResponse.statusCode == 204 { return }

            guard (200...299).contains(httpResponse.statusCode) else { return }

            // Parse JSON-RPC messages
            try await parseMessages(from: data)
        } catch {
            // Connection error - server may be down temporarily
        }
    }

    private func parseMessages(from data: Data) async throws {
        // Try to parse as a single JSON object
        if let message = try? IncomingMessage.parse(data) {
            await handleMessage(message)
            return
        }

        // Try to parse as an array of messages
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for dict in array {
                if let messageData = try? JSONSerialization.data(withJSONObject: dict),
                   let message = try? IncomingMessage.parse(messageData) {
                    await handleMessage(message)
                }
            }
        }
    }

    private func handleMessage(_ message: IncomingMessage) async {
        switch message {
        case .response(let id, let result):
            if timingEnabled, let timing = requestTimings.removeValue(forKey: id) {
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
                Self.logger.info("[ACP Timing] request.end id=\(id, privacy: .public) method=\(timing.method, privacy: .public) ms=\(String(format: "%.2f", elapsedMs), privacy: .public) responseBytes=\(result.count, privacy: .public)")
            }
            if let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: result)
            }
            await messageHandler?(message)

        case .error(let id, let error):
            if timingEnabled, let id, let timing = requestTimings.removeValue(forKey: id) {
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - timing.start.uptimeNanoseconds) / 1_000_000
                Self.logger.info("[ACP Timing] request.error id=\(id, privacy: .public) method=\(timing.method, privacy: .public) ms=\(String(format: "%.2f", elapsedMs), privacy: .public) error=\(error.message, privacy: .public)")
            }
            if let id, let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(throwing: error)
            }
            await messageHandler?(message)

        case .notification:
            await messageHandler?(message)

        case .request:
            await messageHandler?(message)
        }
    }
}
