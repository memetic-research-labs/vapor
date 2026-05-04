# session-cli Specification

## Purpose

Provide a standalone CLI tool (`vapor-cli`) for terminal-based access to Vapor's session context, semantic search, entity queries, and git export operations.

## ADDED Requirements

### Requirement: Separate SwiftPM package

The system SHALL provide `vapor-cli` as a separate SwiftPM package that reads Vapor's existing databases directly without requiring the full Vapor app to be running. The package SHALL be at a sibling path to the vapor repo (e.g., `../vapor-cli/`).

#### Scenario: CLI runs without Vapor app

- **WHEN** `vapor-cli status` is executed and the Vapor app is not running
- **THEN** the CLI reads from `~/Library/Application Support/Vapor/default.store` and `vectors.db` and returns database statistics

### Requirement: Search command

The CLI SHALL provide a `search` command that performs semantic + faceted search:
- `vapor search "<query>" --project <id> --tool opencode --limit 10`
- `vapor search --entity-kind decision --branch feature/auth`
- `vapor search --tag bug-fix --date-from 2025-04-01`

When the MiniLM CoreML model is bundled, semantic search SHALL work offline. When the model is not available, the CLI SHALL fall back to keyword-only search.

#### Scenario: Semantic search from CLI

- **WHEN** `vapor search "rate limiting express" --project <uuid> --limit 5` is executed
- **THEN** the CLI generates an embedding for the query, performs KNN search against vectors.db, and outputs matching turns in human-readable format

#### Scenario: Keyword fallback

- **WHEN** `vapor search "express"` is executed AND the MiniLM model is not bundled
- **THEN** the CLI performs keyword search across turn content using SQLite LIKE queries

### Requirement: Sessions command

The CLI SHALL provide a `sessions` command:
- `vapor sessions list --project <id> --limit 20`
- `vapor sessions show <session-id> --format markdown`
- `vapor sessions export <session-id> --preview` -- preview only, no git commit
- `vapor sessions export <session-id> --commit` -- full export + git commit

#### Scenario: List sessions

- **WHEN** `vapor sessions list --project <uuid> --limit 10` is executed
- **THEN** the CLI outputs a table with session title, tool, date, turn count, and duration

#### Scenario: Show session as markdown

- **WHEN** `vapor sessions show <uuid> --format markdown` is executed
- **THEN** the CLI outputs the full session transcript in markdown format with timestamps, roles, and model IDs

#### Scenario: Export session

- **WHEN** `vapor sessions export <uuid> --commit` is executed AND the session has a project with gitLocalPath
- **THEN** the CLI exports to `.vapor-context/` and creates a git commit, outputting the commit SHA

### Requirement: Entities command

The CLI SHALL provide an `entities` command:
- `vapor entities search "express" --kind library`
- `vapor entities graph --project <id> --kind concept`

#### Scenario: Search entities by kind

- **WHEN** `vapor entities search "express" --kind library` is executed
- **THEN** the CLI outputs matching entities with kind "library", showing displayText, confidence, and occurrence count

### Requirement: Projects command

The CLI SHALL provide a `projects` command:
- `vapor projects list`
- `vapor projects create "My API" --git-path ~/projects/my-api`
- `vapor projects show <project-id>`
- `vapor projects context <project-id> --limit 20`

#### Scenario: List projects

- **WHEN** `vapor projects list` is executed
- **THEN** the CLI outputs a table with project name, git remote, branch, and context item count

### Requirement: Import command

The CLI SHALL provide an `import` command:
- `vapor sessions import --path ~/projects/my-api`

This SHALL scan the `.vapor-context/` directory in the given path for unimported sessions and offer to import them with fast-path from `vectors.jsonl` or slow-path re-embedding.

#### Scenario: Import from git repo

- **WHEN** `vapor sessions import --path ~/projects/my-api` is executed AND the repo contains `.vapor-context/sessions/` with 3 sessions
- **THEN** the CLI lists the 3 sessions and imports them, creating AISession and AITurn records

### Requirement: Status command

The CLI SHALL provide a `status` command that outputs:
- Total sessions, turns, entities, projects
- Vector database size and embedding count
- Capture adapter status (if Vapor app is running and API is reachable)

#### Scenario: Database stats

- **WHEN** `vapor status` is executed
- **THEN** the CLI outputs counts for sessions, turns, entities, projects, and vector database stats

### Requirement: Output format options

The CLI SHALL support both human-readable (terminal table) and JSON output formats via a `--format json` flag on all commands.

#### Scenario: JSON output

- **WHEN** `vapor sessions list --format json` is executed
- **THEN** the CLI outputs a JSON array of session objects
