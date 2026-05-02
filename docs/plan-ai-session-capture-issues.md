# Proposed Issues: AI Session Capture

This document lists every issue and sub-issue that should be opened in GitHub to execute the AI Session Capture feature described in `docs/plan-ai-session-capture.md` and `docs/plan-ai-session-git-export.md`.

Each item is tagged with the milestone it belongs to and an estimated complexity (S / M / L).

---

## Milestones

| Milestone | Description | Est. Calendar |
|---|---|---|
| M1: Data Models & Plumbing | SwiftData schema, vectorization namespace | Week 1 |
| M2: Capture Backends | Log watchers, local API clients, project detection | Weeks 2–3 |
| M3: Vectorization & Screenshots | Per-turn embedding, screenshot interleaving | Week 4 |
| M4: Context Explorer & UI | Session browser, reader view, search integration | Week 5 |
| M5: Git Export | Export, import, re-vectorization | Week 6 |
| M6: Settings & Polish | Preferences, onboarding, status bar, privacy | Week 7 |

---

## Issues

### Milestone 1 — Data Models & Plumbing

#### [AI-SESSION-01] Add AISession and AITurn SwiftData models
- **Size:** M
- **Description:** Create `AISession.swift` and `AITurn.swift` under `Vapor/Models/`, add them to `VaporSchema.swift` with a new schema version and a lightweight migration. Include unit tests for model creation and relationship traversal.
- **Acceptance criteria:** App builds and launches without SwiftData migration failure on a device with existing data.

#### [AI-SESSION-02] Add aisession: embedding namespace to VectorizationService
- **Size:** S
- **Description:** Add `ensureEmbedding(for:AITurn:force:)` method to `VectorizationService`, using the `aisession:` prefix. Add `searchAISessionTurnIDs(matching:limit:)` semantic search method. Update `candidateEmbeddingIDs` to include the new prefix.
- **Acceptance criteria:** Unit test: embed a turn, search for it by content, confirm the turn UUID is returned.

#### [AI-SESSION-03] Create AISessionService singleton
- **Size:** M
- **Description:** `@MainActor @Observable final class AISessionService` with methods: `startSession(tool:projectPath:)`, `appendTurn(role:content:modelID:)`, `closeCurrentSession()`, `pauseCapture()`, `resumeCapture()`. Manages the single in-flight `AISession` and delegates persistence to SwiftData.
- **Acceptance criteria:** Unit test drives the full lifecycle; SwiftData records are saved correctly.

#### [AI-SESSION-04] Extend ContextItemKind with .aiSessionTurn
- **Size:** S
- **Description:** Add `.aiSessionTurn` case to `ContextItemKind` enum with appropriate `displayName` and `systemImage`. This allows the Context Explorer to render AI session turns alongside regular context items in search results.
- **Acceptance criteria:** Enum compiles, existing switch statements are exhaustive (no new warnings).

---

### Milestone 2 — Capture Backends

#### [AI-SESSION-05] Implement OpenCodeLogWatcher
- **Size:** L
- **Description:** `FSEventStream`-based file watcher for OpenCode JSONL conversation logs. Includes path resolution (config.json → XDG_DATA_HOME → ~/.local/share/opencode → ~/.config/opencode), incremental JSONL parsing (only new lines since last read position), and delegation to `AISessionService`. Handles file rotation (new session file per conversation).
- **Acceptance criteria:** Manual test — start an OpenCode session, observe new turns appearing in `AISessionService` within 3 seconds.

#### [AI-SESSION-06] Implement ClaudeDesktopLogWatcher
- **Size:** M
- **Description:** `NSFilePresenter`-based watcher for `~/Library/Application Support/Claude/logs/conversation-*.jsonl`. Includes glob-based discovery of the most recent log file, JSONL parsing, and delegation to `AISessionService`.
- **Acceptance criteria:** Manual test — start a Claude Desktop session, observe new turns within 5 seconds.

