//
//  JSONRPCMessage.swift
//  swift-acp
//
//  JSON-RPC 2.0 message types for ACP communication.
//

import Foundation

// MARK: - JSON-RPC 2.0 Base Types

/// JSON-RPC 2.0 request message
public struct JSONRPCRequest<Params: Encodable & Sendable>: Encodable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: RequestID
    public let method: String
    public let params: Params?
    
    public init(id: RequestID, method: String, params: Params? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 notification (no id, no response expected)
public struct JSONRPCNotification<Params: Encodable & Sendable>: Encodable, Sendable {
    public let jsonrpc: String = "2.0"
    public let method: String
    public let params: Params?
    
    public init(method: String, params: Params? = nil) {
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 success response
public struct JSONRPCResponse<Result: Decodable & Sendable>: Decodable, Sendable {
    public let jsonrpc: String
    public let id: RequestID
    public let result: Result
}

/// JSON-RPC 2.0 error response
public struct JSONRPCErrorResponse: Decodable, Sendable {
    public let jsonrpc: String
    public let id: RequestID?
    public let error: JSONRPCError
}

/// JSON-RPC 2.0 error object
public struct JSONRPCError: Decodable, Sendable, Error, LocalizedError {
    public let code: Int
    public let message: String
    public let data: AnyCodable?
    
    public var errorDescription: String? {
        "[\(code)] \(message)"
    }
    
    // Standard JSON-RPC error codes
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
    
    // ACP-specific error codes
    public static let authRequired = -32000
    public static let resourceNotFound = -32002
}

// MARK: - Dynamic Message Parsing

/// Incoming message from an agent (could be response, notification, or request)
public enum IncomingMessage: Sendable {
    case response(id: RequestID, result: Data)
    case error(id: RequestID?, error: JSONRPCError)
    case notification(method: String, params: Data?)
    case request(id: RequestID, method: String, params: Data?)
    
    /// Parse a raw JSON data message
    public static func parse(_ data: Data) throws -> IncomingMessage {
        let decoder = JSONDecoder()
        
        // First, try to decode as a generic structure to determine type
        struct MessageProbe: Decodable {
            let id: RequestID?
            let method: String?
            let result: AnyCodable?
            let error: JSONRPCError?
            let params: AnyCodable?
        }
        
        do {
            let probe = try decoder.decode(MessageProbe.self, from: data)
            
            // Error response
            if let error = probe.error {
                return .error(id: probe.id, error: error)
            }
            
            // Success response (has id + result)
            if let id = probe.id, probe.result != nil {
                // Re-extract result as raw data for later type-specific decoding
                struct ResultExtractor: Decodable {
                    let result: AnyCodable
                }
                let extractor = try decoder.decode(ResultExtractor.self, from: data)
                let resultData = try JSONEncoder().encode(extractor.result)
                return .response(id: id, result: resultData)
            }
            
            // Request from agent (has id + method)
            if let id = probe.id, let method = probe.method {
                var paramsData: Data? = nil
                if probe.params != nil {
                    struct ParamsExtractor: Decodable {
                        let params: AnyCodable
                    }
                    let extractor = try decoder.decode(ParamsExtractor.self, from: data)
                    paramsData = try JSONEncoder().encode(extractor.params)
                }
                return .request(id: id, method: method, params: paramsData)
            }
            
            // Notification (has method, no id)
            if let method = probe.method {
                var paramsData: Data? = nil
                if probe.params != nil {
                    struct ParamsExtractor: Decodable {
                        let params: AnyCodable
                    }
                    let extractor = try decoder.decode(ParamsExtractor.self, from: data)
                    paramsData = try JSONEncoder().encode(extractor.params)
                }
                return .notification(method: method, params: paramsData)
            }
            
            throw JSONRPCError(code: JSONRPCError.parseError, message: "Unable to determine message type", data: Optional<AnyCodable>.none)
        } catch {
            let jsonString = String(data: data, encoding: .utf8) ?? "binary data"
            print("[ACP] Parse error: \(error)\nMessage: \(jsonString)")
            throw error
        }
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable for dynamic JSON handling
/// Note: Uses @unchecked Sendable since we only store JSON-compatible primitives
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}
