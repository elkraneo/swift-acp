//
//  Models.swift
//  swift-acp
//
//  Core models for ACP protocol metadata and manifest.
//

import Foundation

/// Static details about an agent, for discovery, classification, and cataloging.
public struct AgentManifest: Codable, Sendable {
    /// Unique identifier for the agent
    public var name: String
    
    /// Human-readable description
    public var description: String
    
    /// Real-time dynamic metrics and state
    public var status: AgentStatus?
    
    /// Metadata about the agent
    public var metadata: AgentMetadata?
    
    /// List of supported MIME content types for input
    public var inputContentTypes: [String]?
    
    /// List of supported MIME content types for output
    public var outputContentTypes: [String]?
    
    public init(
        name: String,
        description: String,
        status: AgentStatus? = nil,
        metadata: AgentMetadata? = nil,
        inputContentTypes: [String]? = nil,
        outputContentTypes: [String]? = nil
    ) {
        self.name = name
        self.description = description
        self.status = status
        self.metadata = metadata
        self.inputContentTypes = inputContentTypes
        self.outputContentTypes = outputContentTypes
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case status
        case metadata
        case inputContentTypes = "input_content_types"
        case outputContentTypes = "output_content_types"
    }
}

/// Real-time dynamic metrics and state provided by the system managing the agent.
public struct AgentStatus: Codable, Sendable {
    /// Average tokens per run
    public var avgRunTokens: Double?
    
    /// Average run time in seconds
    public var avgRunTimeSeconds: Double?
    
    /// Percentage of successful runs (0-100)
    public var successRate: Double?
    
    public init(avgRunTokens: Double? = nil, avgRunTimeSeconds: Double? = nil, successRate: Double? = nil) {
        self.avgRunTokens = avgRunTokens
        self.avgRunTimeSeconds = avgRunTimeSeconds
        self.successRate = successRate
    }
    
    enum CodingKeys: String, CodingKey {
        case avgRunTokens = "avg_run_tokens"
        case avgRunTimeSeconds = "avg_run_time_seconds"
        case successRate = "success_rate"
    }
}

/// Metadata about the agent
public struct AgentMetadata: Codable, Sendable {
    /// Key-value annotation metadata
    public var annotations: [String: AnyCodable]?
    
    /// Full agent documentation in markdown
    public var documentation: String?
    
    /// License (SPDX ID)
    public var license: String?
    
    public init(annotations: [String: AnyCodable]? = nil, documentation: String? = nil, license: String? = nil) {
        self.annotations = annotations
        self.documentation = documentation
        self.license = license
    }
}
