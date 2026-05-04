## 1. Project Anchoring Foundation

- [ ] 1.1 Add `ContextKind.spec` enum case to ContextItem
- [ ] 1.2 Create `VaporProject` SwiftData model with all fields (id, name, notes, gitLocalPath, gitRemoteURL, gitCurrentBranch, detectedPRNumber, colorHex, sortOrder, createdAt, lastActiveAt) and relationships to ContextItem, PromptRecord, ImageAsset, AISession
- [ ] 1.3 Create `VaporProjectBookmark` SwiftData model with bookmarkData for security-scoped folder access
- [ ] 1.4 Create VaporSchemaV2 migration registering VaporProject, VaporProjectBookmark, and adding optional project FK to ContextItem, PromptRecord, ImageAsset
- [ ] 1.5 Implement `ProjectService` singleton (@MainActor @Observable) with createProject, detectProject(from gitPath:), detectProject(from browserURL:), assign methods, refreshGitState
- [ ] 1.6 Implement git detection helpers: git rev-parse --show-toplevel, git remote get-url origin, git rev-parse --abbrev-ref HEAD, branch name PR number parsing
- [ ] 1.7 Implement browser URL project detection: GitHub/GitLab/Bitbucket pattern matching, remote URL normalization
- [ ] 1.8 Implement security-scoped bookmark save/restore for gitLocalPaths
- [ ] 1.9 Add project picker UI to Context Explorer sidebar (list projects with counts, Unassigned, New Project action)
- [ ] 1.10 Wire project picker to ContextExplorerStore: filter all facets by selected project, filter semantic search by project

## 2. AI Session Data Models

- [ ] 2.1 Create `AISession` SwiftData model with all fields (id, title, tool, projectPath, projectName, branchName, prNumber, startedAt, endedAt, tags, isArchived, gitCommitSHA, embeddingID, summaryAbstract, summaryKeyPoints, totalTokensEstimated, totalTurns, totalAttachedImages, totalAttachedURLs, project FK)
- [ ] 2.2 Create `AITurn` SwiftData model with all fields (id, session FK, role, turnIndex, content, contentTokenCount, capturedAt, embeddingID, modelID, toolName, attachedImageIDs, attachedURLs, durationSeconds, isEdited, isRedacted)
- [ ] 2.3 Create `AISessionEntityLink` SwiftData model (id, confidence, surfaceText, createdAt, session FK, entityRecord FK)
- [ ] 2.4 Create `AITurnEntityLink` SwiftData model (id, confidence, surfaceText, createdAt, turn FK, entityRecord FK)
- [ ] 2.5 Create `AISessionTag` SwiftData model (id, text, sourceRaw, confidence, createdAt, session FK)
- [ ] 2.6 Create `AIGitExportRecord` SwiftData model (id, session FK, exportedAt, gitCommitSHA, branchName, sessionDirPath, filesIncluded, totalBytes, redactionCount, redactedTurnIDs)
- [ ] 2.7 Expand `EntityKind` enum with: model, tool, library, api, file, error, decision
- [ ] 2.8 Register all new models in VaporSchemaV2 migration

## 3. Session Capture Facade + OpenCode Adapter

- [ ] 3.1 Define `SessionCaptureAdapter` protocol (toolName, isAvailable, startCapture, stopCapture, onTurnCaptured callback)
- [ ] 3.2 Define `CapturedTurn` struct (role, content, capturedAt, modelID, toolName, durationSeconds)
- [ ] 3.3 Implement `SessionCaptureFacade` (@MainActor @Observable) with registerAdapter, startAll, stopAll, stopAdapter, isCapturing
- [ ] 3.4 Implement `AISessionService` singleton: open session on first turn, close on idle timeout/adapter stop/manual, generate summary on close
- [ ] 3.5 Implement `OpenCodeAdapter`: log path resolution (config.json, XDG_DATA_HOME, defaults), FSEventStream file watcher, JSONL line parser
- [ ] 3.6 Implement OpenCode JSONL parsing: extract role, content, timestamp, model from each line; skip malformed lines; log errors to StatusBar
- [ ] 3.7 Wire OpenCodeAdapter to ProjectService.detectProject(from gitPath:) for auto project assignment
- [ ] 3.8 Implement idle timeout (configurable, default 30 min) with timer-based session close
- [ ] 3.9 Add "Pause capture" toggle to menu bar (discard turns while paused, orange dot indicator)
- [ ] 3.10 Implement ManualPasteAdapter: Cmd+Opt+V or toolbar button, auto-segment pasted Q&A text into turns

