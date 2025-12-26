//
//  AgentRequests.swift
//  swift-acp
//
//  Requests sent from the agent to the client (permission, file operations, terminals).
//

import Foundation

// MARK: - Permission Request

/// Request from agent to client for permission to perform an action
public struct RequestPermissionRequest: Codable, Sendable {
    /// Unique identifier for the session
    public var sessionId: String?
    
    /// Description of what permission is needed
    public var description: String?
    
    /// Tool call context this permission is for
    public var toolCall: ToolCallContext?
    
    /// Legacy tool call ID
    public var toolCallId: String?
    
    /// Available options for the user
    public var options: [PermissionOption]
    
    /// Content to display (tool details)
    public var content: [AnyCodable]?
    
    public init(
        sessionId: String? = nil,
        description: String? = nil,
        toolCall: ToolCallContext? = nil,
        toolCallId: String? = nil,
        options: [PermissionOption],
        content: [AnyCodable]? = nil
    ) {
        self.sessionId = sessionId
        self.description = description
        self.toolCall = toolCall
        self.toolCallId = toolCallId
        self.options = options
        self.content = content
    }
}

/// Context for a tool call associated with a permission request
public struct ToolCallContext: Codable, Sendable {
    /// ID of the tool call
    public var toolCallId: String
    
    /// Raw input to the tool
    public var rawInput: [String: AnyCodable]?
    
    /// Title/description of the tool call
    public var title: String?
    
    public init(toolCallId: String, rawInput: [String: AnyCodable]? = nil, title: String? = nil) {
        self.toolCallId = toolCallId
        self.rawInput = rawInput
        self.title = title
    }
}

/// An option for responding to a permission request
public struct PermissionOption: Codable, Sendable {
    /// Unique identifier
    public var optionId: PermissionOptionID
    
    /// Human-readable label
    public var name: String
    
    /// Kind of permission option
    public var kind: PermissionOptionKind
    
    public init(optionId: PermissionOptionID, name: String, kind: PermissionOptionKind) {
        self.optionId = optionId
        self.name = name
        self.kind = kind
    }
}

/// Types of permission options
public enum PermissionOptionKind: String, Codable, Sendable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectOnce = "reject_once"
    case rejectAlways = "reject_always"
}

/// Content to display with permission request
public struct PermissionContent: Codable, Sendable {
    /// Content type
    public var type: String
    
    /// Text content
    public var text: String?
    
    /// Terminal ID (for terminal content)
    public var terminalId: TerminalID?
    
    public init(type: String, text: String? = nil, terminalId: TerminalID? = nil) {
        self.type = type
        self.text = text
        self.terminalId = terminalId
    }
}

/// Response to a permission request
public struct RequestPermissionResponse: Codable, Sendable {
    /// The outcome of the permission request
    public var outcome: PermissionOutcome
    
    public init(optionId: PermissionOptionID) {
        self.outcome = PermissionOutcome(outcome: "selected", optionId: optionId)
    }
}

/// The outcome of a permission request
public struct PermissionOutcome: Codable, Sendable {
    /// "selected" or "cancelled"
    public var outcome: String
    /// The selected option ID
    public var optionId: PermissionOptionID?
    
    public init(outcome: String, optionId: PermissionOptionID? = nil) {
        self.outcome = outcome
        self.optionId = optionId
    }
}

// MARK: - File System Requests

/// Request to read a text file
public struct ReadTextFileRequest: Codable, Sendable {
    /// Path to the file
    public var path: String
}

/// Response with file contents
public struct ReadTextFileResponse: Codable, Sendable {
    /// File content
    public var content: String
    
    public init(content: String) {
        self.content = content
    }
}

/// Request to write a text file
public struct WriteTextFileRequest: Codable, Sendable {
    /// Path to the file
    public var path: String
    
    /// Content to write
    public var content: String
}

/// Response confirming write
public struct WriteTextFileResponse: Codable, Sendable {
    /// Whether the write was successful
    public var success: Bool
    
    public init(success: Bool) {
        self.success = success
    }
}

// MARK: - Terminal Requests

/// Request to create a new terminal
public struct CreateTerminalRequest: Codable, Sendable {
    /// Command to run
    public var command: String
    
    /// Working directory
    public var cwd: String?
    
    /// Environment variables
    public var env: [String: String]?
}

/// Response with terminal ID
public struct CreateTerminalResponse: Codable, Sendable {
    /// Terminal identifier
    public var terminalId: TerminalID
    
    public init(terminalId: TerminalID) {
        self.terminalId = terminalId
    }
}

/// Request for terminal output
public struct TerminalOutputRequest: Codable, Sendable {
    /// Terminal identifier
    public var terminalId: TerminalID
}

/// Response with terminal output
public struct TerminalOutputResponse: Codable, Sendable {
    /// Current output content
    public var content: String
    
    /// Exit status (if exited)
    public var exitStatus: Int?
    
    public init(content: String, exitStatus: Int? = nil) {
        self.content = content
        self.exitStatus = exitStatus
    }
}

/// Request to release a terminal
public struct ReleaseTerminalRequest: Codable, Sendable {
    /// Terminal identifier
    public var terminalId: TerminalID
}

/// Response confirming release
public struct ReleaseTerminalResponse: Codable, Sendable {
    public init() {}
}

/// Request to wait for terminal exit
public struct WaitForTerminalExitRequest: Codable, Sendable {
    /// Terminal identifier
    public var terminalId: TerminalID
    
    /// Timeout in milliseconds
    public var timeoutMs: Int?
}

/// Response with exit status
public struct WaitForTerminalExitResponse: Codable, Sendable {
    /// Exit status code
    public var exitStatus: Int
    
    public init(exitStatus: Int) {
        self.exitStatus = exitStatus
    }
}

/// Request to kill terminal command
public struct KillTerminalCommandRequest: Codable, Sendable {
    /// Terminal identifier
    public var terminalId: TerminalID
}

/// Response confirming kill
public struct KillTerminalCommandResponse: Codable, Sendable {
    public init() {}
}
// MARK: - Tool Requests

/// Request from agent to list available tools
public struct ListToolsRequest: Codable, Sendable {
    public init() {}
}

/// A tool definition
public struct ToolDefinition: Codable, Sendable {
    /// Unique name of the tool
    public var name: String
    
    /// Human-readable description
    public var description: String
    
    /// JSON schema for tool parameters
    public var parameters: [String: AnyCodable]
    
    public init(name: String, description: String, parameters: [String: AnyCodable]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Response with list of tools
public struct ListToolsResponse: Codable, Sendable {
    /// Available tools
    public var tools: [ToolDefinition]
    
    public init(tools: [ToolDefinition]) {
        self.tools = tools
    }
}

/// Request to call a tool
public struct CallToolRequest: Codable, Sendable {
    /// Name of the tool to call
    public var name: String
    
    /// Tool parameters matching its schema
    public var arguments: [String: AnyCodable]
    
    public init(name: String, arguments: [String: AnyCodable]) {
        self.name = name
        self.arguments = arguments
    }
}

/// Response from tool call
public struct CallToolResponse: Codable, Sendable {
    /// Success or failure
    public var success: Bool
    
    /// Result content (usually text)
    public var content: [ToolResultContent]
    
    public init(success: Bool, content: [ToolResultContent]) {
        self.success = success
        self.content = content
    }
}
