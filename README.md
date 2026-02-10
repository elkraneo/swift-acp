# swift-acp

A Swift SDK for communicating with AI coding agents over JSON-RPC.

Built with Swift 6 and modern concurrency, `swift-acp` provides a type-safe interface to connect, communicate, and collaborate with AI agents like [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Gemini CLI](https://github.com/google-gemini/gemini-cli), and others that expose a JSON-RPC 2.0 interface.

> [!NOTE]
> This is **not** an official ACP SDK. While inspired by the [Agent Communication Protocol](https://agentcommunicationprotocol.dev) vocabulary (sessions, prompts, manifests), this library implements a **bidirectional JSON-RPC 2.0** transport (stdio + HTTP) — a different interaction model from ACP's REST/HTTP specification. With ACP [merging into A2A](https://github.com/orgs/i-am-bee/discussions/5) under the Linux Foundation, a dedicated [Swift A2A SDK](https://github.com/a2aproject/A2A) is being explored separately.

---

## ⚡️ Key Features

- **🚀 Multi-Transport Support**: Connect via local subprocess (`ProcessTransport`) or remote servers (`HTTPTransport`).
- **🔀 Bidirectional Communication**: Agents can request permissions, read/write files, and call client-side tools — not just respond to prompts.
- **🛡️ Native Delegate API**: Handle permissions, file operations, and tool calls with a clean, async-await delegate pattern.
- **🛠️ Client-Side Tools**: Expose your app's functions as tools the agent can call directly.
- **📂 File System Integration**: Let agents read and write files safely within your app's sandbox.
- **⏱️ Performance Logging**: Built-in timing and batching for high-throughput coding tasks.
- **🔌 MCP Bridge**: Includes a minimal MCP server implementation for tool exposure to standard MCP clients.

---

## 📦 Installation

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/reality2713/swift-acp.git", branch: "main")
]
```

Then add `"ACP"` to your target's dependencies. For agent-specific helpers and the MCP server, also add `"ACPExtras"`.

## 🚀 Quickstart

### 1. Connecting to a Local Agent (e.g., Claude Code)

```swift
import ACP

let client = ACPClient(
    command: "claude",
    arguments: ["--acp"],
    clientInfo: ClientInfo(name: "MyIDE", version: "1.0")
)

try await client.connect()
let session = try await client.newSession(workingDirectory: URL(fileURLWithPath: "/path/to/project"))

let response = try await client.prompt("Explain the architecture of this project")
print(response.stopReason)
```

### 2. Implementing the Delegate

Most interaction happens through `ACPClientDelegate`. Assign it to handle agent requests.

```swift
class AppAgentHandler: ACPClientDelegate {
    // Handle status updates (streaming text, plans, tools)
    func client(_ client: ACPClient, didReceiveUpdate update: SessionUpdate) {
        if let chunks = update.messageChunks {
            for chunk in chunks {
                print(chunk.text ?? "", terminator: "")
            }
        }
    }

    // Handle security permissions
    func client(_ client: ACPClient, requestPermission request: RequestPermissionRequest) async -> PermissionOptionID {
        return "allow_once"
    }

    // Provide tools to the agent
    func listTools(_ client: ACPClient) async -> [ToolDefinition] {
        return [
            ToolDefinition(
                name: "reveal_in_finder",
                description: "Reveals a file in macOS Finder",
                parameters: ["path": AnyCodable("string")]
            )
        ]
    }
}
```

---

## 💎 Advanced Capabilities

### Agent-Specific Metadata (ACPExtras)

Configure agent-specific behaviors via typed metadata helpers:

```swift
import ACPExtras

let meta = ClaudeCodeMeta.autoApprove(except: ["rm", "git_push"])
try await client.newSession(meta: meta.toDictionary())
```

### Model & Mode Switching
Agents often support multiple modes (e.g., `architect`, `code`, `ask`) and models.

```swift
// Switch model mid-session
try await client.setSessionModel("claude-3-5-sonnet-20241022")

// Switch session mode
try await client.setSessionMode("architect")
```

### Performance & Debugging
Enable verbose logging or timing by setting environment variables:

- `ACP_VERBOSE=1`: Detailed JSON-RPC message logs.
- `ACP_TIMING=1`: Performance metrics for prompt response times and tool execution.
- `ACP_BATCHING=1`: Enables message chunk batching for smoother UI updates.

---

## 🧱 Project Structure

```
Sources/
├── ACP/                    Core SDK (cross-platform target)
│   ├── Protocol/           Type-safe Codable models
│   ├── Transport/          JSON-RPC, Process (IPC), and HTTP layers
│   └── Client/             ACPClient + delegate protocol
│
└── ACPExtras/              Apple-platform extras
    ├── ClaudeCodeMeta      Agent-specific configuration helpers
    └── MCPServer           Minimal MCP tool server (Network.framework)
```

---

## 🗺️ How It Compares

| Feature | `swift-acp` | Official ACP SDKs (Python/TS) |
|---------|:-----------:|:-----------------------------:|
| **Transport** | JSON-RPC (stdio + HTTP) | REST/HTTP + SSE |
| **Direction** | Bidirectional (agent ↔ client) | Unidirectional (client → agent) |
| **Local Process (IPC)** | ✅ | ❌ |
| **Async/Await Native** | ✅ | ✅ |
| **Tool Registration** | ✅ | ✅ |
| **File System Ops** | ✅ (delegated) | ❌ |
| **Permission System** | ✅ | ❌ |
| **MCP Bridge** | ✅ (ACPExtras) | ❌ |
| **Apple Platforms** | ✅ | ❌ |

---

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

---

> [!TIP]
> Developed for **Preflight** – a spatial AI IDE for Apple Vision Pro.
