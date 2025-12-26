//
//  ACPClientDelegate.swift
//  swift-acp
//
//  Delegate protocol for handling agent callbacks.
//

import Foundation

/// Delegate protocol for receiving agent notifications and handling requests
@MainActor
public protocol ACPClientDelegate: AnyObject, Sendable {
    
    /// Called when the agent sends a session update (streaming content, tool calls, plans)
    /// - Parameters:
    ///   - client: The ACP client
    ///   - update: The session update
    func client(_ client: ACPClient, didReceiveUpdate update: SessionUpdate)
    
    /// Called when the agent requests permission to perform an action
    /// - Parameters:
    ///   - client: The ACP client
    ///   - request: The permission request with options
    /// - Returns: The selected option ID
    func client(_ client: ACPClient, requestPermission request: RequestPermissionRequest) async -> PermissionOptionID
    
    /// Called when the agent wants to read a file
    /// - Parameters:
    ///   - client: The ACP client
    ///   - path: Path to the file
    /// - Returns: File contents
    /// - Throws: If file cannot be read
    func client(_ client: ACPClient, readFile path: String) async throws -> String
    
    /// Called when the agent wants to write a file
    /// - Parameters:
    ///   - client: The ACP client
    ///   - path: Path to the file
    ///   - content: Content to write
    /// - Throws: If file cannot be written
    func client(_ client: ACPClient, writeFile path: String, content: String) async throws
    
    // MARK: - Tools
    
    /// List available tools provided by this client
    func listTools(_ client: ACPClient) async -> [ToolDefinition]
    
    /// Call a tool
    func client(_ client: ACPClient, callTool name: String, arguments: [String: Any]) async throws -> CallToolResponse
}

// MARK: - Default Implementations

public extension ACPClientDelegate {
    
    func client(_ client: ACPClient, didReceiveUpdate update: SessionUpdate) {
        // Default: do nothing
    }
    
    func client(_ client: ACPClient, requestPermission request: RequestPermissionRequest) async -> PermissionOptionID {
        // Default: reject once
        return "reject_once"
    }
    
    func client(_ client: ACPClient, readFile path: String) async throws -> String {
        throw ACPError.protocolError("File read not implemented")
    }
    
    func client(_ client: ACPClient, writeFile path: String, content: String) async throws {
        throw ACPError.protocolError("File write not implemented")
    }
    
    func listTools(_ client: ACPClient) async -> [ToolDefinition] {
        return []
    }
    
    func client(_ client: ACPClient, callTool name: String, arguments: [String: Any]) async throws -> CallToolResponse {
        return CallToolResponse(success: false, content: [.init(type: "text", text: "Tools not implemented")])
    }
}
