//
//  ClaudeCodeMeta.swift
//  swift-acp
//
//  Typed meta helpers for Claude Code options.
//

import Foundation

/// Typed metadata for Claude Code session configuration
public struct ClaudeCodeMeta: Codable, Sendable {

    // MARK: - Nested Types

    /// Tool permissions configuration
    public struct ToolPermissions: Codable, Sendable {
        /// Tools that are explicitly disallowed
        public let disallowedTools: [String]

        public init(disallowedTools: [String] = []) {
            self.disallowedTools = disallowedTools
        }
    }

    /// Session options
    public struct Options: Codable, Sendable {
        /// Maximum number of parallel tool calls
        public let maxParallelToolCalls: Int?

        /// Whether to auto-approve tool calls
        public let autoApproveTools: Bool?

        /// Whether to show reasoning in output
        public let showReasoning: Bool?

        /// Tool permissions
        public let toolPermissions: ToolPermissions?

        public init(
            maxParallelToolCalls: Int? = nil,
            autoApproveTools: Bool? = nil,
            showReasoning: Bool? = nil,
            toolPermissions: ToolPermissions? = nil
        ) {
            self.maxParallelToolCalls = maxParallelToolCalls
            self.autoApproveTools = autoApproveTools
            self.showReasoning = showReasoning
            self.toolPermissions = toolPermissions
        }
    }

    // MARK: - Properties

    /// Tool permissions
    public var toolPermissions: ToolPermissions?

    /// Session options
    public var options: Options?

    // MARK: - Initialization

    public init(
        toolPermissions: ToolPermissions? = nil,
        options: Options? = nil
    ) {
        self.toolPermissions = toolPermissions
        self.options = options
    }

    // MARK: - Conversion to [String: AnyCodable]

    /// Convert to dictionary compatible with NewSessionRequest._meta
    public func toDictionary() -> [String: AnyCodable] {
        var result: [String: AnyCodable] = [:]

        if let toolPermissions = toolPermissions {
            result["toolPermissions"] = AnyCodable([
                "disallowedTools": AnyCodable(toolPermissions.disallowedTools)
            ])
        }

        if let options = options {
            var optionsDict: [String: Any] = [:]

            if let maxParallelToolCalls = options.maxParallelToolCalls {
                optionsDict["maxParallelToolCalls"] = maxParallelToolCalls
            }

            if let autoApproveTools = options.autoApproveTools {
                optionsDict["autoApproveTools"] = autoApproveTools
            }

            if let showReasoning = options.showReasoning {
                optionsDict["showReasoning"] = showReasoning
            }

            if let toolPermissions = options.toolPermissions {
                optionsDict["toolPermissions"] = [
                    "disallowedTools": toolPermissions.disallowedTools
                ]
            }

            result["options"] = AnyCodable(optionsDict)
        }

        return result
    }
}

// MARK: - Convenience Extensions

extension ClaudeCodeMeta {
    /// Default configuration with no restrictions
    public static let `default` = ClaudeCodeMeta()

    /// Configuration with specific disallowed tools
    /// - Parameter tools: List of tool names to disallow
    /// - Returns: Meta configuration
    public static func withDisallowedTools(_ tools: [String]) -> ClaudeCodeMeta {
        return ClaudeCodeMeta(
            toolPermissions: ToolPermissions(disallowedTools: tools)
        )
    }

    /// Configuration with auto-approve tools enabled
    /// - Parameter disallowedTools: Optional list of tools to not auto-approve
    /// - Returns: Meta configuration
    public static func autoApprove(except disallowedTools: [String] = []) -> ClaudeCodeMeta {
        return ClaudeCodeMeta(
            toolPermissions: ToolPermissions(disallowedTools: disallowedTools),
            options: Options(
                autoApproveTools: true,
                toolPermissions: ToolPermissions(disallowedTools: disallowedTools)
            )
        )
    }

    /// Configuration with reasoning enabled
    /// - Returns: Meta configuration
    public static func withReasoning() -> ClaudeCodeMeta {
        return ClaudeCodeMeta(
            options: Options(showReasoning: true)
        )
    }

    /// Configuration with custom options
    /// - Parameters:
    ///   - maxParallelToolCalls: Maximum parallel tool calls
    ///   - autoApprove: Auto-approve tool calls
    ///   - showReasoning: Show reasoning
    /// - Returns: Meta configuration
    public static func withOptions(
        maxParallelToolCalls: Int? = nil,
        autoApprove: Bool? = nil,
        showReasoning: Bool? = nil
    ) -> ClaudeCodeMeta {
        return ClaudeCodeMeta(
            options: Options(
                maxParallelToolCalls: maxParallelToolCalls,
                autoApproveTools: autoApprove,
                showReasoning: showReasoning
            )
        )
    }
}
