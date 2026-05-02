# Plan: AI Session Capture

## Overview

**AI Session Capture** transforms Vapor into a persistent memory layer for every AI-assisted coding or research session. As a developer works in tools like OpenCode, Claude Desktop, Cursor, Continue.dev, or any other AI system, Vapor silently captures the full Q&A transcript, interleaves it with screenshots and other ambient context, vectorizes each turn for semantic search, and optionally commits the entire session to a git repository — so any developer on the team can later reconstruct exactly what happened, search it semantically, and re-vectorize it in their own Vapor instance.

This feature is intentionally **additive and non-intrusive**: it captures what is already flowing through log files, IPC endpoints, or local HTTP APIs that AI tools already expose. No secret credentials are ever sent to external services. All vectorization is on-device using the existing MiniLM embedding pipeline.

---

## User Stories

> As a developer, after a long OpenCode or Claude session, I want Vapor to have already captured every question I asked and every answer the AI gave — so I can search my past sessions semantically ("when did I ask about rate-limiting") without re-opening the AI tool.

> As a team, when I open a PR I want the complete AI context that produced that PR committed alongside the code — so my reviewer can understand not just *what* changed but *why*, without any extra effort from me.

> As a new team member, I want to pull a repo and immediately have my Vapor instance understand all the AI-assisted work that happened before I joined — by re-vectorizing the committed session transcripts.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            External AI Tools                                │
│                                                                             │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │  OpenCode    │  │  Claude Desktop  │  │   Cursor     │  │ Continue  │  │
│  │ (log files)  │  │  (log files /    │  │ (local HTTP) │  │ (VS Code  │  │
│  │              │  │   local API)     │  │              │  │  ext API) │  │
│  └──────┬───────┘  └────────┬─────────┘  └──────┬───────┘  └─────┬─────┘  │
└─────────┼───────────────────┼───────────────────┼───────────────┼─────────┘
          │                   │                   │               │
          └───────────────────┴───────────────────┴───────────────┘
                                      │
                         ┌────────────▼────────────┐
                         │  AISessionCaptureService │
                         │                         │
                         │  ┌────────────────────┐ │
                         │  │ LogFileWatcher     │ │  (FSEvents / NSFilePresenter)
                         │  │ LocalAPIPoller     │ │  (HTTP long-poll / SSE)
                         │  │ ClipboardParser    │ │  (optional heuristic fallback)
                         │  └────────────────────┘ │
                         └────────────┬────────────┘
                                      │
                         ┌────────────▼────────────┐
                         │  Q&A Turn Segmentation  │
                         │  (parse log → AITurn[]) │
                         └────────────┬────────────┘
                                      │
               ┌──────────────────────┼────────────────────────┐
               │                      │                        │
   ┌───────────▼──────────┐ ┌─────────▼──────────┐ ┌──────────▼──────────┐
   │  SwiftData Layer     │ │ VectorizationSvc   │ │ ScreenshotSvc       │
   │  AISession           │ │ embed each AITurn  │ │ attach nearby       │
   │  AITurn              │ │ with MiniLM        │ │ screenshots to turn │
   └───────────┬──────────┘ └─────────┬──────────┘ └──────────┬──────────┘
               │                      │                        │
               └──────────────────────▼────────────────────────┘
                                      │
                         ┌────────────▼────────────┐
                         │   GitExportService      │
                         │   (optional commit to   │
                         │    project git repo)    │
                         └─────────────────────────┘
```

---

## Data Models

### AISession (SwiftData)

A session groups all Q&A turns that occurred within a single continuous working context (typically scoped to a tool process, a project directory, or a time window).

```swift
@Model
final class AISession {
    var id: UUID
    var title: String              // auto-generated from first Q, editable
    var tool: String               // "opencode" | "claude-desktop" | "cursor" | "continue" | "manual"
    var projectPath: String?       // absolute path to git repo root (nil if no repo detected)
    var projectName: String?       // last path component of projectPath
    var startedAt: Date
    var endedAt: Date?             // nil while session is still live
    var tags: [String]
    var isArchived: Bool
    var gitCommitSHA: String?      // SHA of the commit that exported this session (if any)
    var embeddingID: String?       // embedding of the session summary for top-level search