## 4. Entity Extraction + Tagging for Sessions

- [ ] 4.1 Implement per-turn entity extraction: call EntityExtractionService.extract() for each AITurn, create/find EntityRecord, create AITurnEntityLink
- [ ] 4.2 Implement session-level entity aggregation on close: collect unique entities from all turns, create AISessionEntityLink records
- [ ] 4.3 Implement decision extraction LLM prompt: analyze session turns, extract architectural decisions as JSON, store as EntityRecords with kind .decision
- [ ] 4.4 Implement per-turn auto-tagging: adapt TaggerService for AITurn content (keywords + entity names + role tags)
- [ ] 4.5 Implement session-level tag aggregation: collect and deduplicate turn tags into AISession.tags
- [ ] 4.6 Implement LLM-generated session tags on close: 3-5 high-level tags from session summary

## 5. Vectorization for Sessions

- [ ] 5.1 Add `aisession:` embedding namespace to VectorizationService (alongside existing `ctx:` and `prompt:`)
- [ ] 5.2 Implement `VectorizationService.ensureEmbedding(for turn: AITurn)` with searchable text composite (role + content + session title + tool + model)
- [ ] 5.3 Implement `VectorizationService.ensureEmbedding(for session: AISession)` for session summary embedding
- [ ] 5.4 Create `aisession_meta` SQLite table in vectors.db (embedding_id, turn_id, session_id, project_id, role, tool, branch, model_id, captured_at, tags, entity_kinds)
- [ ] 5.5 Implement auto-vectorize on turn capture (async, non-blocking, after entity extraction)
- [ ] 5.6 Implement backfill service: re-vectorize historical turns with nil embeddingID on app launch, concurrency limit 4
- [ ] 5.7 Extend semantic search to query aisession_meta JOIN for faceted filtering (project, tool, branch, role, model, date range)

## 6. Screenshot Interleaving

- [ ] 6.1 Implement temporal matching: when ImageAsset is captured and a live session exists, check for AITurn within configurable window (default 30s)
- [ ] 6.2 Link matching screenshots to AITurn via attachedImageIDs
- [ ] 6.3 Configure time window in Settings

## 7. HTTP API Endpoints

- [ ] 7.1 Implement `GET /api/sessions` with query params (tool, project, branch, limit, offset)
- [ ] 7.2 Implement `GET /api/sessions/:id` (full session with turns, entities, tags, images)
- [ ] 7.3 Implement `GET /api/sessions/:id/turns` (paginated, filterable by role)
- [ ] 7.4 Implement `GET /api/sessions/:id/summary`, `GET /api/sessions/:id/entities`, `GET /api/sessions/:id/tags`
- [ ] 7.5 Implement `DELETE /api/sessions/:id` (archive)
- [ ] 7.6 Implement `POST /api/search/sessions` and `POST /api/search/turns` (semantic + faceted with filters object)
- [ ] 7.7 Implement `GET /api/search/entities` and `GET /api/search/tags`
- [ ] 7.8 Implement `GET /api/entities/:id`, `GET /api/entities/:id/related`, `GET /api/entities/graph`
- [ ] 7.9 Implement `GET /api/projects`, `POST /api/projects`, `GET /api/projects/:id`, `PUT /api/projects/:id`
- [ ] 7.10 Implement `GET /api/projects/:id/context`, `GET /api/projects/:id/sessions`, `GET /api/projects/:id/entities`
- [ ] 7.11 Implement `POST /api/sessions/:id/export` (preview) and `POST /api/sessions/:id/export/commit` (full export)
- [ ] 7.12 Implement `GET /api/export/config` and `PUT /api/export/config`

## 8. CLI Package (vapor-cli)

- [ ] 8.1 Scaffold vapor-cli SwiftPM package (Package.swift, main.swift, argument parser setup)
- [ ] 8.2 Implement VaporDatabase service (read SQLite + SwiftData directly from ~/Library/Application Support/Vapor/)
- [ ] 8.3 Implement EmbeddingSearch service (optional bundled MiniLM CoreML model, keyword fallback)
- [ ] 8.4 Implement `search` command (semantic + faceted, --project, --tool, --entity-kind, --tag, --date-from, --format json)
- [ ] 8.5 Implement `sessions` command (list, show --format markdown, export --preview/--commit)
- [ ] 8.6 Implement `entities` command (search, graph)
- [ ] 8.7 Implement `projects` command (list, create, show, context)
- [ ] 8.8 Implement `import` command (scan .vapor-context/, fast-path from vectors.jsonl, slow-path re-embed)
- [ ] 8.9 Implement `status` command (DB stats, vector count, capture status)
- [ ] 8.10 Implement JSON and terminal table output formatters for all commands

