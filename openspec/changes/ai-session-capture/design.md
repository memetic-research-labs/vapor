## Context

Vapor is a macOS AI research assistant that captures browser context, screenshots, and prompts. It stores context in SwiftData with MiniLM-based vector embeddings for semantic search. All context currently lives in a single global pool with no project scoping.

The existing infrastructure includes:
- SwiftData models: `ContextItem`, `EntityRecord`, `ImageAsset`, `PromptRecord`, `URLRecord` with join tables
- `VectorizationService` with `ctx:` and `prompt:` embedding namespaces in a shared SQLite-vec table
- `EntityExtractionService` with OpenRouter (cloud LLM) and `NLTagger` (on-device) backends
- `TaggerService` for auto-tagging, `SummarizationService` for LLM summaries
- `VaporEmbeddedServer` on port 8766 with SSE and basic REST endpoints
- `ContextExplorerView` with faceted filtering (domains, entities, tags, types, URLs)

No git integration exists. No project concept exists. No AI session capture exists.

## Goals / Non-Goals

**Goals:**
- Anchor all context to projects (git repos, remote URLs, or custom names) with auto-detection
- Capture AI coding sessions from OpenCode (primary) with adapter protocol for future tools
- Extract entities from session turns, including architectural decisions
- Provide programmatic access via REST API (existing server) and standalone CLI (new SwiftPM package)
- Export full context to git with secrets redaction, branch-aligned structure, and re-import support
- Ingest OpenSpec files as searchable context items

**Non-Goals:**
- Real-time collaboration or multi-user project sharing
- Cloud sync or remote vector database
- Running Vapor on iOS/iPadOS
- Supporting more than 3 AI tool adapters in Phase 1 (OpenCode, manual paste, clipboard heuristic)
- Modifying the browser extension (project assignment is server-side)
- Building a full knowledge graph database (entity co-occurrence is sufficient for Phase 1)

## Decisions

### D1: Single project FK (not multi-project join table)

Context items belong to exactly one project (or nil for Unassigned). This is simpler to query, filter, and export. Multi-project association adds query complexity for minimal benefit -- developers typically think of "this is my vapor project context."

**Alternative considered:** Primary project FK + secondary join table for "also relevant." Rejected -- adds join complexity, unclear when to use primary vs secondary, and most context is clearly scoped to one project.

### D2: Facade/adapter pattern for capture

A `SessionCaptureFacade` manages multiple `SessionCaptureAdapter` instances. Each adapter handles one AI tool. The facade provides a single `isCapturing` state and unified `onTurnCaptured` callback.

**Alternative considered:** Direct integration per tool with if/else branching. Rejected -- violates open/closed principle, makes adding new tools messy.

### D3: Extend existing server (not separate service)

All new endpoints go on the existing port 8766 server. Same auth, same CORS, same process. This avoids operational complexity of managing two servers.

**Alternative considered:** Separate service on port 8767. Rejected -- requires separate auth, CORS, process management, and adds deployment complexity for no real benefit.

### D4: SQLite-vec metadata table (not a new vector DB)

Add an `aisession_meta` table alongside the existing `vec_items` table for faceted filtering via SQL JOIN. SQLite-vec is already embedded and working.

**Alternative considered:** LanceDB or Qdrant for richer faceted search. Rejected -- adds a new dependency, a new binary, and operational complexity. SQL JOINs on a metadata table are sufficient for the filtering we need.

### D5: Regex + LLM hybrid redaction

Phase 1 runs regex patterns (fast, deterministic), Phase 2 sends content to local LLM for contextual secrets, Phase 3 applies user denylist. This catches both structured secrets (API key patterns) and contextual leaks ("my password is...").

**Alternative considered:** Regex only. Rejected -- misses secrets embedded in natural language. LLM-only rejected -- misses structured patterns like base64 tokens.

### D6: Separate vapor-cli SwiftPM package

The CLI is a standalone package that reads Vapor's databases directly. This allows using the CLI without the Vapor app running and makes the CLI independently versionable and installable.

**Alternative considered:** CLI built into the Vapor app bundle. Rejected -- couples CLI releases to app releases, requires the full app for a simple search query.

### D7: Branch-aligned symlinks to date-based storage

Actual files live under `.vapor-context/sessions/<date>/<uuid>/`. Symlinks at `.vapor-context/by-branch/<branch>/<uuid>` provide branch-based navigation. The index file at `.vapor-context/branches/<branch>/sessions.jsonl` enables fast listing.

**Alternative considered:** Storing files directly under branch directories. Rejected -- a session might span branches (branch switches mid-session), and date-based storage is simpler for deduplication.

### D8: Specs as context items

OpenSpec files are ingested as ContextItems with `kind = .spec`, vectorized, and searchable. This turns specs into living context that AI sessions can discover.

**Alternative considered:** Separate spec search index. Rejected -- unnecessary complexity when the existing vector search infrastructure already handles this perfectly.

## Risks / Trade-offs

**[Risk: OpenCode JSONL format instability]** → Add a version check on the log file, graceful fallback on parse failure, and log warnings to StatusBarService. The adapter SHALL treat unknown fields as non-fatal.

**[Risk: FSEvents reliability for log watching]** → FSEventStream is reliable for file appends but can miss events under extreme load. Add a periodic fallback poll (every 30 seconds) to catch any missed events.

**[Risk: Large session performance (>1000 turns)]** → Lazy loading in reader view, chunked vectorization with concurrency limit of 4, and paginated API endpoints with cursor-based pagination.

**[Risk: Secrets redaction false positives]** → Pre-commit preview shows all redactions for user review. Users can skip specific redactions. The "sensitive content warning" dialog uses keyword matching as a lower-confidence signal separate from actual redactions.

**[Risk: SQLite-vec metadata table bloat]** → Periodic cleanup of orphaned rows (meta entries without matching embedding entries) on app launch. Prune entries older than 90 days for archived/deleted sessions.

**[Risk: vapor-cli SwiftData model sync]** → The CLI reads raw SQLite/SwiftData without the Swift model layer. Model definitions in vapor-cli-core MUST be kept in sync with the Vapor app. Consider generating model definitions from a shared source or versioning the schema.

**[Risk: Git export file size]** → WebP conversion at 0.85 quality, optional media exclusion toggle, and vector embeddings in JSON (slightly larger than binary but universally parseable). Target: <5MB for a 100-turn session with 10 screenshots.
