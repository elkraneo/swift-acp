//
//  Requests.swift
//  swift-acp
//
//  Client-to-Agent request types for ACP protocol.
//

import Foundation

// MARK: - Initialize

/// Request to initialize connection and negotiate capabilities
public struct InitializeRequest: Codable, Sendable {
    /// Protocol version (integer)
    public var protocolVersion: Int
    
    /// Supported protocol versions (in order of preference)
    public var supportedVersions: [ProtocolVersion]
    
    /// Client capabilities
    public var capabilities: ClientCapabilities
    
    /// Client information
    public var clientInfo: ClientInfo
    
    public init(
        protocolVersion: Int = 1,
        supportedVersions: [ProtocolVersion] = [.current],
        capabilities: ClientCapabilities = .default,
        clientInfo: ClientInfo
    ) {
        self.protocolVersion = protocolVersion
        self.supportedVersions = supportedVersions
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

/// Client information sent during initialization
public struct ClientInfo: Codable, Sendable {
    /// Name of the client application
    public var name: String
    
    /// Version of the client application
    public var version: String
    
    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// Response from initialize request
public struct InitializeResponse: Codable, Sendable {
    /// Negotiated protocol version
    public var protocolVersion: Int
    
    /// Agent capabilities
    public var capabilities: AgentCapabilities
    
    /// Agent information
    public var agentInfo: AgentInfo
    
    /// Authentication requirements (if any)
    public var authMethods: [AuthenticationMethod]?
    
    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case capabilities = "agentCapabilities"
        case agentInfo
        case authMethods
    }
}

/// Agent information received during initialization
public struct AgentInfo: Codable, Sendable {
    /// Name of the agent
    public var name: String
    
    /// Version of the agent
    public var version: String
}

/// Authentication requirements
public struct AuthenticationInfo: Codable, Sendable {
    /// Available authentication methods
    public var methods: [AuthenticationMethod]
}

/// An authentication method
public struct AuthenticationMethod: Codable, Sendable {
    /// Unique identifier for this method
    public var id: String
    
    /// Human-readable description
    public var description: String?
}

// MARK: - Authenticate

/// Request to authenticate with the agent
public struct AuthenticateRequest: Codable, Sendable {
    /// The authentication method ID to use
    public var methodId: String
    
    public init(methodId: String) {
        self.methodId = methodId
    }
}

/// Response from authenticate request
public struct AuthenticateResponse: Codable, Sendable {
    /// Whether authentication was successful
    public var success: Bool
}

// MARK: - Session

/// Request to create a new session
public struct NewSessionRequest: Codable, Sendable {
    /// Working directory for the session (mapped to 'cwd')
    public var cwd: String
    
    /// MCP server configurations to use
    public var mcpServers: [McpServerConfig]
    
    /// Model to use for this session (e.g., "haiku", "sonnet", "opus")
    public var model: String?
    
    /// Extra metadata for agent configuration (e.g. claudeCode options)
    public var _meta: [String: AnyCodable]?
    
    public init(cwd: String = FileManager.default.currentDirectoryPath, mcpServers: [McpServerConfig] = [], model: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.model = model
        self._meta = _meta
    }
    
    enum CodingKeys: String, CodingKey {
        case cwd
        case mcpServers
        case model = "modelId"
        case _meta
    }
}

/// Response from new session request
public struct NewSessionResponse: Codable, Sendable {
    /// Unique session identifier
    public var sessionId: SessionID
    
    /// Initial mode state (if supported)
    public var modes: SessionModeState?
    
    /// Initial model state (if supported)
    public var models: SessionModelState?
}

/// Session mode state
public struct SessionModeState: Codable, Sendable {
    /// Available modes
    public var available: [SessionMode]
    
    /// Current mode
    public var current: String?
    
    enum CodingKeys: String, CodingKey {
        case available = "availableModes"
        case current = "currentModeId"
    }
}

/// A session mode
public struct SessionMode: Codable, Sendable {
    /// Mode identifier
    public var id: String
    
    /// Human-readable name
    public var name: String
    
    /// Description
    public var description: String?
}

/// Session model state
public struct SessionModelState: Codable, Sendable {
    /// Available models
    public var availableModels: [SessionModel]
    
    /// Current model ID
    public var currentModelId: String?
}

/// A session model
public struct SessionModel: Codable, Sendable, Identifiable {
    public var id: String { modelId }
    
    /// Model identifier (e.g., "gpt-5.2-codex (medium)")
    public var modelId: String
    
    /// Human-readable display name
    public var name: String
    
    /// Optional description
    public var description: String?
    
    public init(modelId: String, name: String, description: String? = nil) {
        self.modelId = modelId
        self.name = name
        self.description = description
    }
}

/// Request to load an existing session
public struct LoadSessionRequest: Codable, Sendable {
    /// Session ID to load
    public var sessionId: SessionID
    
    public init(sessionId: SessionID) {
        self.sessionId = sessionId
    }
}

/// Response from load session request
public struct LoadSessionResponse: Codable, Sendable {
    /// The loaded session ID
    public var sessionId: SessionID
    
    /// Session mode state
    public var modes: SessionModeState?
    
    /// Session model state
    public var models: SessionModelState?
}


// MARK: - Set Session Model

/// Request to change the model for a session (without reconnecting)
public struct SetSessionModelRequest: Codable, Sendable {
    /// Session ID
    public var sessionId: SessionID
    
    /// Model ID to switch to
    public var modelId: String
    
    public init(sessionId: SessionID, modelId: String) {
        self.sessionId = sessionId
        self.modelId = modelId
    }
}

/// Response from set session model request
public struct SetSessionModelResponse: Codable, Sendable {
    // Empty response - success indicated by no error
    public init() {}
}

// MARK: - Set Session Mode

/// Request to change the mode for a session (without reconnecting)
public struct SetSessionModeRequest: Codable, Sendable {
    /// Session ID
    public var sessionId: SessionID
    
    /// Mode ID to switch to
    public var modeId: String
    
    public init(sessionId: SessionID, modeId: String) {
        self.sessionId = sessionId
        self.modeId = modeId
    }
}

/// Response from set session mode request
public struct SetSessionModeResponse: Codable, Sendable {
    // Empty response - success indicated by no error
    public init() {}
}

// MARK: - Prompt

/// Request to send a prompt to the agent
public struct PromptRequest: Codable, Sendable {
    /// Session ID
    public var sessionId: SessionID
    
    /// The prompt content
    public var content: [PromptContent]
    
    public init(sessionId: SessionID, content: [PromptContent]) {
        self.sessionId = sessionId
        self.content = content
    }
    
    /// Convenience initializer for text-only prompts
    public init(sessionId: SessionID, text: String) {
        self.sessionId = sessionId
        self.content = [.text(TextPromptContent(text: text))]
    }
    
    enum CodingKeys: String, CodingKey {
        case sessionId
        case content = "prompt"
    }
}

/// Prompt content types
public enum PromptContent: Codable, Sendable {
    case text(TextPromptContent)
    case image(ImagePromptContent)
    case audio(AudioPromptContent)
    case context(ContextPromptContent)
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            self = .text(try TextPromptContent(from: decoder))
        case "image":
            self = .image(try ImagePromptContent(from: decoder))
        case "audio":
            self = .audio(try AudioPromptContent(from: decoder))
        case "context":
            self = .context(try ContextPromptContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown prompt content type: \(type)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .audio(let content):
            try content.encode(to: encoder)
        case .context(let content):
            try content.encode(to: encoder)
        }
    }
}

/// Text prompt content
public struct TextPromptContent: Codable, Sendable {
    public var type: String = "text"
    public var text: String
    