    @Relationship(deleteRule: .cascade, inverse: \AITurn.session)
    var turns: [AITurn] = []

    @Relationship(deleteRule: .nullify, inverse: \ImageAsset.aiSession)
    var attachedImages: [ImageAsset] = []
}
```

### AITurn (SwiftData)

One discrete question or answer within a session. Each turn is independently vectorized so that semantic search can surface individual exchanges rather than entire sessions.

```swift
@Model
final class AITurn {
    var id: UUID
    var session: AISession?        // parent session
    var role: String               // "user" | "assistant" | "system" | "tool"
    var turnIndex: Int             // ordinal position within the session
    var content: String            // full raw text of the turn
    var contentTokenCount: Int     // estimated token count
    var capturedAt: Date
    var embeddingID: String?       // "aisession:" namespaced vector ID

    // Optional rich metadata
    var modelID: String?           // e.g. "claude-opus-4-5", "gpt-4o"
    var toolName: String?          // filled when role == "tool"
    var attachedImageIDs: [String] // UUIDs of ImageAsset records attached to this turn
    var durationSeconds: Double?   // time the AI took to produce this response (if available)
    var isEdited: Bool             // user manually corrected the captured text
}
```

### Embedding Namespace

The vectorization service uses a `"aisession:"` prefix to namespace AI session turn embeddings within the shared SQLite-vec table, consistent with the existing `"ctx:"` and `"prompt:"` namespaces:

```
aisession:<turn-uuid>
```

---

## Capture Backends

### 1. OpenCode Log Watcher (Primary Target)

OpenCode is open-source and stores its conversation history in a structured log file (JSONL format) at a well-known path under `~/.local/share/opencode/` or `~/.config/opencode/`. Vapor watches this file with `FSEventStream` (via `FileSystemWatcher`), parsing new lines as they are appended.

**Log Format (JSONL, one message per line):**
```json
{"role":"user","content":"How do I add rate limiting to my Express API?","timestamp":"2025-05-01T14:23:01Z"}
{"role":"assistant","content":"You can use the `express-rate-limit` package...","timestamp":"2025-05-01T14:23:05Z","model":"claude-opus-4-5"}
```

**Watcher configuration path resolution order:**
1. OpenCode `config.json` → `logDir` field
2. `$XDG_DATA_HOME/opencode/` if `XDG_DATA_HOME` is set
3. `~/.local/share/opencode/`
4. `~/.config/opencode/`

Vapor stores the resolved log path in `UserDefaults` so it survives restarts without re-scanning.

### 2. Claude Desktop / Anthropic Tools

Claude Desktop stores its conversation log in Application Support:
```
~/Library/Application Support/Claude/logs/conversation-*.jsonl
```

The log format is similar JSONL. Vapor watches with `NSFilePresenter` and parses on each `presentedItemDidChange` call.

### 3. Cursor / Continue.dev (Local HTTP Long-Poll)

Cursor and Continue.dev expose a local WebSocket or HTTP SSE endpoint while running. Vapor connects to the well-known port and subscribes to turn events:

- Cursor: `ws://localhost:65002/api/chat-stream`
- Continue: `http://localhost:65432/api/history` (polling every 2 seconds when active)

The connection is made only if the process is detected as running (via `NSRunningApplication` or a lightweight `/proc` scan).

### 4. Clipboard Heuristic Fallback

For any AI tool not natively supported, users can opt into a heuristic clipboard monitor:

- When the clipboard changes and contains text formatted as a Q&A exchange (detected by structural heuristics: "User:", "Assistant:", code fences, etc.), Vapor prompts to append it as a manual turn to the current session.

### 5. Manual Paste

A dedicated "Paste Q&A" toolbar button and keyboard shortcut (`⌘⌥V`) lets users manually paste any AI conversation text. Vapor segments it into turns automatically.

---

## Session Lifecycle

