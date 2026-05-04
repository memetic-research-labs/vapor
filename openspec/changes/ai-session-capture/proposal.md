## Why

Vapor captures browser context, screenshots, and prompts but has no concept of a "project" -- all data lives in a single global pool. Developers lose the full context of AI-assisted work sessions the moment they close their AI tool. There is no way to search past sessions, scope context to a git repo or PR, export a complete session (including images, URLs, entities) to git history, or access session context programmatically via HTTP API or CLI.

## What Changes

- Add a `VaporProject` model that anchors all context (ContextItems, PromptRecords, ImageAssets, AISessions) to git repos, GitHub/GitLab URLs, or custom named workspaces
- Add auto-detection of projects from AI session working directories and browser URLs
- Capture AI coding sessions (OpenCode-first, with adapter interface for Claude Desktop, Cursor, Continue.dev) with full Q&A transcript, screenshot interleaving, and per-turn entity extraction
- Extract entities from session turns (reusing existing `EntityRecord` infrastructure) with expanded `EntityKind` values for decisions, libraries, APIs, models, and tools
- Extend the existing embedded HTTP server (port 8766) with session CRUD, faceted semantic search, entity graph, and export endpoints
- Create a separate `vapor-cli` SwiftPM package for terminal-based access to sessions, search, entities, and git export
- Export full session context to git (transcript, entities, vectors, images, media, URLs) with regex + LLM hybrid secrets redaction, branch-aligned via symlinks to date-based storage

## Capabilities

### New Capabilities

- `project-anchoring`: VaporProject model, auto-detection from git CWD and browser URLs, project-scoped Context Explorer, security-scoped bookmarks
- `session-capture`: SessionCaptureFacade with adapter protocol, OpenCodeAdapter (FSEvents + JSONL parser), session lifecycle management
- `session-entity-extraction`: Per-turn entity extraction pipeline, session-level entity aggregation, expanded EntityKind (decision, library, api, model, tool, file, error)
- `session-http-api`: Session CRUD, faceted semantic search, entity graph, project, and export REST endpoints on existing 8766 server
- `session-cli`: Separate `vapor-cli` SwiftPM package with search, sessions, entities, projects, export, import, and status commands
- `session-git-export`: Full-context git export (all context types per project), branch-aligned symlinks, re-import with fast-path from vectors.jsonl
- `session-redaction`: Regex + LLM hybrid secrets redaction engine, user-configurable denylist, pre-commit preview with redaction summary
- `specs-as-context`: OpenSpec specs and change proposals are ingested as Vapor context items, vectorized, and searchable -- so AI sessions working on a feature can discover relevant specs via semantic search and the CLI/HTTP API

### Modified Capabilities

None -- no existing specs yet.

## Impact

- **SwiftData schema**: New VaporSchemaV2 migration adding VaporProject, AISession, AITurn, join models, and optional project FK on ContextItem, PromptRecord, ImageAsset
- **Existing models**: ContextItem, PromptRecord, ImageAsset gain optional `project: VaporProject?` FK
- **EntityKind enum**: Expanded from 9 to 16 values (adding model, tool, library, api, file, error, decision)
- **VaporEmbeddedServer**: New REST endpoints (~20) on existing port 8766
- **SQLite-vec**: New `aisession_meta` table for faceted vector search
- **VectorizationService**: New `aisession:` embedding namespace and per-turn embedding method
- **EntityExtractionService**: Reused for session turn extraction; no API changes
- **Context Explorer UI**: New project picker sidebar, AI Sessions section, entity graph visualization
- **Settings**: New AI Session Capture section, project management, export/redaction configuration
- **Browser extension**: No changes required (project assignment is server-side based on URL heuristics)
- **New repo**: `vapor-cli` as a separate SwiftPM package
- **Dependencies**: No new external dependencies; reuses MiniLM, SwiftLlama, SwiftNIO
- **Specs as context**: OpenSpec files in `openspec/specs/` and `openspec/changes/*/` are watched for changes and ingested into Vapor's context system as `ContextItem` records with `kind = .spec`, auto-assigned to the project, vectorized for semantic search, and included in git exports
