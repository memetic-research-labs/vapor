# AI Session Capture: Expanded Architecture Report

## Executive Summary

This report expands PR #19's AI session capture plan with four major additions the original design is missing:

1. **Project anchoring** — a new `VaporProject` model that scopes all context (ContextItems, PromptRecords, ImageAssets, AISessions) to git repos, GitHub/GitLab URLs, or custom named workspaces, with auto-detection from AI session CWD and browser URLs
2. **Entity & tag extraction from session turns** — reusing Vapor's existing `EntityRecord` / `ContextItemEntityLink` infrastructure so every AI turn is fully indexed for faceted search, plus new `EntityKind` values for decisions, libraries, APIs, and models
3. **Local HTTP API + separate CLI package** — programmatic access to session context, semantic search, entity graph queries, and git export via the existing embedded server and a new `vapor-cli` SwiftPM tool
4. **Full-context git export** — every image, PDF, URL, and media asset alongside the transcript, with regex + LLM hybrid secrets redaction, branch-aligned symlinks to date-based storage

The capture architecture uses a **facade/adapter pattern** starting with OpenCode as the primary target, with a clean interface for future adapters (Claude Desktop, Cursor, Continue.dev).

---

## Table of Contents

1. [Prior Art Analysis](#1-prior-art-analysis)
2. [Expanded Data Model](#2-expanded-data-model)
3. [Project Anchoring](#3-project-anchoring)
4. [Facade / Adapter Architecture](#4-facade--adapter-architecture)
5. [Entity Extraction Pipeline for Sessions](#5-entity-extraction-pipeline-for-sessions)
6. [Local HTTP API](#6-local-http-api)
7. [CLI Tool (Separate SwiftPM Package)](#7-cli-tool-separate-swiftpm-package)
8. [Full-Context Git Export](#8-full-context-git-export)
9. [Implementation Roadmap](#9-implementation-roadmap)
10. [Dependency Graph](#10-dependency-graph)

---

## 1. Prior Art Analysis

### Directly Relevant

| Project | Stars | Key Insight for Vapor |
|---------|-------|----------------------|
| **Ghost** (notkurt/ghost) | 11 | Closest to Vapor's goal. Records Claude Code sessions as markdown with YAML frontmatter in `.ai-sessions/`, uses git notes (`refs/notes/ai-sessions`), indexes into QMD for semantic search. Has secret redaction, tag filtering, warm resume. **Lesson: git notes + markdown + YAML frontmatter is a proven pattern.** |
| **mem0 / mem0.ai** | 54.7k | Universal AI memory layer. Extracts entities, stores across sessions, supports hybrid search (semantic + BM25 + entity). Multi-level memory (User, Session, Agent). **Lesson: entity linking across sessions and ADD-only accumulation without overwrite is the right model.** |
| **Aider** | 44.3k | Git-native session tracking. Every AI edit = git commit. `.aider.chat.yml` metadata. `ChatSummary` recursive summarization. **Lesson: commits as session boundaries, YAML sidecar for metadata.** |
| **Khoj** | 34.4k | Self-hosted "AI second brain" with local vector DB. Semantic search across PDFs, markdown, images. Custom agents with scoped knowledge bases. **Lesson: complete self-hosted architecture for personal knowledge search.** |

### Entity Extraction & Knowledge Graph

| Project | Approach |
|---------|----------|
| **Neo4j GraphRAG** | LLM extracts entities/relations -> graph -> hybrid retrieval (vector + graph traversal). |
| **LightRAG** | Lightweight knowledge graph from docs using LLM entity extraction with entity centrality scoring. |
| **mem0 v3** | Entity linking across conversations, spaCy NLP support, hybrid entity matching. |
| **LangChain** | `GraphCypherQAChain` and entity extraction chains for graph DB storage. |

### Session Export to Git

| Project | Strategy |
|---------|----------|
| **Ghost** | `.ai-sessions/` + git notes + QMD search index |
| **Aider** | `.aider.chat.yml` per repo, commits as session boundaries |
| **trace** (GrayCodeAI) | Git refs (not branches) for session storage |
| **ai-context** (lankithagallage) | "Distill" concept -- compress raw sessions into actionable context |

### Secrets Redaction (No Dedicated Tool Exists)

No open-source project combines AI session sanitization with git export. The industry standard is:

- **detect-secrets** (Yelp) -- regex-based secret scanning
- **gitleaks** -- Go-based secret scanner for git repos
- **truffleHog** -- scans git history for secrets
- Combined with LLM-based contextual sanitization (no existing open-source implementation)

### Local Vector Search APIs

| Tool | Embed | Faceted | CLI | HTTP API |
|------|-------|---------|-----|----------|
| **Qdrant** | Docker | Yes (payload filtering) | No | REST + gRPC |
| **LanceDB** | Embedded | Yes (SQL + metadata) | No | REST |
| **ChromaDB** | Embedded | Yes (metadata) | No | Local HTTP |
| **SQLite-vec** | Embedded | Partial (via SQL WHERE) | Via sqlite3 | No native |
| **QMD** | Embedded | No | Yes | No |

**Vapor already has SQLite-vec** -- extending it with metadata columns for faceted filtering is simpler than adding a new database dependency.

### Key Gap Identified

No existing tool combines all of: (1) AI session capture, (2) entity extraction, (3) faceted semantic search, (4) git-native storage with sanitization, and (5) HTTP/CLI API. Vapor would be the first.

---

## 2. Expanded Data Model

The original plan's `AISession` + `AITurn` models are a good start but miss the entity extraction, tagging, and faceted search integration that Vapor's existing data model already supports. The expansion reuses `EntityRecord`, `ContextItemEntityLink`, the `TaggerService` pattern, and the existing `vec_items_minilm_l12_multilingual_v2` table.

### 2.1 AISession (expanded)

```swift
@Model
final class AISession {
    var id: UUID
    var title: String
    var tool: String                    // "opencode" | "claude-desktop" | "cursor" | "continue" | "manual"
    var projectPath: String?
    var projectName: String?
    var branchName: String?             // git branch at time of capture
    var prNumber: Int?                  // associated PR number (if detectable)
    var startedAt: Date
    var endedAt: Date?
    var tags: [String]                  // LLM-generated + user tags
    var isArchived: Bool
    var gitCommitSHA: String?
    var embeddingID: String?            // session summary embedding

    // Summarization
    var summaryAbstract: String?        // 2-3 sentence overview
    var summaryKeyPoints: [String]?     // 3-5 key points (stored as JSON)

    // Metrics
    var totalTokensEstimated: Int
    var totalTurns: Int                 // denormalized count
    var totalAttachedImages: Int        // denormalized count
    var totalAttachedURLs: Int          // denormalized count

    // Project anchoring
    var project: VaporProject?

    @Relationship(deleteRule: .cascade, inverse: \AITurn.session)
    var turns: [AITurn] = []

    @Relationship(deleteRule: .nullify, inverse: \ImageAsset.aiSession)
    var attachedImages: [ImageAsset] = []

    @Relationship(deleteRule: .cascade, inverse: \AISessionEntityLink.session)
    var entityLinks: [AISessionEntityLink] = []
}
```

### 2.2 AITurn (expanded)

```swift
@Model
final class AITurn {
    var id: UUID
    var session: AISession?
    var role: String                    // "user" | "assistant" | "system" | "tool"
    var turnIndex: Int
    var content: String
    var contentTokenCount: Int
    var capturedAt: Date
    var embeddingID: String?            // "aisession:<turn-uuid>"

    var modelID: String?
    var toolName: String?
    var attachedImageIDs: [String]
    var attachedURLs: [String]          // URLs mentioned in this turn
    var durationSeconds: Double?
    var isEdited: Bool
    var isRedacted: Bool                // excluded from git export

    @Relationship(deleteRule: .cascade, inverse: \AITurnEntityLink.turn)
    var entityLinks: [AITurnEntityLink] = []
}
```

### 2.3 New Join Models for Entity Extraction

Reuse the existing `EntityRecord` (already in schema) with new join tables:

```swift
@Model
final class AISessionEntityLink {
    var id: UUID
    var confidence: Double
    var surfaceText: String
    var createdAt: Date
    var session: AISession?
    var entityRecord: EntityRecord?
}

@Model
final class AITurnEntityLink {
    var id: UUID
    var confidence: Double
    var surfaceText: String
    var createdAt: Date
    var turn: AITurn?
    var entityRecord: EntityRecord?
}
```

### 2.4 Expanded EntityKind

Extend `EntityKind` enum beyond the existing 9 types to cover AI session context:

```swift
enum EntityKind: String, Codable, CaseIterable {
    case person, organization, product, location, date, url, number, code, concept
    case model          // LLM model names (e.g. "claude-opus-4-5")
    case tool           // AI tools (e.g. "opencode", "cursor")
    case library        // Software libraries (e.g. "express-rate-limit")
    case api            // API endpoints
    case file           // File paths referenced in sessions
    case error          // Error types/messages
    case decision       // Architectural decisions (extracted by LLM)
}
```

### 2.5 AITag Model (LLM-generated tags)

Sessions support both auto-generated and user-defined tags:

```swift
@Model
final class AISessionTag {
    var id: UUID
    var text: String                   // e.g. "rate-limiting", "auth-refactor", "bug-fix"
    var sourceRaw: String              // "auto" | "user" | "llm"
    var confidence: Double?            // for auto/llm tags
    var createdAt: Date
    var session: AISession?
}
```

### 2.6 AIGitExportRecord

Track what was exported and where:

```swift
@Model
final class AIGitExportRecord {
    var id: UUID
    var session: AISession?
    var exportedAt: Date
    var gitCommitSHA: String
    var branchName: String
    var sessionDirPath: String         // relative path within repo
    var filesIncluded: [String]        // list of files in export
    var totalBytes: Int
    var redactionCount: Int            // number of redactions applied
    var redactedTurnIDs: [String]      // turn IDs that were fully redacted
}
```

### 2.7 Schema Migration

All new models register in `VaporSchemaV2` (new schema version). Existing `EntityRecord` is shared -- no migration needed for the entity table, only new join tables.

---

## 3. Project Anchoring

### 3.1 The Problem

Vapor currently has no concept of a "project." All context -- browser captures, screenshots, prompts, AI sessions, entities -- lives in a single global pool. There's no way to:

- See "all context related to the Vapor app" vs "all context related to my client project"
- Filter the Context Explorer by project
- Export context aligned to a specific PR or branch
- Switch between projects as a developer moves between tasks

### 3.2 VaporProject Model

A new top-level SwiftData model that anchors all context:

```swift
@Model
final class VaporProject {
    var id: UUID
    var name: String                      // "Vapor App", "Client API", "Research: RAG"
    var notes: String?                    // optional description

    // Git anchoring (optional -- projects can exist without git)
    var gitLocalPath: String?             // absolute path to git repo root
    var gitRemoteURL: String?             // "https://github.com/org/repo" or "git@github.com:org/repo.git"
    var gitCurrentBranch: String?         // updated via git rev-parse --abbrev-ref HEAD
    var detectedPRNumber: Int?            // parsed from branch name (e.g., "pr-27-dictation-perf" -> 27)

    // Display
    var colorHex: String?                 // for sidebar/project picker accent color
    var sortOrder: Int

    // Timestamps
    var createdAt: Date
    var lastActiveAt: Date

    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \ContextItem.project)
    var contextItems: [ContextItem] = []

    @Relationship(deleteRule: .nullify, inverse: \PromptRecord.project)
    var promptRecords: [PromptRecord] = []

    @Relationship(deleteRule: .nullify, inverse: \AISession.project)
    var sessions: [AISession] = []

    @Relationship(deleteRule: .nullify, inverse: \ImageAsset.project)
    var imageAssets: [ImageAsset] = []

    @Relationship(deleteRule: .cascade, inverse: \VaporProjectBookmark.bookmark)
    var bookmarks: [VaporProjectBookmark] = []
}
```

### 3.3 Project Discovery (Auto-Detection)

Three auto-detection signals, plus manual creation.

**Signal 1: AI Session CWD** (highest confidence)

When `OpenCodeAdapter` (or any adapter) captures a turn:

1. Detect the tool process CWD via `sysctl(KERN_PROC_PATHNAME)` or similar
2. Run `git rev-parse --show-toplevel` -> git root
3. Run `git remote get-url origin` -> remote URL
4. Run `git rev-parse --abbrev-ref HEAD` -> current branch
5. Parse branch name for PR number (regex: `pr-(\d+)`, `feature/(\d+)-`, `(\d+)-.*`)
6. Match against existing `VaporProject` by `gitLocalPath` or `gitRemoteURL`
7. If no match -> create new `VaporProject` with detected info

**Signal 2: Browser URL** (medium confidence)

When browser captures context (article, screenshot):

1. Check if `sourceURL` matches GitHub/GitLab/Bitbucket patterns:
   - `github.com/{org}/{repo}` or `gitlab.com/{org}/{repo}`
2. If match -> build canonical remote URL -> match against existing projects
3. If match found -> prompt user to assign this context to the project
4. If no match -> context stays in "Unassigned"

**Signal 3: Manual Creation**

User creates a project via:

- "New Project" button in project picker
- Provide: name, optional local git path, optional remote URL
- Vapor auto-detects git info from the path if provided

### 3.4 Project Bookmark (Security-Scoped Access)

macOS requires scoped bookmarks for persistent folder access:

```swift
@Model
final class VaporProjectBookmark {
    var id: UUID
    var project: VaporProject?
    var bookmarkData: Data               // NSURL scoped bookmark for gitLocalPath
    var createdAt: Date
}
```

When a user grants access to a git repo directory, the scoped bookmark is saved so Vapor retains access across app restarts.

### 3.5 Data Model Changes (Existing Models)

Add optional project FK to existing models. **"Unassigned" is represented by `project == nil`.** No special model needed.

```swift
// ContextItem -- add:
var project: VaporProject?

// PromptRecord -- add:
var project: VaporProject?

// ImageAsset -- add:
var project: VaporProject?
```

### 3.6 Project-Scoped Context Explorer

Add a project picker to the Context Explorer sidebar:

```
+--------------------------+
|  Projects                |
|  ---------               |
|  * Vapor App       (42)  |  <- active project, context count
|  o Client API      (18)  |
|  o Research: RAG   (7)   |
|  o Unassigned     (156)  |  <- project == nil
|  ---------               |
|  + New Project            |
+--------------------------+
|  Explorer                |
|  ---------               |
|  Overview                 |
|  Recent                   |
|  Domains                  |
|  Entities                 |
|  ...                      |
+--------------------------+
```

When a project is selected:

- All facets (domains, entities, tags, types, URLs) are filtered to that project
- Semantic search only returns results from that project
- Entity graph only shows entities from that project
- Export operations are scoped to that project

### 3.7 Project Service

```swift
@MainActor
@Observable
final class ProjectService {
    static let shared = ProjectService()

    var allProjects: [VaporProject] = []
    var activeProject: VaporProject?   // nil = "Unassigned" (global view)
    var unassignedCount: Int = 0

    // Detection
    func detectProject(from gitPath: String) async throws -> VaporProject
    func detectProject(from browserURL: String) async -> VaporProject?
    func createProject(name: String, gitPath: String?, remoteURL: String?) throws -> VaporProject

    // Git sync
    func refreshGitState(for project: VaporProject) async
    func watchProjectDirectories()

    // Assignment
    func assignContextItem(_ item: ContextItem, to project: VaporProject?)
    func assignPromptRecord(_ record: PromptRecord, to project: VaporProject?)
    func assignImageAsset(_ asset: ImageAsset, to project: VaporProject?)
    func assignSession(_ session: AISession, to project: VaporProject?)
}
```

---

## 4. Facade / Adapter Architecture

### 4.1 SessionCaptureFacade

A single facade that adapters plug into:

```swift
protocol SessionCaptureAdapter: Sendable {
    var toolName: String { get }
    func isAvailable() async -> Bool
    func startCapture() async throws
    func stopCapture() async
    var onTurnCaptured: (@Sendable (CapturedTurn) async -> Void)? { get set }
}

struct CapturedTurn: Sendable {
    let role: String
    let content: String
    let capturedAt: Date
    let modelID: String?
    let toolName: String?
    let durationSeconds: Double?
}

@MainActor
@Observable
final class SessionCaptureFacade {
    var activeAdapters: [String: any SessionCaptureAdapter] = [:]
    var isCapturing: Bool = false

    func registerAdapter(_ adapter: any SessionCaptureAdapter) { ... }
    func startAll() async { ... }
    func stopAll() async { ... }
    func stopAdapter(for tool: String) async { ... }
}
```

### 4.2 OpenCodeAdapter (Primary Target)

OpenCode stores conversation history as JSONL. The adapter watches for new lines:

```swift
final class OpenCodeAdapter: SessionCaptureAdapter {
    let toolName = "opencode"

    // Path resolution: config.json -> XDG_DATA_HOME -> ~/.local/share/opencode/ -> ~/.config/opencode/
    // Watches via FSEventStream for file appends
    // Parses JSONL: {"role": "...", "content": "...", "timestamp": "...", "model": "..."}
    // Detects project from working directory via ProjectService.detectProject()
}
```

### 4.3 Future Adapters (Stub)

- `ClaudeDesktopAdapter` -- NSFilePresenter on `~/Library/Application Support/Claude/logs/`
- `CursorAdapter` -- WebSocket/HTTP client on `localhost:65002`
- `ContinueAdapter` -- HTTP polling on `localhost:65432`
- `ManualPasteAdapter` -- Cmd+Opt+V or toolbar button

---

## 5. Entity Extraction Pipeline for Sessions

### 5.1 Per-Turn Extraction

Each captured `AITurn` flows through a pipeline mirroring `ContextQueueService`:

```
CapturedTurn
  -> AITurn SwiftData record created
  -> Parallel:
      +-- EntityExtractionService.extract(turn.content)
      |     -> EntityRecord (deduplicated by entityHash)
      |     -> AITurnEntityLink (confidence + surfaceText)
      +-- TaggerService.tagSessionTurn(turn)
      |     -> Auto-generates tags from content + entities
      +-- URL extraction (NSDataDetector)
            -> URLs stored in AITurn.attachedURLs
  -> VectorizationService.ensureEmbedding(for: turn)
  -> Session-level entity aggregation (collect all unique entities)
```

### 5.2 Session-Level Summary + Entity Aggregation

On session close:

```
Session close
  -> Collect all AITurnEntityLink entities -> deduplicate -> AISessionEntityLink
  -> LLM generates session summary (abstract + key points) -> stored on AISession
  -> LLM generates session tags (3-5 high-level tags) -> AISessionTag
  -> Session summary embedding -> AISession.embeddingID
```

### 5.3 Decision Extraction

For `EntityKind.decision`, use a dedicated LLM prompt:

```
Analyze this AI coding session. Extract architectural and design DECISIONS
that were made during the conversation. For each decision, provide:
- text: short description of the decision
- confidence: 0.0-1.0

Output as JSON array: [{"text": "...", "kind": "decision", "confidence": 0.9}]
```

This enables faceted search for "show me all architectural decisions made in sessions for project X."

---

## 6. Local HTTP API

All endpoints extend the existing `VaporEmbeddedServer` on port 8766, reusing the same auth (bearer token / query param) and CORS configuration.

### 6.1 Session Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/sessions` | List sessions (query: `?tool=opencode&project=my-api&branch=main&limit=50&offset=0`) |
| `GET` | `/api/sessions/:id` | Full session with turns, entities, tags, images |
| `GET` | `/api/sessions/:id/turns` | Paginated turns (`?limit=20&offset=0&role=assistant`) |
| `GET` | `/api/sessions/:id/summary` | Session summary (abstract + key points) |
| `GET` | `/api/sessions/:id/entities` | All entities linked to session |
| `GET` | `/api/sessions/:id/tags` | All tags |
| `DELETE` | `/api/sessions/:id` | Archive session |

### 6.2 Search Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/search/sessions` | Semantic search across sessions (`{"query": "...", "limit": 10, "filters": {...}}`) |
| `POST` | `/api/search/turns` | Semantic search across individual turns |
| `GET` | `/api/search/entities` | Entity search (`?kind=person&text=john&limit=20`) |
| `GET` | `/api/search/tags` | Tag search (`?text=auth&limit=20`) |

### 6.3 Faceted Query Parameters

The `filters` object in search endpoints supports:

```json
{
  "projectId": "uuid-of-project",
  "tool": "opencode",
  "project": "my-api",
  "branch": "feature/auth",
  "entityKind": "decision",
  "entityText": "rate-limiting",
  "tags": ["bug-fix", "api"],
  "dateFrom": "2025-04-01T00:00:00Z",
  "dateTo": "2025-05-01T00:00:00Z",
  "modelID": "claude-opus-4-5",
  "minTurns": 5
}
```

### 6.4 Export Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/sessions/:id/export` | Preview export (returns file list + redaction summary, no git commit) |
| `POST` | `/api/sessions/:id/export/commit` | Export + git commit |
| `GET` | `/api/export/config` | Get current export settings |
| `PUT` | `/api/export/config` | Update export settings (denylist, redaction rules) |

### 6.5 Entity Graph Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/entities/:id` | Entity detail + all linked sessions/turns |
| `GET` | `/api/entities/:id/related` | Related entities (co-occurring in same sessions) |
| `GET` | `/api/entities/graph` | Adjacency list for entity graph visualization (`?kind=concept&project=my-api`) |

### 6.6 Project Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/projects` | List all projects |
| `POST` | `/api/projects` | Create project |
| `GET` | `/api/projects/:id` | Project detail + stats |
| `PUT` | `/api/projects/:id` | Update project |
| `GET` | `/api/projects/:id/context` | List context items for project |
| `GET` | `/api/projects/:id/sessions` | List AI sessions for project |
| `GET` | `/api/projects/:id/entities` | Entity summary for project |

### 6.7 SQLite-vec Faceted Search Extension

Current `vec_items` table only has `embedding` + `embedding_id`. Add a metadata table:

```sql
CREATE TABLE aisession_meta (
    embedding_id TEXT PRIMARY KEY,
    turn_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    project_id TEXT,
    role TEXT NOT NULL,
    tool TEXT,
    branch TEXT,
    model_id TEXT,
    captured_at REAL NOT NULL,
    tags TEXT,           -- JSON array
    entity_kinds TEXT    -- JSON array
);
```

This enables filtered KNN search:

```sql
SELECT v.embedding_id, v.distance, m.*
FROM vec_items_minilm_l12_multilingual_v2 v
JOIN aisession_meta m ON m.embedding_id = v.embedding_id
WHERE m.project_id = 'uuid-of-project' AND m.role = 'assistant'
ORDER BY v.distance LIMIT 10;
```

---

## 7. CLI Tool (Separate SwiftPM Package)

A standalone `vapor-cli` package that reads Vapor's database directly without requiring the full Vapor app to be running.

### 7.1 Package Structure

```
vapor-cli/
+-- Package.swift
+-- Sources/
|   +-- vapor-cli/
|   |   +-- main.swift
|   |   +-- Commands/
|   |   |   +-- SearchCommand.swift      // Semantic + faceted search
|   |   |   +-- SessionsCommand.swift     // List, show, archive sessions
|   |   |   +-- EntitiesCommand.swift     // Entity search, graph queries
|   |   |   +-- ExportCommand.swift       // Git export from CLI
|   |   |   +-- ImportCommand.swift       // Import from .vapor-context/
|   |   |   +-- ProjectsCommand.swift     // List, create, show projects
|   |   |   +-- StatusCommand.swift       // DB stats, capture status
|   |   +-- Services/
|   |   |   +-- VaporDatabase.swift       // Reads SQLite + SwiftData directly
|   |   |   +-- EmbeddingSearch.swift     // In-process MiniLM for CLI search
|   |   +-- Output/
|   |       +-- JSONOutput.swift          // Machine-readable output
|   |       +-- TerminalOutput.swift      // Human-readable output
|   +-- vapor-cli-core/
|       +-- Models/                      // Shared model definitions
+-- Tests/
+-- README.md
```

### 7.2 CLI Commands

```bash
# Projects
vapor projects list
vapor projects create "My API" --git-path ~/projects/my-api
vapor projects show <project-id>
vapor projects context <project-id> --limit 20

# Search
vapor search "rate limiting express" --project <id> --tool opencode --limit 10
vapor search --entity-kind decision --branch feature/auth
vapor search --tag bug-fix --date-from 2025-04-01

# Sessions
vapor sessions list --project <id> --limit 20
vapor sessions show <session-id> --format markdown
vapor sessions export <session-id> --preview    # Preview only, no commit
vapor sessions export <session-id> --commit     # Full export + git commit

# Entities
vapor entities search "express" --kind library
vapor entities graph --project <id> --kind concept

# Import
vapor sessions import --path ~/projects/my-api  # Scan .vapor-context/ dir

# Status
vapor status                                       # DB stats, capture status
```

### 7.3 Installation

```bash
# Build from source
swift build -c release
cp .build/release/vapor-cli /usr/local/bin/

# Future: brew tap
brew install memetic-research-labs/tap/vapor-cli
```

### 7.4 Database Access

The CLI reads Vapor's existing databases directly:

- **SwiftData:** `~/Library/Application Support/Vapor/default.store`
- **Vectors:** `~/Library/Application Support/Vapor/vectors.db`
- **Blobs:** `~/Library/Application Support/Vapor/blobs/`

For the embedding model in CLI search, either:

- Bundle the MiniLM CoreML model (~50MB) with the CLI package
- Or fall back to keyword-only search when the model isn't available

---

## 8. Full-Context Git Export

### 8.1 Directory Structure

**Date-based storage** (actual files):

```
.vapor-context/
+-- sessions/
|   +-- 2025-05-01/
|       +-- a3f7c912-4b2e-41d0-8e2f-1234567890ab/
|           +-- transcript.md
|           +-- meta.json
|           +-- entities.json
|           +-- vectors.jsonl
|           +-- images/
|           |   +-- 14-23-01.webp
|           |   +-- 14-45-17.webp
|           +-- media/
|           |   +-- docs-spec.pdf       (if PDFs were in context)
|           |   +-- recording.mp4       (if video clips were captured)
|           +-- urls/
|               +-- references.jsonl    (URLs with fetched metadata)
```

**Branch-aligned index** (symlinks):

```
.vapor-context/
+-- by-branch/
|   +-- main/
|   |   +-- a3f7c912-... -> ../../sessions/2025-05-01/a3f7c912-...
|   |   +-- b4e8d023-... -> ../../sessions/2025-05-01/b4e8d023-...
|   +-- feature/
|       +-- auth-refactor/
|           +-- d6a0f245-... -> ../../sessions/2025-05-02/d6a0f245-...
|           +-- e7b1g356-... -> ../../sessions/2025-05-03/e7b1g356-...
+-- branches/
    +-- feature/
        +-- auth-refactor/
            +-- sessions.jsonl    # [{"sessionId": "...", "date": "...", "title": "...", "turnCount": 47}]
```

### 8.2 meta.json (expanded)

```json
{
  "sessionID": "a3f7c912-...",
  "title": "My Express API Project",
  "tool": "opencode",
  "modelID": "claude-opus-4-5",
  "projectPath": "/Users/alice/projects/my-api",
  "projectName": "my-api",
  "branchName": "feature/auth-refactor",
  "prNumber": 42,
  "startedAt": "2025-05-01T14:23:01Z",
  "endedAt": "2025-05-01T16:37:14Z",
  "turnCount": 47,
  "estimatedTokens": 18432,
  "tags": ["rate-limiting", "api-design", "bug-fix"],
  "summary": {
    "abstract": "Refactored Express API to add rate limiting...",
    "keyPoints": ["Added express-rate-limit middleware", "Configured 15-min window"]
  },
  "entityCount": 23,
  "uniqueEntities": 15,
  "imageCount": 2,
  "urlCount": 8,
  "vaporVersion": "1.0.6",
  "embeddingModel": "paraphrase-multilingual-MiniLM-L12-v2",
  "embeddingDimensions": 384,
  "redaction": {
    "totalRedactions": 3,
    "redactedTurnIDs": ["turn-5"],
    "redactedPatterns": ["API_KEY", "password"]
  }
}
```

### 8.3 entities.json

```json
{
  "sessionID": "a3f7c912-...",
  "entities": [
    {
      "kind": "library",
      "displayText": "express-rate-limit",
      "confidence": 0.95,
      "occurrences": 12,
      "linkedTurns": ["turn-1", "turn-2", "turn-5"]
    },
    {
      "kind": "decision",
      "displayText": "Use 15-minute sliding window for rate limiting",
      "confidence": 0.85,
      "occurrences": 3,
      "linkedTurns": ["turn-3", "turn-7"]
    }
  ]
}
```

### 8.4 urls/references.jsonl

One JSON object per URL encountered in the session:

```json
{"url":"https://expressjs.com/en/guide/rate-limiting.html","domain":"expressjs.com","firstSeenAt":"2025-05-01T14:25:00Z","turnID":"turn-2","title":"Rate Limiting - Express.js"}
```

### 8.5 Secrets Redaction (Regex + LLM Hybrid)

**Phase 1: Regex patterns** (runs first, fast)

```
# API key patterns
sk-or-v1-[a-zA-Z0-9]{48}
sk-ant-[a-zA-Z0-9\-_]{48,}
ghp_[a-zA-Z0-9]{36}
gho_[a-zA-Z0-9]{36}
glpat-[a-zA-Z0-9\-_]{20,}

# Generic secret patterns
password\s*[=:]\s*\S+
secret\s*[=:]\s*\S+
token\s*[=:]\s*\S+
api_key\s*[=:]\s*\S+
Bearer\s+[a-zA-Z0-9\-._~+/]+=*

# File paths with sensitive names
~/.ssh/
~/.aws/credentials
.env
.id_rsa

# Private/internal URLs
internal\.company\.com
localhost:\d+

# User-configurable denylist
(custom patterns from UserPreferences.exportDenylistPatterns)
```

**Phase 2: LLM pass** (runs on regex output, for contextual secrets)

```
System: You are a secrets redaction assistant. Review the following text
and identify any sensitive information that should be redacted before
committing to a git repository. This includes:
- Credentials, API keys, tokens, passwords
- Internal/private URLs or endpoints
- Personally identifiable information (PII)
- Company-internal project names or codenames
- Database connection strings
- Private keys or certificates

Return a JSON array of strings to redact:
[{"match": "exact text to replace", "reason": "category"}]
```

**Phase 3: Denylist** (user-configurable strings/patterns)

Users define in Settings:

```
# Examples:
my-company-internal-api
project-codename-alpha
jira.internal.company.com
```

**Redaction output:**

- Redacted text replaced with `[REDACTED: <reason>]`
- Count of redactions stored in `meta.json`
- Pre-commit preview sheet shows all redactions with original text (truncated) and reason
- User can approve, skip specific redactions, or cancel

### 8.6 Media Export

| Asset Type | Storage | Notes |
|-----------|---------|-------|
| Screenshots | `images/` as WebP (0.85 quality) | Already supported by ImageConverter |
| PDFs | `media/` original file | Stored as-is with hash-based filename |
| Video clips | `media/` original file | May be large; optional include/exclude toggle |
| Animated GIFs | `media/` original file | Already in ImageAsset model |
| URLs | `urls/references.jsonl` | Metadata only (title, domain, first seen) |

`.gitattributes`:

```
.vapor-context/sessions/**/*.webp binary
.vapor-context/sessions/**/*.pdf binary
.vapor-context/sessions/**/*.mp4 binary
.vapor-context/sessions/**/*.gif binary
.vapor-context/by-branch/** symlink
```

### 8.7 Commit Strategy

```
# Atomic commit per session
git add .vapor-context/sessions/2025-05-01/<uuid>/ .vapor-context/by-branch/<branch>/<uuid>
git commit -m "vapor: add AI session [<tool>] <title> (<turnCount> turns)"

# Branch index updated separately
git add .vapor-context/branches/<branch>/sessions.jsonl
git commit -m "vapor: update branch session index for <branch>"
```

### 8.8 Project-Level Full-Context Export

When exporting for a project, Vapor collects ALL context for the project (not just AI sessions):

- All `ContextItem` records for the project -> exported as markdown references
- All `PromptRecord` records for the project -> exported as `prompts.md`
- All `ImageAsset` records for the project -> exported as WebP
- All `AISession` records -> exported as `transcript.md`
- All `EntityRecord` links -> exported as `entities.json`
- All URLs -> exported as `urls/references.jsonl`

This gives a complete picture of "everything we thought about and researched while building this feature."

### 8.9 Re-import Flow

When another developer pulls the repo:

1. Scan `.vapor-context/sessions/` for unimported session directories
2. Read `meta.json` -> validate embedding dimensions
3. Fast path: read `vectors.jsonl` -> bulk insert into local SQLite-vec (~1s per 100 turns)
4. Slow path: re-embed from `transcript.md` turn-by-turn (~10s per 100 turns)
5. Create `AISession`, `AITurn`, entity links, tags from `entities.json` + `meta.json`
6. Link images from `images/` to their turns

---

## 9. Implementation Roadmap

### Phase 0.5 -- Project Anchoring Foundation

| Issue | Size | Description |
|-------|------|-------------|
| PROJECT-01 | L | Create `VaporProject` model + `VaporProjectBookmark` + migration (VaporSchemaV2) |
| PROJECT-02 | M | Add optional `project` FK to `ContextItem`, `PromptRecord`, `ImageAsset` |
| PROJECT-03 | L | Implement `ProjectService` with auto-detection (git CWD + browser URL) |
| PROJECT-04 | M | Project picker UI in sidebar with active project state |
| PROJECT-05 | M | Project-scoped Context Explorer (filter all facets by project) |
| PROJECT-06 | S | Security-scoped bookmarks for persistent folder access |
| PROJECT-07 | M | Project-level full-context git export (all context types, not just sessions) |

### Phase 0 -- Foundation (expand PR #19 plan)

| Issue | Size | Description |
|-------|------|-------------|
| AI-SESSION-01b | M | Expand `AISession` / `AITurn` models with entities, tags, branch, PR, summary, metrics |
| AI-SESSION-01c | S | Add `AISessionEntityLink`, `AITurnEntityLink`, `AISessionTag`, `AIGitExportRecord` models |
| AI-SESSION-01d | S | Expand `EntityKind` with `model`, `tool`, `library`, `api`, `file`, `error`, `decision` |
| AI-SESSION-02b | M | Add `aisession_meta` SQLite table for faceted vector search |
| AI-SESSION-30 | L | Design and implement `SessionCaptureFacade` + adapter protocol |

### Phase 1 -- OpenCode Capture

| Issue | Size | Description |
|-------|------|-------------|
| AI-SESSION-05b | L | `OpenCodeAdapter`: FSEvents watcher, JSONL parser, path resolution, project detection |
| AI-SESSION-31 | M | Per-turn entity extraction pipeline (reuse `EntityExtractionService`) |
| AI-SESSION-32 | S | Per-turn auto-tagging (adapt `TaggerService` for session turns) |
| AI-SESSION-33 | M | Session summary + decision extraction on session close |
| AI-SESSION-12b | S | Auto-vectorize each turn with `aisession:` namespace |

### Phase 2 -- HTTP API

| Issue | Size | Description |
|-------|------|-------------|
| AI-SESSION-40 | L | Session CRUD + project endpoints on existing 8766 server |
| AI-SESSION-41 | L | Search endpoints (semantic + faceted) with `aisession_meta` joins |
| AI-SESSION-42 | M | Entity graph endpoints (entity detail, related entities, adjacency) |
| AI-SESSION-43 | M | Export preview + commit endpoints |

### Phase 3 -- CLI Package

| Issue | Size | Description |
|-------|------|-------------|
| AI-SESSION-50 | L | Scaffold `vapor-cli` SwiftPM package with argument parser |
| AI-SESSION-51 | M | `search` command (semantic + faceted, reads vectors.db directly) |
| AI-SESSION-52 | M | `sessions` command (list, show, export, import) |
| AI-SESSION-53 | M | `entities` command (search, graph) |
| AI-SESSION-54 | S | `status` command (DB stats, capture status) |

### Phase 4 -- Git Export with Redaction

| Issue | Size | Description |
|-------|------|-------------|
| AI-SESSION-60 | L | Full-context git export (transcript, meta, entities, vectors, images, media, URLs) |
| AI-SESSION-61 | L | Secrets redaction engine (regex patterns + LLM pass + user denylist) |
| AI-SESSION-62 | M | Branch-aligned symlinks + branch session index |
| AI-SESSION-63 | M | Pre-commit preview UI (file list, redaction summary, approve/cancel) |
| AI-SESSION-64 | M | Re-import flow (fast path from vectors.jsonl, slow path re-embed) |

### Phase 5 -- Context Explorer UI

| Issue | Size | Description |
|-------|------|-------------|
| AI-SESSION-70 | M | AI Sessions section in Context Explorer sidebar |
| AI-SESSION-71 | M | Session list view (title, tool, branch, PR, tags, entity count, turn count) |
| AI-SESSION-72 | L | Session reader view (chronological Q&A with entity highlights, images, URLs) |
| AI-SESSION-73 | M | Entity graph visualization (adjacency from co-occurrence in sessions) |

---

## 10. Dependency Graph

```
PROJECT-01 (VaporProject model)
    +-- PROJECT-02 (FK on existing models)
    |       +-- PROJECT-05 (scoped Context Explorer)
    |       +-- PROJECT-07 (project-level export)
    |       +-- AI-SESSION-01b (AISession gains project FK)
    +-- PROJECT-03 (ProjectService + auto-detection)
    |       +-- AI-SESSION-05b (OpenCodeAdapter uses project detection)
    |       +-- AI-SESSION-30 (facade uses project service)
    +-- PROJECT-04 (project picker UI)
    +-- PROJECT-06 (bookmarks)

AI-SESSION-01b (expanded models)
    +-- AI-SESSION-01c (join models)
    +-- AI-SESSION-01d (expanded EntityKind)
    +-- AI-SESSION-02b (aisession_meta table)

AI-SESSION-30 (facade + adapter protocol)
    +-- AI-SESSION-05b (OpenCodeAdapter)
    |       +-- AI-SESSION-31 (per-turn entity extraction)
    |       +-- AI-SESSION-32 (per-turn tagging)
    |       +-- AI-SESSION-33 (session summary + decisions)
    |       +-- AI-SESSION-12b (auto-vectorize turns)
    +-- AI-SESSION-05 (Claude Desktop) [future]

AI-SESSION-40..43 (HTTP API)
    requires: 01b, 02b, PROJECT-01

AI-SESSION-50..54 (CLI)
    requires: 01b, 02b, 40 (shares model definitions)

AI-SESSION-60..64 (git export + redaction)
    requires: 01b, 01c, 05b, PROJECT-01

AI-SESSION-70..73 (UI)
    requires: 01b, 05b, 40, PROJECT-04, PROJECT-05
```