#### [AI-SESSION-07] Implement CursorLocalAPIClient
- **Size:** M
- **Description:** WebSocket client subscribing to `ws://localhost:65002/api/chat-stream`. Detects Cursor process via `NSRunningApplication`. Reconnects automatically if the connection drops. Falls back to clipboard heuristic if connection is refused after 3 attempts.
- **Acceptance criteria:** Unit test with a mock WebSocket server; integration test via manual Cursor session.

#### [AI-SESSION-08] Implement ContinueLocalAPIClient
- **Size:** M
- **Description:** HTTP polling client against `http://localhost:65432/api/history`. Polls every 2 seconds when Continue's VS Code extension process is detected as running. Deduplicates turns by comparing against last-seen turn index.
- **Acceptance criteria:** Unit test with a mock HTTP server returning incrementally growing history.

#### [AI-SESSION-09] Implement ClipboardHeuristicParser
- **Size:** S
- **Description:** Optional clipboard monitor that detects Q&A formatted text (structural heuristics: "User:" / "Assistant:" prefixes, alternating indentation, code fence density). When triggered, prompts the user to append to the current session. Off by default.
- **Acceptance criteria:** Unit tests for heuristic detection across 10 sample Q&A formats from common AI tools.

#### [AI-SESSION-10] Project path and git root detection
- **Size:** S
- **Description:** Utility function `detectProjectPath(for tool: AICapturedTool) -> String?` using `sysctl(KERN_PROC_PATHNAME)` to read the process CWD of the detected tool process, then resolving the git root with `git rev-parse --show-toplevel` via `Process`. Cache the result per session.
- **Acceptance criteria:** Unit test mocking a running process at a known CWD inside a git repo.

#### [AI-SESSION-11] Session idle-timeout and auto-close logic
- **Size:** S
- **Description:** `AISessionService` starts a 30-minute idle timer on each turn received. If no new turn arrives before the timer fires, `closeCurrentSession()` is called automatically. The timeout duration is configurable via `UserPreferences`. Also close on tool process exit (detected via `NSRunningApplication` KVO).
- **Acceptance criteria:** Unit test drives the timer with a mock clock.

---

### Milestone 3 — Vectorization & Screenshot Interleaving

#### [AI-SESSION-12] Auto-vectorize each AITurn as it is captured
- **Size:** S
- **Description:** In `AISessionService.appendTurn(...)`, after inserting the `AITurn` into SwiftData, fire-and-forget a `Task` to call `VectorizationService.shared.ensureEmbedding(for: turn)`. Errors are logged to `StatusBarService` but do not interrupt capture.
- **Acceptance criteria:** After a 3-turn test session, confirm all 3 turns have non-nil `embeddingID` in SwiftData.

#### [AI-SESSION-13] Session-level summary embedding
- **Size:** S
- **Description:** When `closeCurrentSession()` is called, embed a summary string (`"SESSION: \(title) TOOL: \(tool) TURNS: \(turnCount)"`) and store in `AISession.embeddingID`. This enables session-level semantic search distinct from individual turn search.
- **Acceptance criteria:** Unit test confirms `AISession.embeddingID` is set after close.

#### [AI-SESSION-14] Screenshot temporal matching and AITurn attachment
- **Size:** M
- **Description:** `ScreenshotWatcherService` is already running. When a new `ImageAsset` is detected, `AISessionService` checks whether an active session exists and whether any turn was captured within ±30 seconds of the screenshot timestamp. If yes, append the asset UUID to `AITurn.attachedImageIDs` and link the asset to `AISession.attachedImages`. The ±30 second window is configurable.
- **Acceptance criteria:** Integration test: mock a turn at T=0, add a screenshot at T=15s, confirm link is created. Add screenshot at T=45s, confirm no link.

#### [AI-SESSION-15] Backfill service: re-vectorize historical turns on app launch
- **Size:** S
- **Description:** On `AISessionService.initialize()`, fetch all `AITurn` records with nil `embeddingID` and call `VectorizationService.shared.ensureEmbedding(for:)` for each, with a concurrency limit of 4. Log progress to `StatusBarService`. Mirrors the existing `backfillMissingPromptEmbeddings` pattern.
- **Acceptance criteria:** Backfill completes without memory pressure on a 500-turn corpus.

---

### Milestone 4 — Context Explorer & UI

