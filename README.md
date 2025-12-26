# swift-acp

Swift SDK for the [Agent Client Protocol (ACP)](https://agentclientprotocol.com/) — a standard for connecting code editors to AI coding agents.

## Overview

`swift-acp` enables your macOS/iOS/visionOS app to host AI coding agents like Claude Code, Gemini CLI, and others. Users bring their own agent subscription — you provide the integration.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/swift-acp.git", from: "0.1.0")
]
```

## Quick Start

```swift
import ACP

// Create client for Claude Code
let client = ACPClient(
    command: "claude",
    arguments: ["--acp"],
    clientInfo: ClientInfo(name: "MyApp", version: "1.0")
)

// Connect and initialize
try await client.connect()

// Create a session
let sessionId = try await client.newSession(workingDirectory: projectURL)

// Send a prompt
let response = try await client.prompt("What files are in this directory?")
```

## Handling Agent Callbacks

Implement `ACPClientDelegate` to receive streaming updates and handle permission requests:

```swift
class MyAgentHandler: ACPClientDelegate {
    func client(_ client: ACPClient, didReceiveUpdate update: SessionUpdate) {
        // Handle streaming message chunks, tool calls, plans
        if let chunks = update.messageChunks {
            for chunk in chunks {
                print(chunk.text ?? "")
            }
        }
    }
    
    func client(_ client: ACPClient, requestPermission request: RequestPermissionRequest) async -> PermissionOptionID {
        // Show UI for user approval
        return "allow_once"  // or "reject_once"
    }
    
    func client(_ client: ACPClient, readFile path: String) async throws -> String {
        return try String(contentsOfFile: path)
    }
    
    func client(_ client: ACPClient, writeFile path: String, content: String) async throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
```

## Supported Agents

Any ACP-compatible agent works with this SDK:

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- [Goose](https://block.github.io/goose)
- [OpenHands](https://docs.openhands.dev)
- [And many more...](https://agentclientprotocol.com/overview/agents)

## Requirements

- macOS 15+ / iOS 18+ / visionOS 2+
- Swift 6.0+

## Architecture

```
┌─────────────────────────┐
│      Your App           │
│  ┌───────────────────┐  │
│  │    ACPClient      │  │
│  │  (MainActor)      │  │
│  └─────────┬─────────┘  │
│            │            │
│  ┌─────────▼─────────┐  │
│  │ ProcessTransport  │  │
│  │   (actor)         │  │
│  └─────────┬─────────┘  │
└────────────┼────────────┘
             │ stdin/stdout
             │ JSON-RPC 2.0
┌────────────▼────────────┐
│    External Agent       │
│  (Claude, Gemini, etc)  │
└─────────────────────────┘
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or PR.

## Acknowledgments

- [Agent Client Protocol](https://agentclientprotocol.com/) by Zed Industries
- [Preflight](https://github.com/your-org/preflight) — the first ACP client for 3D/USD workflows
