# 🚀 Feature: Build `swift-a2a` — The First Swift SDK for the Agent2Agent Protocol

## Summary

Build the first **Swift SDK for the [Agent2Agent (A2A) Protocol](https://a2a-protocol.org)** — Google's open standard for AI agent interoperability, now under the Linux Foundation. No official Swift SDK exists today. The official SDKs are Python, Go, JavaScript, Java, and .NET. Swift is a glaring gap.

This would live in a **separate repository** (`swift-a2a` or `a2a-swift`) and could eventually become an official community-contributed SDK.

---

## 🌍 Context & Why This Matters

### What is A2A?

The Agent2Agent Protocol is an open standard (Release Candidate v1.0) that enables independent AI agents to:
- **Discover** each other's capabilities via "Agent Cards" (`/.well-known/agent.json`)
- **Negotiate** interaction modalities (text, files, structured data)
- **Manage** collaborative tasks with a full lifecycle (9 states)
- **Stream** real-time updates via SSE
- **Exchange** rich data (text, binary files, URLs, structured JSON)

It's complementary to MCP (Model Context Protocol): **MCP = agent↔tools**, **A2A = agent↔agent**.

### Why Now?

- **ACP is merging into A2A** — The Agent Communication Protocol (IBM's BeeAI) is [officially merging with A2A](https://github.com/orgs/i-am-bee/discussions/5) under the Linux Foundation.
- **No Swift SDK exists** — Only a community [GitHub Gist](https://gist.github.com/) using Hummingbird 2 exists. No package, no tests, no official anything.
- **Apple platforms are underserved** — visionOS, iOS, and macOS apps have no way to participate in the A2A ecosystem.
- **First-mover opportunity** — Being the first Swift A2A SDK positions Preflight (and Reality Check) as leaders in spatial AI agent interoperability.

### Preflight Integration Opportunities

1. **Preflight as A2A Server** — Expose Preflight's spatial computing capabilities so other agents can discover and invoke them (e.g., "Create a 3D scene…" → USDZ artifact back).
2. **Preflight as A2A Client** — Connect to cloud-hosted A2A agents for specialized tasks (research, code gen, data analysis) and pipe results into the spatial IDE.
3. **Agent orchestration** — Enable multi-agent workflows where Preflight coordinates with specialized agents via the standard protocol.

---

## 📋 Specification Reference

- **Full Spec**: https://a2a-protocol.org/latest/specification/
- **JSON Schema**: https://github.com/a2aproject/A2A/blob/main/specification/json/a2a.json
- **Protocol Buffers**: https://github.com/a2aproject/A2A/tree/main/specification/proto
- **Main Repo**: https://github.com/a2aproject/A2A

### Core Protocol Operations

| Operation | Description | Required? |
|-----------|-------------|-----------|
| `sendMessage` | Send a message to an agent, get a Task or Message back | ✅ |
| `sendStreamingMessage` | Same but with SSE streaming of updates | ✅ |
| `getTask` | Retrieve task status and results | ✅ |
| `cancelTask` | Cancel an in-progress task | ✅ |
| `listTasks` | List tasks, optionally filtered by context | Optional |
| `setTaskPushNotification` | Register a webhook for task updates | Optional |
| `getTaskPushNotification` | Get push notification config | Optional |
| `resubscribe` | Re-establish SSE stream for a task | Optional |

### Core Data Model

```
Task
├── id: String
├── contextId: String
├── status: TaskStatus
│   ├── state: TaskState (submitted|working|completed|failed|canceled|rejected|input_required|auth_required)
│   ├── message: Message?
│   └── timestamp: Date
├── artifacts: [Artifact]
├── history: [Message]
└── metadata: [String: Any]?

Message
├── messageId: String
├── contextId: String?
├── taskId: String?
├── role: Role (user|agent)
├── parts: [Part]
├── metadata: [String: Any]?
├── extensions: [String]?
└── referenceTaskIds: [String]?

Part (oneOf: text | raw | url | data)
├── text: String?
├── raw: Data?          // binary content
├── url: String?        // file URL
├── data: Any?          // structured JSON
├── metadata: [String: Any]?
├── filename: String?
└── mediaType: String?

Artifact
├── artifactId: String
├── name: String?
├── description: String?
├── parts: [Part]
├── metadata: [String: Any]?
└── extensions: [String]?

AgentCard
├── name: String
├── description: String?
├── url: String
├── provider: AgentProvider?
├── version: String
├── capabilities: AgentCapabilities
│   ├── streaming: Bool
│   ├── pushNotifications: Bool
│   └── stateTransitionHistory: Bool
├── skills: [AgentSkill]
├── securitySchemes: [SecurityScheme]?
├── security: [SecurityRequirement]?
├── defaultInputModes: [String]    // "text", "file", "data"
├── defaultOutputModes: [String]
└── protocols: [ProtocolEntry]     // jsonrpc, rest, grpc
```

### Protocol Bindings

A2A supports **3 transport bindings** (implementations can support 1 or more):

| Binding | Transport | Streaming | Notes |
|---------|-----------|-----------|-------|
| **JSON-RPC 2.0** | HTTP POST to single endpoint | SSE | Primary binding, most SDKs implement this |
| **REST+JSON** | Standard RESTful endpoints | SSE | Simpler, maps to `URLSession` naturally |
| **gRPC** | Protocol Buffers over HTTP/2 | Server-side streaming | Enterprise use case |

**Recommendation for v1**: Implement **REST+JSON** binding first — it maps most naturally to Swift's `URLSession` / `AsyncSequence`. JSON-RPC can follow.

---

## 🏗️ Proposed Architecture

### Phase 1: Client-Only SDK (~1,000-1,500 lines)

```
swift-a2a/
├── Package.swift
├── Sources/
│   └── A2A/
│       ├── A2A.swift                    // Public exports
│       │
│       ├── Models/                      // ~500 lines — Pure Codable structs
│       │   ├── Task.swift               // Task, TaskStatus, TaskState
│       │   ├── Message.swift            // Message, Role
│       │   ├── Part.swift               // Part (text/raw/url/data)
│       │   ├── Artifact.swift           // Artifact
│       │   ├── AgentCard.swift          // AgentCard, AgentCapabilities, AgentSkill
│       │   ├── Requests.swift           // SendMessageRequest, GetTaskRequest, etc.
│       │   ├── Responses.swift          // Task/Message responses, streaming events
│       │   └── Errors.swift             // A2AError, error codes
│       │
│       ├── Client/                      // ~500 lines — URLSession-based
│       │   ├── A2AClient.swift          // Main client: sendMessage, getTask, cancelTask, listTasks
│       │   ├── A2AStreamClient.swift    // SSE streaming via AsyncSequence
│       │   ├── CardResolver.swift       // Fetch /.well-known/agent.json, validate
│       │   └── Errors.swift             // Client-specific errors (HTTP, network)
│       │
│       └── Utils/                       // ~100 lines
│           └── SSEParser.swift          // text/event-stream parser
│
├── Tests/
│   └── A2ATests/
│       ├── ModelTests.swift             // JSON encoding/decoding round-trips
│       ├── ClientTests.swift            // Mock URLProtocol-based tests
│       ├── CardResolverTests.swift
│       └── SSEParserTests.swift
│
└── README.md
```

### Phase 2: Server SDK (Future)

```
Sources/
└── A2AServer/                           // Separate target
    ├── A2AServer.swift                  // Request handler, routing
    ├── TaskStore/                       // In-memory + protocol for custom stores
    │   ├── TaskStore.swift              // Protocol
    │   └── InMemoryTaskStore.swift
    ├── EventQueue/                      // SSE event delivery
    │   ├── EventQueue.swift
    │   └── InMemoryEventQueue.swift
    └── AgentExecutor.swift              // Protocol for agent logic
```

### Phase 3: Preflight Integration (Future)

```
Sources/
└── A2APreflight/                        // Preflight-specific target
    ├── PreflightAgentCard.swift          // Spatial computing agent card
    ├── SpatialAgentExecutor.swift        // Bridge to Preflight scene ops
    └── USDZArtifactProvider.swift        // Package USDZ as A2A artifacts
```

---

## 🔑 Key Design Decisions

### 1. Swift 6 + Strict Concurrency
- Use `Sendable` protocols throughout
- `async`/`await` for all network operations
- `AsyncSequence` for SSE streaming

### 2. Zero External Dependencies (Phase 1)
- Use `URLSession` for HTTP (no Alamofire, no async-http-client)
- Use `JSONDecoder`/`JSONEncoder` for serialization
- Use `Codable` for all models
- SSE parser is trivial (~50 lines) — no need for a dependency

### 3. Cross-Platform from Day 1
- Target macOS 13+, iOS 16+, visionOS 1+, Linux
- No Apple-only frameworks in the core module
- `#if canImport(FoundationNetworking)` for Linux `URLSession`

### 4. REST+JSON Binding First
The REST binding maps naturally to Swift:

```swift
// REST endpoints → URLSession calls
GET    /.well-known/agent.json       → resolveCard()
POST   /tasks/send                   → sendMessage(_:)
POST   /tasks/sendSubscribe          → sendStreamingMessage(_:) → AsyncSequence<Event>
GET    /tasks/{taskId}               → getTask(id:)
POST   /tasks/{taskId}/cancel        → cancelTask(id:)
GET    /tasks                        → listTasks(contextId:)
```

### 5. Models Auto-Generated (Optional Enhancement)
The A2A types are defined in a [JSON Schema](https://github.com/a2aproject/A2A/blob/main/specification/json/a2a.json). The Python SDK auto-generates its `types.py` (55KB!) from this schema. For Swift, hand-written `Codable` structs are more idiomatic, but a code-gen script could be created to stay in sync.

---

## 📊 Complexity Estimate

| Component | Estimated LOC | Effort | Priority |
|-----------|:---:|:---:|:---:|
| **Models** (Codable structs) | ~500 | 1-2 days | P0 |
| **REST Client** (URLSession) | ~300 | 1-2 days | P0 |
| **SSE Streaming** (AsyncSequence) | ~200 | 1 day | P0 |
| **Agent Card Resolver** | ~100 | 0.5 day | P0 |
| **Unit Tests** | ~500 | 1-2 days | P0 |
| **README + Documentation** | ~200 | 0.5 day | P0 |
| **JSON-RPC Binding** | ~400 | 2 days | P1 |
| **Server (basic)** | ~1,500 | 1 week | P2 |
| **Push Notifications** | ~500 | 2 days | P2 |
| **Auth (OAuth 2.0)** | ~400 | 2 days | P2 |
| **gRPC Binding** | ~800 | 3-4 days | P3 |
| **Preflight Integration** | ~500 | 2-3 days | P3 |

**Phase 1 Total: ~5-7 days** for a client-only SDK with REST binding, streaming, and tests.

---

## 🔗 Reference Implementations

Study these official SDKs for patterns and edge cases:

| SDK | Repo | Key Files |
|-----|------|-----------|
| **Python** | [a2aproject/a2a-python](https://github.com/a2aproject/a2a-python) | `src/a2a/types.py` (55KB models), `src/a2a/client/`, `src/a2a/server/` |
| **JavaScript** | [a2aproject/a2a-js](https://github.com/a2aproject/a2a-js) | Likely simplest — good for client patterns |
| **Go** | [a2aproject/a2a-go](https://github.com/a2aproject/a2a-go) | Strong typing patterns relevant to Swift |
| **.NET** | [a2aproject/a2a-dotnet](https://github.com/a2aproject/a2a-dotnet) | Closest language paradigm to Swift |
| **Java** | [a2aproject/a2a-java](https://github.com/a2aproject/a2a-java) | Enterprise patterns |

### Also Study:
- **ACP TypeScript SDK** (simple client): [i-am-bee/acp/typescript](https://github.com/i-am-bee/acp/tree/main/typescript) — minimal, clean, ~200 LOC client
- **ACP Python SDK** (client + server): [i-am-bee/acp/python](https://github.com/i-am-bee/acp/tree/main/python) — `Client` class is ~350 LOC with httpx
- **Community Swift Gist**: Search GitHub for Hummingbird 2 A2A implementation

---

## ✅ Acceptance Criteria (Phase 1 — Client SDK)

- [ ] **Package builds** on macOS 13+ and Linux with `swift build`
- [ ] **Models decode** all example JSON from the A2A spec without error
- [ ] **Agent Card resolution** from `/.well-known/agent.json` works
- [ ] **`sendMessage`** sends a message and returns a `Task` or `Message`
- [ ] **`sendStreamingMessage`** returns an `AsyncSequence<TaskEvent>` with SSE parsing
- [ ] **`getTask`** retrieves task by ID with full status
- [ ] **`cancelTask`** cancels a running task
- [ ] **`listTasks`** lists tasks with optional context filter
- [ ] **Error handling** maps A2A error codes to typed Swift errors
- [ ] **Unit tests** cover all models (JSON round-trip) and client methods (mocked)
- [ ] **Integration test** against the Python A2A sample server passes
- [ ] **README** with installation, quickstart, and API reference
- [ ] **No external dependencies** — Foundation only
- [ ] **Swift 6 strict concurrency** — all types are `Sendable`

---

## 🏷️ Labels

`enhancement`, `new-repository`, `a2a`, `swift`, `agent-protocol`, `opportunity`

---

## 📚 Additional Resources

- [A2A Protocol Specification (RC v1.0)](https://a2a-protocol.org/latest/specification/)
- [A2A JSON Schema](https://github.com/a2aproject/A2A/blob/main/specification/json/a2a.json)
- [A2A and MCP Relationship](https://a2a-protocol.org/latest/topics/a2a-and-mcp/)
- [A2A Samples](https://github.com/a2aproject/a2a-samples)
- [ACP → A2A Merger Announcement](https://github.com/orgs/i-am-bee/discussions/5)
- [A2A Contributing Guide](https://github.com/a2aproject/A2A/blob/main/CONTRIBUTING.md)

---

> **Note**: Once this SDK reaches maturity, consider proposing it as an official A2A SDK contribution via the [A2A GitHub Discussions](https://github.com/a2aproject/A2A/discussions) or the [partner program](https://goo.gle/a2a-partner).