#### [AI-SESSION-16] Add "AI Sessions" section to Context Explorer sidebar
- **Size:** S
- **Description:** Add `aiSessions` case to the `ExplorerSection` enum in `ContextExplorerStore`. Add the sidebar row with a `bubble.left.and.bubble.right` SF Symbol. Wire to a new `AISessionListView`.
- **Acceptance criteria:** "AI Sessions" appears in the sidebar, clicking it shows the session list.

#### [AI-SESSION-17] Session list view
- **Size:** M
- **Description:** `AISessionListView` shows a sorted list of `AISession` records (newest first). Each row shows: title, tool icon, date, turn count, duration. Support search by session title. Support filter by tool (opencode / claude-desktop / cursor / continue).
- **Acceptance criteria:** List renders correctly with 0, 1, and 100 sessions. Search filters in real time.

#### [AI-SESSION-18] Session reader view (chronological Q&A)
- **Size:** L
- **Description:** `AISessionReaderView` shows all `AITurn` records for the selected session in turn-index order. User turns are shown with a distinct background. Assistant turns render with model ID and response duration. Screenshot thumbnails appear below the turn they are linked to. The view is scrollable and supports large turn counts via lazy loading.
- **Acceptance criteria:** Reader renders a 200-turn session without jank; thumbnails load asynchronously.

#### [AI-SESSION-19] Turn detail actions: copy, edit, add to prompt
- **Size:** S
- **Description:** Right-click context menu on any turn: "Copy Text", "Add to Prompt Editor" (appends turn content to the main `EditorViewModel`), "Mark as Private" (excludes from git export), "Edit Text" (opens inline text field, sets `AITurn.isEdited = true`).
- **Acceptance criteria:** "Add to Prompt Editor" correctly appends to the editor without clearing existing content.

#### [AI-SESSION-20] Search integration: AI turns in global semantic search
- **Size:** M
- **Description:** `ContextExplorerStore.semanticSearch` already queries the vector table. Extend the `searchContextItemIDs` method to also query `aisession:` prefixed embeddings and return matching `AITurn` UUIDs. Results are rendered in the search results list with a chip showing the session title and tool icon.
- **Acceptance criteria:** Searching "rate limiting express" returns the relevant AI turn from the test session.

---

### Milestone 5 — Git Export

#### [AI-SESSION-21] GitExportService: write transcript, meta, vectors, images
- **Size:** L
- **Description:** Full implementation of `GitExportService` as specified in `docs/plan-ai-session-git-export.md`. Includes `TranscriptRenderer`, `SessionMetadata`, `ImageConverter` (WebP), and `vectors.jsonl` writer. Does not perform git operations; those are in a separate helper.
- **Acceptance criteria:** Export a 10-turn session with 2 screenshots; verify file layout matches spec; verify `transcript.md` is valid Markdown; verify `vectors.jsonl` loads correctly.

#### [AI-SESSION-22] "Commit Session" UI in session detail view
- **Size:** M
- **Description:** Add a "Commit to Git" button to `AISessionReaderView`. Tapping it shows a pre-commit preview sheet: list of files, total byte count, sensitive-content warning if applicable. Confirm → calls `GitExportService.exportAndCommit(_:)`. Success shows a toast with the commit SHA. Failure shows an error sheet with the git error message.
- **Acceptance criteria:** Full UI flow tested manually against a local git repo.

#### [AI-SESSION-23] Auto-commit option (triggered on session close)
- **Size:** S
- **Description:** If `UserPreferences.autoCommitSessions == true` and `session.projectPath != nil` and the session has ≥ 1 turn, `AISessionService.closeCurrentSession()` fires `GitExportService.exportAndCommit(_:)` in a background task. Errors are surfaced via `StatusBarService` rather than interrupting the user.
- **Acceptance criteria:** Unit test confirms auto-commit is called (via mock) when the setting is enabled.

