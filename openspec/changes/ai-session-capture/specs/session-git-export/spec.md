# session-git-export Specification

## Purpose

Export full AI session context (transcript, entities, vectors, images, media, URLs) to a git repository with branch-aligned directory structure and support for re-import.

## ADDED Requirements

### Requirement: Date-based session storage

The system SHALL export sessions to `.vapor-context/sessions/<YYYY-MM-DD>/<session-uuid>/` containing:
- `transcript.md` -- human-readable Q&A with timestamps
- `meta.json` -- session metadata (tool, model, branch, PR, tags, summary, entity counts, redaction info, vapor version, embedding model)
- `entities.json` -- all entities with kind, displayText, confidence, occurrences, linked turns
- `vectors.jsonl` -- one JSON object per AITurn with turnID, role, turnIndex, capturedAt, and embedding (384 float32 values)
- `images/` -- screenshots as WebP (0.85 quality), named by timestamp (`HH-mm-ss.webp`)
- `media/` -- PDFs, video clips, animated GIFs stored as-is with hash-based filenames
- `urls/references.jsonl` -- one JSON object per URL with url, domain, firstSeenAt, turnID, title

#### Scenario: Export 10-turn session with 2 screenshots

- **WHEN** a session with 10 turns and 2 screenshots is exported
- **THEN** the `.vapor-context/sessions/2025-05-01/<uuid>/` directory is created with all 7 items (transcript.md, meta.json, entities.json, vectors.jsonl, images/, media/, urls/)

#### Scenario: WebP conversion of screenshots

- **WHEN** a screenshot PNG is exported
- **THEN** it is converted to WebP at 0.85 quality AND stored in `images/` with filename `HH-mm-ss.webp`

### Requirement: Branch-aligned symlinks

The system SHALL create symlinks from `.vapor-context/by-branch/<branch>/<session-uuid>` pointing to the date-based session directory. This allows browsing sessions by branch.

Additionally, a `.vapor-context/branches/<branch>/sessions.jsonl` index file SHALL be maintained listing all sessions for each branch.

#### Scenario: Symlink created for branch

- **WHEN** a session on branch "feature/auth-refactor" is exported
- **THEN** a symlink is created at `.vapor-context/by-branch/feature/auth-refactor/<uuid>` pointing to `../../sessions/2025-05-02/<uuid>/`

#### Scenario: Branch index updated

- **WHEN** a session is exported on branch "feature/auth-refactor"
- **THEN** an entry is appended to `.vapor-context/branches/feature/auth-refactor/sessions.jsonl` with sessionId, date, title, and turnCount

### Requirement: Atomic git commit per session

The system SHALL create one git commit per session export with message format: `vapor: add AI session [<tool>] <title> (<turnCount> turns)`. The branch index SHALL be updated in a separate commit.

#### Scenario: Single session commit

- **WHEN** a session "Rate limiting" from opencode with 47 turns is exported
- **THEN** a git commit is created with message "vapor: add AI session [opencode] Rate limiting (47 turns)"

### Requirement: Full-context project export

The system SHALL support exporting ALL context for a project (not just AI sessions):
- All `ContextItem` records -> exported as markdown references
- All `PromptRecord` records -> exported as `prompts.md`
- All `ImageAsset` records -> exported as WebP
- All `AISession` records -> exported as individual session directories
- All entity links -> exported per session in `entities.json`
- All URLs -> exported in `urls/references.jsonl`

#### Scenario: Export all project context

- **WHEN** user triggers full export for project "Vapor App"
- **THEN** the export includes all ContextItems, PromptRecords, ImageAssets, and AISessions belonging to that project

### Requirement: Re-import from git repo

The system SHALL support importing sessions from a `.vapor-context/` directory:
1. Scan for unimported session directories
2. Read `meta.json` and validate `embeddingDimensions` matches local MiniLM (384)
3. Fast path: read `vectors.jsonl` and bulk insert into local SQLite-vec (~1s per 100 turns)
4. Slow path: re-embed from `transcript.md` turn-by-turn (~10s per 100 turns)
5. Create AISession, AITurn, entity links, and tags from exported files

#### Scenario: Fast-path import

- **WHEN** a session with `vectors.jsonl` and matching `embeddingDimensions = 384` is imported
- **THEN** vectors are bulk-inserted directly AND no embedding inference is performed

#### Scenario: Slow-path import

- **WHEN** a session with `embeddingDimensions = 512` (mismatch) is imported
- **THEN** each turn is re-embedded using local MiniLM AND `embeddingDimensions` in meta.json is updated to 384

#### Scenario: Import missing session detection

- **WHEN** Vapor scans `.vapor-context/` and finds a session directory whose ID does not exist in local SwiftData
- **THEN** that session is offered for import

### Requirement: .gitattributes for binary files

The system SHALL create or update `.gitattributes` to mark exported binary files:

```
.vapor-context/sessions/**/*.webp binary
.vapor-context/sessions/**/*.pdf binary
.vapor-context/sessions/**/*.mp4 binary
.vapor-context/sessions/**/*.gif binary
.vapor-context/by-branch/** symlink
```

#### Scenario: gitattributes created on first export

- **WHEN** the first session with screenshots is exported AND no `.gitattributes` exists
- **THEN** `.gitattributes` is created with the binary and symlink rules

### Requirement: AIGitExportRecord model

The system SHALL maintain an `AIGitExportRecord` SwiftData model tracking each export:
- `id` (UUID), `session: AISession?`, `exportedAt` (Date)
- `gitCommitSHA` (String), `branchName` (String), `sessionDirPath` (String)
- `filesIncluded: [String]`, `totalBytes` (Int)
- `redactionCount` (Int), `redactedTurnIDs: [String]`

#### Scenario: Export record created

- **WHEN** a session is exported and committed
- **THEN** an AIGitExportRecord is created with the commit SHA, list of files, and byte count
