//
//  ACP.swift
//  swift-acp
//
//  Agent Client Protocol (ACP) Swift SDK
//  https://agentclientprotocol.com
//
//  A protocol for connecting any editor to any AI coding agent.
//

// MARK: - Public API Exports

// Transport
@_exported import struct Foundation.URL
@_exported import struct Foundation.Data

// Re-export core types
public typealias SessionID = String
/// A polymorphic ID that can be either a String or an Int (JSON-RPC 2.0)
public enum RequestID: Codable, Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, CustomStringConvertible {
    case string(String)
    case integer(Int)
    
    public init(stringLiteral value: String) {
        self = .string(value)
    }
    
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .integer(intVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else {
            throw DecodingError.typeMismatch(RequestID.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected String or Int for RequestID"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val): try container.encode(val)
        case .integer(let val): try container.encode(val)
        }
    }
    
    public var description: String {
        switch self {
        case .string(let val): return val
        case .integer(let val): return String(val)
        }
    }
    
    /// Value for use with JSONSerialization
    public var jsonSerializableValue: Any {
        switch self {
        case .string(let val): return val
        case .integer(let val): return val
        }
    }
}

public typealias TerminalID = String
public typealias PermissionOptionID = String