#### [AI-SESSION-24] Re-vectorization import: read vectors.jsonl from git repo
- **Size:** L
- **Description:** Implement `SessionImportService` as specified in `docs/plan-ai-session-git-export.md`. Includes: auto-scan for `vapor-sessions/` on project folder change, import sheet UI (list of found sessions with "Import & Vectorize" button), fast-path bulk insert from `vectors.jsonl`, slow-path re-embedding fallback, SwiftData record creation.
- **Acceptance criteria:** Import a 100-turn session from `vectors.jsonl` in under 2 seconds on M1 Mac. Import the same session without `vectors.jsonl`; confirm re-embedding completes in under 15 seconds.

---

### Milestone 6 — Settings, Onboarding & Polish

#### [AI-SESSION-25] Add AI Session Capture section to SettingsView
- **Size:** M
- **Description:** New section in `SettingsView` with all settings listed in `plan-ai-session-capture.md`. Persist in `UserPreferences` (extend the existing model). Include path pickers with folder-access scoped bookmarks for log paths.
- **Acceptance criteria:** All settings persist across app restarts; toggling "Enable AI Session Capture" starts/stops all watchers.

#### [AI-SESSION-26] Onboarding prompt for first enable
- **Size:** S
- **Description:** When the user enables AI Session Capture for the first time, show a sheet explaining what will be captured, what stays on-device, and asking for folder access to the log directory. Persist the scoped bookmark. Show a "Learn more" link to the plan doc in the app Help menu.
- **Acceptance criteria:** Onboarding sheet appears exactly once per user; subsequent launches go directly to capture.

#### [AI-SESSION-27] StatusBar log integration
- **Size:** S
- **Description:** Log the following events to `StatusBarService` with appropriate levels:
  - `session open` (info)
  - `turn captured` (verbose, rate-limited to 1 per second in UI)
  - `session close` (info, includes turn count and duration)
  - `vectorization queued` (verbose)
  - `git commit succeeded` (success, includes SHA)
  - `capture paused / resumed` (info)
- **Acceptance criteria:** Each event appears in the StatusBar log with correct domain and level.

#### [AI-SESSION-28] "Pause capture" toggle in menu bar
- **Size:** S
- **Description:** Add "⏸ Pause AI Capture" / "▶ Resume AI Capture" toggle to the Vapor menu bar icon context menu. When paused, all watchers suspend reads and the current session is flushed to SwiftData but not closed (turns captured while paused are discarded silently). A visual indicator (e.g., orange dot) on the menu bar icon signals the paused state.
- **Acceptance criteria:** Pause → send AI turns in the tool → resume → confirm no turns were added during pause.

---

## Dependency Graph

```
AI-SESSION-01 (models)
    ├── AI-SESSION-02 (vectorization namespace)
    ├── AI-SESSION-03 (AISessionService)
    │       ├── AI-SESSION-05 (OpenCode watcher)
    │       ├── AI-SESSION-06 (Claude Desktop watcher)
    │       ├── AI-SESSION-07 (Cursor client)
    │       ├── AI-SESSION-08 (Continue client)
    │       ├── AI-SESSION-10 (project detection)
    │       └── AI-SESSION-11 (idle timeout)
    └── AI-SESSION-04 (ContextItemKind)

AI-SESSION-02 + AI-SESSION-03
    ├── AI-SESSION-12 (auto-vectorize turns)
    ├── AI-SESSION-13 (session summary embedding)
    └── AI-SESSION-15 (backfill)

AI-SESSION-14 (screenshot interleaving)
    requires: AI-SESSION-03, ScreenshotWatcherService (existing)

AI-SESSION-16..20 (Context Explorer UI)
    requires: AI-SESSION-01..15

AI-SESSION-21..24 (Git Export)
    requires: AI-SESSION-01..03

AI-SESSION-25..28 (Settings & Polish)
    requires: AI-SESSION-03, AI-SESSION-21
```

---

## Suggested Labeling

| Label | Color | Applied to |
|---|---|---|
| `ai-session-capture` | Purple | All issues in this list |
| `data-model` | Blue | 01, 04 |
| `capture-backend` | Orange | 05–11 |
| `vectorization` | Teal | 02, 12, 13, 15 |
| `ui` | Green | 16–20, 22, 25–28 |
| `git-integration` | Yellow | 21–24 |
| `privacy` | Red | 09, 28 |