    public init(text: String) {
        self.text = text
    }
}

/// Image prompt content
public struct ImagePromptContent: Codable, Sendable {
    public var type: String = "image"
    public var data: String  // Base64
    public var mimeType: String
    
    public init(data: String, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Audio prompt content
public struct AudioPromptContent: Codable, Sendable {
    public var type: String = "audio"
    public var data: String  // Base64
    public var mimeType: String
    
    public init(data: String, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Context prompt content (embedded context)
public struct ContextPromptContent: Codable, Sendable {
    public var type: String = "context"
    public var uri: String
    public var text: String?
    
    public init(uri: String, text: String? = nil) {
        self.uri = uri
        self.text = text
    }
}

/// Response from prompt request
public struct PromptResponse: Codable, Sendable {
    /// Reason the prompt turn ended
    public var stopReason: StopReason
    
    /// Token usage statistics
    public var usage: TokenUsage?
}

/// Reasons a prompt turn can end
public enum StopReason: String, Codable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case cancelled = "cancelled"
    case error = "error"
}

/// Token usage statistics
public struct TokenUsage: Codable, Sendable {
    /// Input tokens consumed
    public var inputTokens: Int?
    
    /// Output tokens generated
    public var outputTokens: Int?
    
    /// Tokens read from cache (e.g. for Claude)
    public var cacheReadTokens: Int?
    
    /// Tokens used to create cache (e.g. for Claude)
    public var cacheCreationTokens: Int?
    
    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheCreationTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
    }
    
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_input_tokens"
        case cacheCreationTokens = "cache_creation_input_tokens"
    }
}
