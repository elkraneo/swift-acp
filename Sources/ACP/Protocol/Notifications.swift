//
//  Notifications.swift
//  swift-acp
//
//  ACP notification types for session updates and progress reporting.
//

import Foundation

// MARK: - Session Update Notification

/// Session update notification from agent
public struct SessionUpdateNotification: Codable, Sendable {
    /// Session ID
    public var sessionId: SessionID
    
    /// Update content
    public var update: SessionUpdate
}

/// A session update containing progress information
public struct SessionUpdate: Codable, Sendable {
    /// Message chunks
    public var messageChunks: [MessageChunk]?
    
    /// Tool call updates
    public var toolCalls: [ToolCallUpdate]?
    
    /// Plan updates
    public var plan: Plan?
    
    /// Available commands
    public var commands: [SlashCommand]?
    
    /// Mode changes
    public var modes: SessionModeState?
    
    public init(from decoder: Decoder) throws {
        // Try decoding as a tagged union first
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Define specific keys for tagged union parsing
        enum TagKeys: String, CodingKey {
            case sessionUpdate
            case content
            case toolCallId
            case status
            case rawInput
            case availableCommands
            case title
            case kind
        }
        
        let tagContainer = try decoder.container(keyedBy: TagKeys.self)
        
        // If 'sessionUpdate' discriminator exists, decode based on it
        if let type = try? tagContainer.decode(String.self, forKey: .sessionUpdate) {
            // Initialize all to nil by default
            self.messageChunks = nil
            self.toolCalls = nil
            self.plan = nil
            self.commands = nil
            self.modes = nil
            
            switch type {
            case "agent_message_chunk":
                if let content = try? tagContainer.decode(MessageChunk.self, forKey: .content) {
                    self.messageChunks = [content]
                }
                
            case "tool_call":
                let id = try tagContainer.decode(String.self, forKey: .toolCallId)
                let status = (try? tagContainer.decode(ToolCallStatus.self, forKey: .status)) ?? .pending
                let title = (try? tagContainer.decode(String.self, forKey: .title)) ?? "Tool Call"
                let input = try? tagContainer.decode(AnyCodable.self, forKey: .rawInput)
                
                let update = ToolCallUpdate(
                    id: id,
                    name: title,
                    status: status,
                    arguments: input,
                    result: nil,
                    error: nil
                )
                self.toolCalls = [update]
                
            case "tool_call_update":
                let id = try tagContainer.decode(String.self, forKey: .toolCallId)
                let status = (try? tagContainer.decode(ToolCallStatus.self, forKey: .status)) ?? .running
                let title = (try? tagContainer.decode(String.self, forKey: .title)) ?? "Tool"
                let content = try? tagContainer.decode([ToolResultContent].self, forKey: .content)
                
                var result: ToolCallResult? = nil
                if let content = content {
                    result = ToolCallResult(success: status == .complete, content: content)
                }
                
                // Use title for name (client can merge with known state for initial call)
                let update = ToolCallUpdate(
                    id: id,
                    name: title,
                    status: status,
                    arguments: nil,
                    result: result,
                    error: nil
                )
                self.toolCalls = [update]
                
            case "available_commands_update":
                self.commands = try? tagContainer.decode([SlashCommand].self, forKey: .availableCommands)
                
            default:
                // Unknown update type, ignore
                break
            }
        } else {
            // Fallback to standard decoding if no discriminator
            self.messageChunks = try container.decodeIfPresent([MessageChunk].self, forKey: .messageChunks)
            self.toolCalls = try container.decodeIfPresent([ToolCallUpdate].self, forKey: .toolCalls)
            self.plan = try container.decodeIfPresent(Plan.self, forKey: .plan)
            self.commands = try container.decodeIfPresent([SlashCommand].self, forKey: .commands)
            self.modes = try container.decodeIfPresent(SessionModeState.self, forKey: .modes)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case messageChunks
        case toolCalls
        case plan
        case commands = "availableCommands"
        case modes
    }
}

// MARK: - Message Chunks

/// A chunk of message content from the agent
public struct MessageChunk: Codable, Sendable {
    /// The content type
    public var type: MessageChunkType
    
    /// Content payload (varies by type)
    public var text: String?
    public var toolCallId: String?
    public var data: String?
    public var mimeType: String?
}

/// Types of message chunks
public enum MessageChunkType: String, Codable, Sendable {
    case text = "text"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case image = "image"
    case audio = "audio"
}

// MARK: - Tool Calls

/// Update about a tool call in progress
public struct ToolCallUpdate: Codable, Sendable {
    /// Unique identifier for this tool call
    public var id: String
    
    /// Tool name
    public var name: String
    
    /// Current status
    public var status: ToolCallStatus
    
    /// Tool arguments (JSON)
    public var arguments: AnyCodable?
    
    /// Result (when complete)
    public var result: ToolCallResult?
    
    /// Error (if failed)
    public var error: String?
}

/// Status of a tool call
public enum ToolCallStatus: String, Codable, Sendable {
    case pending = "pending"
    case running = "running"
    case complete = "complete"
    case failed = "failed"
    case cancelled = "cancelled"
}

/// Result of a tool call
public struct ToolCallResult: Codable, Sendable {
    /// Success indicator
    public var success: Bool
    
    /// Result content
    public var content: [ToolResultContent]?
}

/// Content of a tool result
public struct ToolResultContent: Codable, Sendable {
    /// Content type
    public var type: String
    
    /// Text content
    public var text: String?
    
    /// Image data (base64)
    public var data: String?
    
    /// MIME type for non-text content
    public var mimeType: String?
    
    public init(type: String = "text", text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }
}

// MARK: - Plans

/// An execution plan from the agent
public struct Plan: Codable, Sendable {
    /// Plan entries (tasks)
    public var entries: [PlanEntry]
    
    /// Optional title
    public var title: String?
}

/// An entry in an execution plan
public struct PlanEntry: Codable, Sendable {
    /// Entry identifier
    public var id: String
    
    /// Human-readable title
    public var title: String
    
    /// Current status
    public var status: PlanEntryStatus
    
    /// Child entries (for hierarchical plans)
    public var children: [PlanEntry]?
}

/// Status of a plan entry
public enum PlanEntryStatus: String, Codable, Sendable {
    case pending = "pending"
    case inProgress = "in_progress"
    case complete = "complete"
    case failed = "failed"
    case skipped = "skipped"
}

// MARK: - Slash Commands

/// A slash command advertised by the agent
public struct SlashCommand: Codable, Sendable {
    /// Command name (without slash)
    public var name: String
    
    /// Description
    public var description: String?
    
    /// Arguments specification
    public var arguments: [SlashCommandArgument]?
}

/// Argument for a slash command
public struct SlashCommandArgument: Codable, Sendable {
    /// Argument name
    public var name: String
    
    /// Whether required
    public var required: Bool
    
    /// Description
    public var description: String?
}

// MARK: - Cancel Notification

/// Notification to cancel an ongoing prompt
public struct CancelNotification: Codable, Sendable {
    /// Session ID
    public var sessionId: SessionID
    
    public init(sessionId: SessionID) {
        self.sessionId = sessionId
    }
}