```
1. DETECT        Tool process starts → Vapor opens watcher
2. SESSION OPEN  First Q turn received → AISession created with projectPath detected from CWD of tool process
3. CAPTURE       Each turn appended to AISession in real time; vectorized asynchronously
4. SCREENSHOT    Nearby screenshots (within ±30 seconds of a turn) attached automatically
5. SESSION CLOSE Tool process exits OR no new turns for 30 minutes → AISession.endedAt set
6. EXPORT        User triggers git commit → GitExportService writes markdown + images → commits
```

### Project Path Detection

The project being worked on is inferred from the tool process working directory:

```swift
func detectProjectPath(for tool: AICapturedTool) -> String? {
    let matches = NSRunningApplication.runningApplications(
        withBundleIdentifier: tool.bundleID
    )
    guard let pid = matches.first?.processIdentifier else { return nil }
    return processWorkingDirectory(pid: Int32(pid))  // read /proc/<pid>/cwd via sysctl
}
```

If the CWD is inside a git repository, the git root is resolved with `git rev-parse --show-toplevel` (run in a `Process`).

---

## Vector Storage

Each `AITurn` is vectorized using the existing `MiniLMEmbeddingService` with a combined text representation:

```
[ROLE: user]
How do I add rate limiting to my Express API?

[SESSION: My Express API Project — 2025-05-01]
[TOOL: opencode] [MODEL: claude-opus-4-5]
```

This format ensures that:
- Semantic searches for questions surface user turns
- Semantic searches for explanations surface assistant turns  
- Session and tool context is embedded without dominating the semantic signal

Embeddings are stored in the existing `vec_items_minilm_l12_multilingual_v2` SQLite-vec table with the `aisession:` prefix, so they are automatically included in the global semantic search already wired to the Context Explorer.

### VectorizationService Extension

```swift
// New method added to VectorizationService
func ensureEmbedding(for turn: AITurn, force: Bool = false) async throws -> String? {
    let prefix = "aisession:"
    let embeddingID = "\(prefix)\(turn.id.uuidString)"
    if !force, let existingID = turn.embeddingID,
       existingID.hasPrefix(prefix),
       try await embeddingExists(id: existingID) {
        return existingID
    }
    let text = searchableText(for: turn)
    guard !text.isEmpty else { return nil }
    let embedding = try await generateEmbedding(for: text)
    try await upsert(embedding: embedding, id: embeddingID)
    turn.embeddingID = embeddingID
    return embeddingID
}
```

---

## Screenshot Interleaving

When a new screenshot is detected by `ScreenshotWatcherService` and a live AI session is active, Vapor automatically:

1. Records the screenshot timestamp.
2. After a 30-second window, checks whether any AITurn was captured within ±30 seconds of the screenshot.
3. If yes, links the `ImageAsset` to the nearest turn via `AITurn.attachedImageIDs`.

This produces a timeline that is temporally accurate without requiring the user to manually associate screenshots.

Screenshots committed to git (see below) are stored as WebP files to minimize repo size. The conversion uses `NSBitmapImageRep` with a 0.85 quality factor.

---

## Context Explorer Integration

AI sessions appear as a new **"AI Sessions"** facet in the Context Explorer sidebar alongside Domains, Authors, etc. Clicking an AI session opens a chronological reader view:

