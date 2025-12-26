//
//  ACPTests.swift
//  swift-acp
//
//  Tests for ACP protocol types and message handling.
//

import XCTest
@testable import ACP

final class JSONRPCTests: XCTestCase {
    
    // MARK: - Request Encoding
    
    func testRequestEncoding() throws {
        struct TestParams: Codable, Sendable {
            let name: String
            let value: Int
        }
        
        let request = JSONRPCRequest(
            id: "1",
            method: "test/method",
            params: TestParams(name: "test", value: 42)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? String, "1")
        XCTAssertEqual(json["method"] as? String, "test/method")
        
        let params = json["params"] as? [String: Any]
        XCTAssertEqual(params?["name"] as? String, "test")
        XCTAssertEqual(params?["value"] as? Int, 42)
    }
    
    func testNotificationEncoding() throws {
        struct TestParams: Codable, Sendable {
            let message: String
        }
        
        let notification = JSONRPCNotification(
            method: "session/update",
            params: TestParams(message: "hello")
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(notification)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["method"] as? String, "session/update")
        XCTAssertNil(json["id"])  // Notifications have no id
    }
    
    // MARK: - Response Decoding
    
    func testResponseDecoding() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "5",
            "result": {
                "sessionId": "abc123"
            }
        }
        """
        
        struct TestResult: Codable, Sendable {
            let sessionId: String
        }
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JSONRPCResponse<TestResult>.self, from: data)
        
        XCTAssertEqual(response.id, "5")
        XCTAssertEqual(response.result.sessionId, "abc123")
    }
    
    func testErrorResponseDecoding() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "3",
            "error": {
                "code": -32600,
                "message": "Invalid request"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JSONRPCErrorResponse.self, from: data)
        
        XCTAssertEqual(response.id, "3")
        XCTAssertEqual(response.error.code, -32600)
        XCTAssertEqual(response.error.message, "Invalid request")
    }
    
    // MARK: - Message Parsing
    
    func testParseNotification() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "method": "session/update",
            "params": {
                "sessionId": "test"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let message = try IncomingMessage.parse(data)
        
        if case .notification(let method, _) = message {
            XCTAssertEqual(method, "session/update")
        } else {
            XCTFail("Expected notification")
        }
    }
    
    func testParseRequest() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "10",
            "method": "fs/read_text_file",
            "params": {
                "path": "/test.txt"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let message = try IncomingMessage.parse(data)
        
        if case .request(let id, let method, _) = message {
            XCTAssertEqual(id, "10")
            XCTAssertEqual(method, "fs/read_text_file")
        } else {
            XCTFail("Expected request")
        }
    }
    
    func testParseResponse() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "7",
            "result": {
                "success": true
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let message = try IncomingMessage.parse(data)
        
        if case .response(let id, _) = message {
            XCTAssertEqual(id, "7")
        } else {
            XCTFail("Expected response")
        }
    }
    
    func testParseError() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "8",
            "error": {
                "code": -32000,
                "message": "Auth required"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let message = try IncomingMessage.parse(data)
        
        if case .error(let id, let error) = message {
            XCTAssertEqual(id, "8")
            XCTAssertEqual(error.code, -32000)
        } else {
            XCTFail("Expected error")
        }
    }
}

final class SchemaTests: XCTestCase {
    
    // MARK: - Capabilities
    
    func testClientCapabilitiesRoundTrip() throws {
        let capabilities = ClientCapabilities(
            fs: FileSystemCapability(readTextFile: true, writeTextFile: false),
            terminal: true
        )
        
        let data = try JSONEncoder().encode(capabilities)
        let decoded = try JSONDecoder().decode(ClientCapabilities.self, from: data)
        
        XCTAssertEqual(decoded.fs?.readTextFile, true)
        XCTAssertEqual(decoded.fs?.writeTextFile, false)
        XCTAssertEqual(decoded.terminal, true)
    }
    
    func testAgentCapabilitiesDecoding() throws {
        let json = """
        {
            "loadSession": true,
            "promptCapabilities": {
                "audio": false,
                "embeddedContext": true,
                "image": true
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let capabilities = try JSONDecoder().decode(AgentCapabilities.self, from: data)
        
        XCTAssertEqual(capabilities.loadSession, true)
        XCTAssertEqual(capabilities.promptCapabilities?.image, true)
    }
    
    // MARK: - Requests
    
    func testInitializeRequestEncoding() throws {
        let request = InitializeRequest(
            clientInfo: ClientInfo(name: "TestClient", version: "1.0")
        )
        
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertNotNil(json["supportedVersions"])
        XCTAssertNotNil(json["capabilities"])
        
        let clientInfo = json["clientInfo"] as? [String: Any]
        XCTAssertEqual(clientInfo?["name"] as? String, "TestClient")
    }
    
    func testPromptRequestEncoding() throws {
        let request = PromptRequest(sessionId: "sess123", text: "Hello, agent!")
        
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(json["sessionId"] as? String, "sess123")
        
        let content = json["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.first?["text"] as? String, "Hello, agent!")
    }
    
    // MARK: - Notifications
    
    func testSessionUpdateDecoding() throws {
        let json = """
        {
            "sessionId": "sess456",
            "update": {
                "messageChunks": [
                    {
                        "type": "text",
                        "text": "Hello from agent"
                    }
                ]
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let notification = try JSONDecoder().decode(SessionUpdateNotification.self, from: data)
        
        XCTAssertEqual(notification.sessionId, "sess456")
        XCTAssertEqual(notification.update.messageChunks?.first?.text, "Hello from agent")
    }
    
    func testPlanDecoding() throws {
        let json = """
        {
            "title": "Fix the model",
            "entries": [
                {
                    "id": "1",
                    "title": "Analyze up-axis",
                    "status": "complete"
                },
                {
                    "id": "2",
                    "title": "Apply rotation",
                    "status": "in_progress"
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let plan = try JSONDecoder().decode(Plan.self, from: data)
        
        XCTAssertEqual(plan.title, "Fix the model")
        XCTAssertEqual(plan.entries.count, 2)
        XCTAssertEqual(plan.entries[0].status, .complete)
        XCTAssertEqual(plan.entries[1].status, .inProgress)
    }
    
    // MARK: - Permissions
    
    func testPermissionRequestDecoding() throws {
        let json = """
        {
            "description": "Agent wants to modify file",
            "options": [
                {
                    "optionId": "allow",
                    "name": "Allow",
                    "kind": "allow_once"
                },
                {
                    "optionId": "deny",
                    "name": "Deny",
                    "kind": "reject_once"
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(RequestPermissionRequest.self, from: data)
        
        XCTAssertEqual(request.options.count, 2)
        XCTAssertEqual(request.options[0].kind, .allowOnce)
        XCTAssertEqual(request.options[1].kind, .rejectOnce)
    }
}
