//
//  Capabilities.swift
//  swift-acp
//
//  ACP capability types for client and agent negotiation.
//

import Foundation

// MARK: - Client Capabilities

/// Capabilities advertised by the client (Preflight) to the agent
public struct ClientCapabilities: Codable, Sendable, Hashable {
    /// Optional metadata for extensions
    public var _meta: [String: AnyCodable]?
    
    /// Filesystem capabilities
    public var fs: FileSystemCapability?
    
    /// Terminal capabilities
    public var terminal: Bool?
    
    /// MCP server configurations the client can provide
    public var mcpServers: [McpServerConfig]?
    
    /// Tool capabilities (advertising support for tools/list, tools/call)
    public var tools: AnyCodable?
    
    public init(
        fs: FileSystemCapability? = nil,
        terminal: Bool? = nil,
        mcpServers: [McpServerConfig]? = nil,
        tools: AnyCodable? = nil
    ) {
        self.fs = fs
        self.terminal = terminal
        self.mcpServers = mcpServers
        self.tools = tools
    }
    
    /// Default capabilities for a typical client
    public static var `default`: ClientCapabilities {
        ClientCapabilities(
            fs: FileSystemCapability(readTextFile: true, writeTextFile: true),
            terminal: false,
            mcpServers: nil,
            tools: AnyCodable(true)
        )
    }
}

/// Filesystem capabilities supported by the client
public struct FileSystemCapability: Codable, Sendable, Hashable {
    /// Whether the client supports `fs/read_text_file` requests
    public var readTextFile: Bool
    
    /// Whether the client supports `fs/write_text_file` requests
    public var writeTextFile: Bool
    
    public init(readTextFile: Bool = false, writeTextFile: Bool = false) {
        self.readTextFile = readTextFile
        self.writeTextFile = writeTextFile
    }
    
    public static var readWriteTextFile: FileSystemCapability {
        FileSystemCapability(readTextFile: true, writeTextFile: true)
    }
}

/// Configuration for an MCP server the client can provide
public struct McpServerConfig: Codable, Sendable, Hashable {
    /// Unique identifier for this MCP server
    public var id: String
    
    /// Human-readable name
    public var name: String
    
    /// Transport type (stdio, sse, http)
    public var type: String
    
    /// URL for HTTP/SSE transport
    public var url: String?
    
    /// Headers for HTTP/SSE transport
    public var headers: [HttpHeader]
    
    /// Command to launch the server (for stdio)
    public var command: String?
    
    /// Arguments for the command (required for stdio, even if empty)
    public var args: [String]
    
    /// Environment variables for the server process (array format required by ACP)
    public var env: [EnvVar]
    
    public init(
        id: String,
        name: String,
        type: String,
        url: String? = nil,
        headers: [HttpHeader] = [],
        command: String? = nil,
        args: [String] = [],
        env: [EnvVar] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.headers = headers
        self.command = command
        self.args = args
        self.env = env
    }
    
    /// Create an HTTP MCP server configuration
    public static func http(id: String, name: String, url: String, headers: [HttpHeader] = []) -> McpServerConfig {
        McpServerConfig(id: id, name: name, type: "http", url: url, headers: headers)
    }
    
    /// Create a stdio MCP server configuration
    public static func stdio(id: String, name: String, command: String, args: [String] = [], env: [EnvVar] = []) -> McpServerConfig {
        McpServerConfig(id: id, name: name, type: "stdio", command: command, args: args, env: env)
    }
}

/// HTTP header for MCP server
public struct HttpHeader: Codable, Sendable, Hashable {
    public var name: String
    public var value: String
    
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Environment variable for MCP server
public struct EnvVar: Codable, Sendable, Hashable {
    public var name: String
    public var value: String
    
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

// MARK: - Agent Capabilities

/// Capabilities advertised by the agent
public struct AgentCapabilities: Codable, Sendable, Hashable {
    /// Optional metadata for extensions
    public var _meta: [String: AnyCodable]?
    
    /// Whether the agent supports loading sessions
    public var loadSession: Bool?
    
    /// MCP capabilities
    public var mcpCapabilities: McpCapabilities?
    
    /// Prompt input capabilities
    public var promptCapabilities: PromptCapabilities?
    
    /// Session capabilities
    public var sessionCapabilities: SessionCapabilities?
    
    public init(
        loadSession: Bool? = nil,
        mcpCapabilities: McpCapabilities? = nil,
        promptCapabilities: PromptCapabilities? = nil,
        sessionCapabilities: SessionCapabilities? = nil
    ) {
        self.loadSession = loadSession
        self.mcpCapabilities = mcpCapabilities
        self.promptCapabilities = promptCapabilities
        self.sessionCapabilities = sessionCapabilities
    }
}

/// MCP transport capabilities supported by the agent
public struct McpCapabilities: Codable, Sendable, Hashable {
    /// Whether HTTP transport is supported
    public var http: Bool?
    
    /// Whether SSE transport is supported
    public var sse: Bool?
    
    public init(http: Bool? = nil, sse: Bool? = nil) {
        self.http = http
        self.sse = sse
    }
}

/// Prompt input capabilities
public struct PromptCapabilities: Codable, Sendable, Hashable {
    /// Whether audio input is supported
    public var audio: Bool?
    
    /// Whether embedded context is supported
    public var embeddedContext: Bool?
    
    /// Whether image input is supported
    public var image: Bool?
    
    public init(audio: Bool? = nil, embeddedContext: Bool? = nil, image: Bool? = nil) {
        self.audio = audio
        self.embeddedContext = embeddedContext
        self.image = image
    }
}

/// Session capabilities
public struct SessionCapabilities: Codable, Sendable, Hashable {
    /// Optional metadata for extensions
    public var _meta: [String: AnyCodable]?
    
    public init() {}
}

// MARK: - Version

/// Protocol version information
public struct ProtocolVersion: Codable, Sendable, Hashable {
    public var major: Int
    public var minor: Int
    public var patch: Int
    
    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
    
    /// Current ACP version supported by this SDK
    public static var current: ProtocolVersion {
        ProtocolVersion(major: 0, minor: 3, patch: 0)
    }
    
    public var stringValue: String {
        "\(major).\(minor).\(patch)"
    }
}

// MARK: - Hashable AnyCodable

extension AnyCodable: Hashable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality based on JSON representation
        guard let lhsData = try? JSONEncoder().encode(lhs),
              let rhsData = try? JSONEncoder().encode(rhs) else {
            return false
        }
        return lhsData == rhsData
    }
    
    public func hash(into hasher: inout Hasher) {
        if let data = try? JSONEncoder().encode(self) {
            hasher.combine(data)
        }
    }
}