```
┌──────────────────────────────────────────────────────────────────┐
│  AI Session: My Express API Project — May 1, 2025               │
│  OpenCode · claude-opus-4-5 · 2h 14m · 47 turns                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  14:23  USER                                                      │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ How do I add rate limiting to my Express API?               │ │
│  └─────────────────────────────────────────────────────────────┘ │
│         📷  [screenshot: error-stacktrace.webp]                  │
│                                                                   │
│  14:23  ASSISTANT · claude-opus-4-5                              │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ You can use the `express-rate-limit` package...             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

Individual turns are also surfaced in semantic search results (just like ContextItems today), with a chip showing the session title.

---

## Git Export

See `docs/plan-ai-session-git-export.md` for the full design. Summary:

- **Trigger:** User clicks "Commit Session to Git" in the session detail view, or it happens automatically when `AISession.endedAt` is set and a git root was detected.
- **Output:** A `vapor-sessions/<YYYY-MM-DD>/<session-uuid>/` directory committed to the project repo.
- **Contents:**
  - `transcript.md` — full Q&A in Markdown with timestamps
  - `images/` — screenshots as WebP files, named by timestamp
  - `meta.json` — session metadata (tool, model, project, token counts)
  - `vectors.jsonl` — raw float32 embeddings for each turn (for re-vectorization)
- **Commit message:** `vapor: add AI session transcript [<tool>] <title>`

When another developer pulls the repo and opens it in their own Vapor instance, the `vectors.jsonl` file allows **one-click re-vectorization** without re-running the embedding model — the vectors are simply imported directly into their local SQLite-vec database.

---

## Settings

A new **AI Session Capture** section is added to `SettingsView`:

| Setting | Type | Default |
|---|---|---|
| Enable AI Session Capture | Toggle | Off (opt-in) |
| OpenCode log path | Path picker | auto-detected |
| Watch Claude Desktop | Toggle | On (when enabled) |
| Watch Cursor (local API) | Toggle | On (when enabled) |
| Watch Continue.dev (local API) | Toggle | On (when enabled) |
| Clipboard heuristic fallback | Toggle | Off |
| Session idle timeout | Stepper (5–120 min) | 30 min |
| Screenshot attachment window | Stepper (10–120 sec) | 30 sec |
| Auto-commit to git | Toggle | Off |
| Auto-commit trigger | Picker (On session close / Daily / Manual) | Manual |
| Include raw embeddings in git | Toggle | On |
| Max sessions to keep | Stepper (10–500) | 100 |

---

## Permissions Required

| Action | Mechanism |
|---|---|
| Read OpenCode log files | `FSEventStream` — no special permission, files in user home |
| Read Claude Desktop logs | `NSFilePresenter` — App Support is readable by the user |
| Connect to Cursor / Continue local API | `NSURLSession` loopback — no entitlement needed |
| Detect running AI tool processes | `NSRunningApplication` — no special entitlement |
| Read process CWD | `sysctl(KERN_PROC_PATHNAME)` — no entitlement, works for processes owned by user |
| Run `git` subprocess | `Process` — no entitlement needed, git is a user binary |
| Write to project git repo | Normal file system access (project dir is user-owned) |

The app sandbox is already disabled (`com.apple.security.app-sandbox = false`), so no entitlement changes are needed.

---

## Implementation Phases

### Milestone 1 — Data Models & Plumbing (1 week)

**Issues to open:**
- `[AI-SESSION-01]` Add `AISession` and `AITurn` SwiftData models with migration
- `[AI-SESSION-02]` Add `aisession:` namespace to `VectorizationService.ensureEmbedding`
- `[AI-SESSION-03]` Create `AISessionService` (singleton, `@Observable`) to manage active session lifecycle
- `[AI-SESSION-04]` Extend `ContextItemKind` with `.aiSessionTurn` for Context Explorer surfacing

**Deliverable:** Models compile, migrate cleanly, unit tests pass.

---

### Milestone 2 — Capture Backends (2 weeks)

**Issues to open:**
- `[AI-SESSION-05]` Implement `OpenCodeLogWatcher` (FSEvents, JSONL parser, path resolution)
- `[AI-SESSION-06]` Implement `ClaudeDesktopLogWatcher` (NSFilePresenter, JSONL parser)
- `[AI-SESSION-07]` Implement `CursorLocalAPIClient` (WebSocket subscriber)
- `[AI-SESSION-08]` Implement `ContinueLocalAPIClient` (HTTP polling)
- `[AI-SESSION-09]` Implement `ClipboardHeuristicParser` (opt-in fallback)
- `[AI-SESSION-10]` Project path + git root detection via `sysctl` + `git rev-parse`
- `[AI-SESSION-11]` Session idle-timeout and auto-close logic

**Deliverable:** End-to-end capture for OpenCode and Claude Desktop. Other backends can be added incrementally.

---

### Milestone 3 — Vectorization & Screenshot Interleaving (1 week)

**Issues to open:**
- `[AI-SESSION-12]` Auto-vectorize each `AITurn` as it is captured (async, non-blocking)
- `[AI-SESSION-13]` Session-level summary embedding (first Q + turn count + tool)
- `[AI-SESSION-14]` Screenshot temporal matching and `AITurn.attachedImageIDs` population
- `[AI-SESSION-15]` Backfill service: re-vectorize all historical turns on app launch

**Deliverable:** Semantic search in Context Explorer returns AI session turns.

---

### Milestone 4 — Context Explorer & UI (1 week)

**Issues to open:**
- `[AI-SESSION-16]` Add "AI Sessions" section to Context Explorer sidebar
- `[AI-SESSION-17]` Session list view (title, tool, date, turn count, duration)
- `[AI-SESSION-18]` Session reader view (chronological Q&A with screenshot thumbnails)
- `[AI-SESSION-19]` Turn detail: copy turn, open in Vapor editor, add to prompt
- `[AI-SESSION-20]` Search integration: AI turns appear in global semantic search results

**Deliverable:** Users can browse and search past AI sessions from Vapor.

---

### Milestone 5 — Git Export (1 week)

See `docs/plan-ai-session-git-export.md` for full design.

**Issues to open:**
- `[AI-SESSION-21]` `GitExportService`: write `transcript.md`, `meta.json`, `vectors.jsonl`, WebP images
- `[AI-SESSION-22]` "Commit Session" UI in session detail view
- `[AI-SESSION-23]` Auto-commit option (triggered on session close)
- `[AI-SESSION-24]` Re-vectorization import: read `vectors.jsonl` from a git-committed session

**Deliverable:** A session committed to git can be re-vectorized in another developer's Vapor instance.

---

### Milestone 6 — Settings, Onboarding & Polish (3 days)

**Issues to open:**
- `[AI-SESSION-25]` Add AI Session Capture section to `SettingsView`
- `[AI-SESSION-26]` Onboarding prompt: request folder access on first enable (scoped bookmark)
- `[AI-SESSION-27]` StatusBar log integration: session open/close/turn-captured events
- `[AI-SESSION-28]` Privacy: "Pause capture" toggle in menu bar for sensitive sessions

---

## Privacy & Security

- **No data ever leaves the device** unless the user explicitly commits to git or exports manually.
- All vectorization is on-device (MiniLM via the existing embedded model).
- The "Pause capture" toggle immediately suspends all watchers and closes the active session without saving the current buffer.
- Log file paths displayed in Settings are resolved locally and never stored in any analytics service.
- The clipboard heuristic fallback is off by default to avoid accidental capture.

---

## Open Questions & Risks

| Question | Notes |
|---|---|
| OpenCode log format stability | JSONL format should be stable; add a version check and graceful fallback on parse failure |
| Cursor local API availability | Cursor's local API is undocumented; fall back to clipboard heuristic if connection refused |
| Large session performance | Sessions > 1,000 turns need lazy loading in the reader view and chunked vectorization |
| Re-vectorization on import | `vectors.jsonl` float32 blobs must match the MiniLM dimension (384); validate on import |
| Sensitive content in git | Warn users with a pre-commit summary showing turn count and token estimate before committing |

---

## Success Metrics

| Metric | Target |
|---|---|
| Latency from AI turn completed to turn captured in Vapor | < 3 seconds |
| Semantic search recall (top-10) for a known past question | > 90% on a 500-turn corpus |
| Git export file size for a 100-turn session with 10 screenshots | < 5 MB |
| Re-vectorization time for an imported 100-turn session | < 10 seconds on Apple Silicon |

---

## References

- [OpenCode source — conversation storage](https://github.com/sst/opencode)
- [Claude Desktop Application Support paths](https://support.anthropic.com/en/articles/claude-desktop-app)
- [Cursor local extension API](https://docs.cursor.com)
- [Continue.dev local history API](https://continue.dev/docs)
- [SQLite-vec extension](https://github.com/asg017/sqlite-vec)
- [MiniLM paraphrase-multilingual-L12-v2](https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2)
- [FSEventStream programming guide](https://developer.apple.com/documentation/coreservices/file_system_events)
