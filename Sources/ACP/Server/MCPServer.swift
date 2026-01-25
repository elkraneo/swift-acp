//
//  MCPServer.swift
//  swift-acp
//
//  Minimal MCP HTTP server implementation.
//  Uses Network.framework for proper HTTP request/response handling.
//

import Foundation
import Network

/// Minimal MCP server for tool exposure via HTTP
public actor MCPServer {

  // MARK: - Types

  /// MCP tool definition
  public struct Tool: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: InputSchema

    public init(name: String, description: String, inputSchema: InputSchema) {
      self.name = name
      self.description = description
      self.inputSchema = inputSchema
    }

    public struct InputSchema: Codable, Sendable {
      public let type: String
      public let properties: [String: Property]?
      public let required: [String]?

      public init(type: String = "object", properties: [String: Property]? = nil, required: [String]? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
      }

      public struct Property: Codable, Sendable {
        public let type: String
        public let description: String?

        public init(type: String, description: String? = nil) {
          self.type = type
          self.description = description
        }
      }
    }
  }

  /// Result from a tool call
  public struct ToolResult: Sendable {
    public let content: [Content]
    public let isError: Bool

    public init(content: [Content], isError: Bool = false) {
      self.content = content
      self.isError = isError
    }

    public enum Content: Sendable {
      case text(String)
    }

    public static func text(_ string: String) -> ToolResult {
      ToolResult(content: [.text(string)])
    }
  }

  /// Tool handler signature
  public typealias ToolHandler = @Sendable ([String: AnyCodable]) async throws -> ToolResult

  // MARK: - Properties

  private let name: String
  private let version: String
  private var tools: [String: Tool] = [:]
  private var toolHandlers: [String: ToolHandler] = [:]
  private var listener: NWListener?
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private var port: UInt16 = 0
  private var isRunning = false

  // MARK: - Initialization

  /// Create a new MCP server
  public init(name: String = "MCP Server", version: String = "1.0.0") {
    self.name = name
    self.version = version
  }

  // MARK: - Tool Registration

  /// Register a tool with the server
  public func registerTool(_ tool: Tool, handler: @escaping ToolHandler) {
    tools[tool.name] = tool
    toolHandlers[tool.name] = handler
  }

  /// Register a simple text-based tool
  public func registerTextTool(
    name: String,
    description: String,
    inputSchema: Tool.InputSchema? = nil,
    handler: @escaping @Sendable ([String: AnyCodable]) async throws -> String
  ) {
    let tool = Tool(
      name: name,
      description: description,
      inputSchema: inputSchema ?? Tool.InputSchema()
    )

    registerTool(tool) { args in
      let text = try await handler(args)
      return .text(text)
    }
  }

  // MARK: - Server Lifecycle

  /// Start the HTTP server on the specified port
  public func start(port: Int = 3000) async throws {
    guard !isRunning else { return }

    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true
    params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(port)))

    let listener = try NWListener(using: params)
    self.listener = listener

    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { return }
      Task {
        await self.handleConnection(connection)
      }
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      listener.stateUpdateHandler = { [weak self] state in
        Task { [weak self] in
          await self?.handleListenerState(state, listener: listener, continuation: continuation)
        }
      }
      listener.start(queue: .global(qos: .userInitiated))
    }

    self.port = UInt16(port)
    self.isRunning = true
  }

  /// Stop the server
  public func stop() {
    listener?.cancel()
    listener = nil
    for connection in connections.values {
      connection.cancel()
    }
    connections.removeAll()
    isRunning = false
  }

  // MARK: - Private

  private func handleListenerState(
    _ state: NWListener.State,
    listener: NWListener,
    continuation: CheckedContinuation<Void, Error>
  ) {
    switch state {
    case .ready:
      continuation.resume()
    case .failed(let error):
      continuation.resume(throwing: error)
    case .cancelled:
      continuation.resume(throwing: NSError(domain: "MCPServer", code: -1, userInfo: nil))
    default:
      break
    }
  }

  private func handleConnection(_ connection: NWConnection) {
    let id = ObjectIdentifier(connection)
    connections[id] = connection

    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        Task {
          await self.receiveData(from: connection)
        }
      case .failed, .cancelled:
        Task {
          await self.removeConnection(id)
        }
        connection.cancel()
      default:
        break
      }
    }

    connection.start(queue: .global(qos: .userInitiated))
  }

  private func removeConnection(_ id: ObjectIdentifier) {
    connections.removeValue(forKey: id)
  }

  private func receiveData(from connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
      guard let self else { return }

      if error != nil {
        Task { await self.removeConnection(ObjectIdentifier(connection)) }
        connection.cancel()
        return
      }

      if isComplete {
        Task { await self.removeConnection(ObjectIdentifier(connection)) }
        connection.cancel()
        return
      }

      guard let data, !data.isEmpty else {
        Task {
          await self.receiveData(from: connection)
        }
        return
      }

      Task {
        await self.handleRequest(data, connection: connection)
      }
    }
  }

  private func handleRequest(_ data: Data, connection: NWConnection) async {
    guard let request = String(data: data, encoding: .utf8) else {
      await sendHttpResponse(statusCode: 400, body: "{\"error\":\"Bad request\"}", to: connection)
      return
    }

    // Parse HTTP request
    let lines = request.split(separator: "\r\n", omittingEmptySubsequences: false)
    guard lines.count > 0 else {
      await sendHttpResponse(statusCode: 400, body: "{\"error\":\"Invalid request\"}", to: connection)
      return
    }

    let requestLine = String(lines[0])
    let parts = requestLine.split(separator: " ")

    guard parts.count >= 2 else {
      await sendHttpResponse(statusCode: 400, body: "{\"error\":\"Invalid request\"}", to: connection)
      return
    }

    let method = String(parts[0])
    let _ = String(parts[1])  // path (reserved for future use)

    // Handle CORS preflight
    if method == "OPTIONS" {
      await sendCorsPreflightResponse(to: connection)
      // Keep receiving
      receiveData(from: connection)
      return
    }

    // Find blank line between headers and body
    var bodyStartIndex = 0
    for i in 0..<lines.count {
      if lines[i].isEmpty {
        bodyStartIndex = i + 1
        break
      }
    }

    let bodyLines = lines[(bodyStartIndex)..<lines.count]
    let body = bodyLines.joined(separator: "\r\n")

    guard let bodyData = body.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
      await sendHttpResponse(statusCode: 400, body: "{\"error\":\"Invalid JSON\"}", to: connection)
      receiveData(from: connection)
      return
    }

    let jsonRpcMethod = json["method"] as? String ?? ""
    let id = json["id"]
    let params = json["params"] as? [String: Any]

    let response: String
    switch jsonRpcMethod {
    case "initialize":
      response = handleInitialize(id: id)
    case "notifications/initialized", "initialized":
      response = handleInitialized(id: id)
    case "tools/list":
      response = handleToolsList(id: id)
    case "tools/call":
      response = await handleToolsCall(id: id, params: params)
    default:
      response = createErrorResponse(id: id, code: -32601, message: "Method not found")
    }

    await sendHttpResponse(statusCode: 200, body: response, to: connection)
    receiveData(from: connection)
  }

  // MARK: - MCP Request Handlers

  private func handleInitialize(id: Any?) -> String {
    let result: [String: Any] = [
      "protocolVersion": "2024-11-05",
      "capabilities": ["tools": [:]],
      "serverInfo": ["name": name, "version": version]
    ]
    return createSuccessResponse(id: id, result: result)
  }

  private func handleInitialized(id: Any?) -> String {
    return createSuccessResponse(id: id, result: [:])
  }

  private func handleToolsList(id: Any?) -> String {
    let toolDicts = tools.values.map { tool -> [String: Any] in
      var dict: [String: Any] = [
        "name": tool.name,
        "description": tool.description
      ]

      if let properties = tool.inputSchema.properties {
        var schema: [String: Any] = ["type": tool.inputSchema.type]
        var propertiesDict: [String: Any] = [:]

        for (key, prop) in properties {
          var propDict: [String: Any] = ["type": prop.type]
          if let desc = prop.description {
            propDict["description"] = desc
          }
          propertiesDict[key] = propDict
        }

        schema["properties"] = propertiesDict
        if let required = tool.inputSchema.required, !required.isEmpty {
          schema["required"] = required
        }
        dict["inputSchema"] = schema
      }

      return dict
    }

    let result: [String: Any] = ["tools": toolDicts]
    return createSuccessResponse(id: id, result: result)
  }

  private func handleToolsCall(id: Any?, params: [String: Any]?) async -> String {
    guard let params = params,
          let name = params["name"] as? String,
          let handler = toolHandlers[name] else {
      return createErrorResponse(id: id, code: -32602, message: "Tool not found")
    }

    let arguments = params["arguments"] as? [String: Any] ?? [:]
    let anyCodableArgs = arguments.mapValues { AnyCodable($0) }

    do {
      let result = try await handler(anyCodableArgs)
      let contentArray = result.content.map { content -> [String: Any] in
        switch content {
        case .text(let text):
          return ["type": "text", "text": text]
        }
      }

      let resultDict: [String: Any] = [
        "content": contentArray,
        "isError": result.isError
      ]
      return createSuccessResponse(id: id, result: resultDict)
    } catch {
      let errorResult: [String: Any] = [
        "content": [["type": "text", "text": "Error: \(error.localizedDescription)"]],
        "isError": true
      ]
      return createSuccessResponse(id: id, result: errorResult)
    }
  }

  // MARK: - Response Building

  private func createSuccessResponse(id: Any?, result: [String: Any]) -> String {
    var response: [String: Any] = ["jsonrpc": "2.0"]
    if let id = id {
      response["id"] = id
    }
    response["result"] = result

    guard let data = try? JSONSerialization.data(withJSONObject: response),
          let string = String(data: data, encoding: .utf8) else {
      return ""
    }
    return string
  }

  private func createErrorResponse(id: Any?, code: Int, message: String) -> String {
    let response: [String: Any] = [
      "jsonrpc": "2.0",
      "id": id ?? NSNull(),
      "error": ["code": code, "message": message]
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: response),
          let string = String(data: data, encoding: .utf8) else {
      return ""
    }
    return string
  }

  private func sendHttpResponse(
    statusCode: Int,
    body: String,
    to connection: NWConnection
  ) async {
    let headers = [
      "HTTP/1.1 \(statusCode) \(statusText(for: statusCode))",
      "Content-Type: application/json",
      "Content-Length: \(body.utf8.count)",
      "Access-Control-Allow-Origin: *",
      "Access-Control-Allow-Methods: POST, GET, OPTIONS",
      "Access-Control-Allow-Headers: Content-Type, MCP-Protocol-Version",
      "Connection: keep-alive",
      "Server: swift-acp/1.0",
      "",
      body
    ].joined(separator: "\r\n")

    guard let data = headers.data(using: .utf8) else { return }

    connection.send(content: data, completion: .contentProcessed { error in
      if let error {
        print("[MCPServer] Send error: \(error)")
      }
    })
  }

  private func sendCorsPreflightResponse(to connection: NWConnection) async {
    let response = [
      "HTTP/1.1 204 No Content",
      "Access-Control-Allow-Origin: *",
      "Access-Control-Allow-Methods: POST, GET, OPTIONS",
      "Access-Control-Allow-Headers: Content-Type, MCP-Protocol-Version",
      "Connection: keep-alive",
      "Server: swift-acp/1.0",
      "",
      ""
    ].joined(separator: "\r\n")

    guard let data = response.data(using: .utf8) else { return }

    connection.send(content: data, completion: .contentProcessed { _ in })
  }

  private func statusText(for code: Int) -> String {
    switch code {
    case 200: return "OK"
    case 204: return "No Content"
    case 400: return "Bad Request"
    case 404: return "Not Found"
    case 500: return "Internal Server Error"
    default: return "OK"
    }
  }
}