## 9. Git Export + Redaction

- [ ] 9.1 Implement TranscriptRenderer: AITurn[] -> markdown with timestamps, roles, model IDs, image references
- [ ] 9.2 Implement SessionMetadata serializer: AISession -> meta.json (all fields including summary, entities, redaction info)
- [ ] 9.3 Implement entities.json serializer: session entity links -> JSON with occurrences and linked turns
- [ ] 9.4 Implement vectors.jsonl writer: read embeddings from SQLite-vec, write one JSON object per turn
- [ ] 9.5 Implement ImageConverter: original image -> WebP (0.85 quality) using NSBitmapImageRep
- [ ] 9.6 Implement media export: PDFs, video clips, GIFs as-is with hash-based filenames
- [ ] 9.7 Implement urls/references.jsonl writer: URLRecord + turn association -> JSONL
- [ ] 9.8 Implement .gitattributes management (binary rules for webp/pdf/mp4/gif, symlink rule)
- [ ] 9.9 Implement GitExportService: prepareSessionDirectory, write all files, git add, git commit
- [ ] 9.10 Implement branch-aligned symlinks: create/update .vapor-context/by-branch/<branch>/<uuid> -> ../../sessions/...
- [ ] 9.11 Implement branches/<branch>/sessions.jsonl index management
- [ ] 9.12 Implement full-context project export: collect all ContextItems, PromptRecords, ImageAssets, AISessions for a project
- [ ] 9.13 Implement regex secret detection patterns (API keys, generic secrets, sensitive paths, private URLs)
- [ ] 9.14 Implement LLM-based contextual secret detection (Phase 2): prompt, parse JSON response, flag redactions
- [ ] 9.15 Implement user-configurable denylist (Settings: exportDenylistPatterns, Phase 3)
- [ ] 9.16 Implement redaction output: replace matched text with [REDACTED: reason]
- [ ] 9.17 Implement pre-commit preview UI: file list, byte count, redaction summary, approve/skip/cancel
- [ ] 9.18 Implement sensitive content warning dialog (keyword detection: password, secret, token, key, credential)
- [ ] 9.19 Implement re-import flow: scan .vapor-context/, validate embedding dimensions, fast-path bulk insert, slow-path re-embed

## 10. Specs as Context

- [ ] 10.1 Implement FSEvents watcher on openspec/specs/ and openspec/changes/ directories
- [ ] 10.2 Implement spec ingestion: read .md files, create ContextItem with kind=.spec, file:// sourceURL, project auto-assignment
- [ ] 10.3 Implement change proposal ingestion: parse proposal.md, create ContextItem with tags "change-proposal" and change name
- [ ] 10.4 Vectorize ingested specs via existing VectorizationService
- [ ] 10.5 Add "Specs" to Context Explorer types facet
- [ ] 10.6 Include spec ContextItems in full-context project git exports

## 11. Context Explorer UI

- [ ] 11.1 Add "AI Sessions" section to Context Explorer sidebar
- [ ] 11.2 Implement SessionListView: sorted list with title, tool, date, turn count, duration, project badge
- [ ] 11.3 Implement SessionReaderView: chronological Q&A with role badges, model IDs, timestamps, entity highlights
- [ ] 11.4 Implement screenshot thumbnails in reader view (async loading, linked to turns)
- [ ] 11.5 Implement turn detail actions: copy text, add to prompt editor, mark as private (isRedacted), edit text
- [ ] 11.6 Integrate AI session turns into global semantic search results (with session title chip)

## 12. Settings + Onboarding

- [ ] 12.1 Add AI Session Capture section to SettingsView (enable toggle, OpenCode log path, idle timeout, screenshot window, auto-commit)
- [ ] 12.2 Add project management section to Settings (list projects, create, edit, delete)
- [ ] 12.3 Add export/redaction settings (denylist editor, regex toggle, LLM redaction toggle, media inclusion toggle)
- [ ] 12.4 Add onboarding prompt for first enable (explain capture, request folder access, persist scoped bookmark)
- [ ] 12.5 Add StatusBar log integration (session open/close/turn-captured/vectorization/git commit events)
