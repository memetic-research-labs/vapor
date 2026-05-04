# specs-as-context Specification

## Purpose

Ingest OpenSpec specification files and change proposals into Vapor's context system so they are vectorized, searchable, and available to AI sessions, the CLI, and the HTTP API. This turns specs into living, queryable context that AI coding agents can discover via semantic search.

## ADDED Requirements

### Requirement: Watch openspec/ directory for changes

The system SHALL monitor the `openspec/specs/` and `openspec/changes/` directories using FSEvents. When a spec file (`.md`) is created, modified, or deleted, the system SHALL ingest or update the corresponding ContextItem.

#### Scenario: New spec file detected

- **WHEN** a new file `openspec/specs/project-anchoring/spec.md` is created
- **THEN** the system ingests the file as a ContextItem within 5 seconds

#### Scenario: Spec file updated

- **WHEN** an existing spec file is modified
- **THEN** the corresponding ContextItem's `textContent` and `markdownContent` are updated AND the embedding is regenerated

#### Scenario: Spec file deleted

- **WHEN** a spec file is deleted (e.g., archived via `openspec archive`)
- **THEN** the corresponding ContextItem's status is set to `.archived`

### Requirement: ContextItem kind for specs

The system SHALL store ingested specs as ContextItem records with `kind = .spec` (a new ContextKind value). The `sourceURL` SHALL be set to the file path as a `file://` URL. The `sourceTitle` SHALL be derived from the spec file name and parent directory (e.g., "project-anchoring/spec.md").

#### Scenario: Spec ingested with correct metadata

- **WHEN** `openspec/specs/session-capture/spec.md` is ingested
- **THEN** a ContextItem is created with `kind = .spec`, `sourceURL = "file:///path/to/openspec/specs/session-capture/spec.md"`, `sourceTitle = "session-capture/spec.md"`

### Requirement: Auto-assign specs to project

The system SHALL auto-assign ingested spec ContextItems to the project that owns the repo they live in. Since `openspec/` lives in the project root, specs SHALL inherit the project detected from the git repo root.

#### Scenario: Spec auto-assigned to project

- **WHEN** a spec is ingested from a repo at `/Users/dev/projects/vapor/openspec/specs/auth/spec.md`
- **AND** a VaporProject exists with `gitLocalPath = "/Users/dev/projects/vapor"`
- **THEN** the spec ContextItem is assigned to that project

### Requirement: Vectorize specs for semantic search

The system SHALL vectorize ingested specs using the existing `VectorizationService` with the `ctx:` namespace. The searchable text SHALL include the spec title, capability name, all requirement names, and the full requirement descriptions.

#### Scenario: Spec is vectorized

- **WHEN** a spec is ingested AND processed
- **THEN** `VectorizationService.ensureEmbedding(for:)` is called AND the ContextItem has a non-nil `embeddingID`

#### Scenario: Semantic search finds relevant spec

- **WHEN** a developer searches for "how does session capture detect the git repo"
- **THEN** the session-capture spec containing "auto-detect project from git working directory" appears in search results

### Requirement: Specs appear in Context Explorer

The system SHALL show spec ContextItems in the Context Explorer under a new "Specs" section in the types facet. Specs SHALL be filterable by project and searchable via semantic search.

#### Scenario: Specs listed in types facet

- **WHEN** user filters by type "spec" in the Context Explorer
- **THEN** all ingested spec ContextItems are shown

#### Scenario: Specs searchable across projects

- **WHEN** user performs a semantic search for "password expiration policy" across all projects
- **THEN** any spec containing related requirements (e.g., auth-session spec) appears in results regardless of project

### Requirement: Specs included in git export

The system SHALL include spec ContextItems in full-context project git exports. Specs SHALL be exported as markdown files preserving their original content.

#### Scenario: Specs in export

- **WHEN** a full project export is triggered
- **THEN** the export includes a `specs/` directory with all spec ContextItems as `.md` files, preserving the `openspec/specs/<capability>/spec.md` structure

### Requirement: Change proposals as context

The system SHALL also ingest OpenSpec change proposals (`openspec/changes/*/proposal.md`) as ContextItems with `kind = .spec` and a tag `change-proposal`. Change proposals SHALL include the change name, description, and capability list in their searchable text.

#### Scenario: Change proposal ingested

- **WHEN** `openspec/changes/ai-session-capture/proposal.md` is created
- **THEN** a ContextItem is created with `kind = .spec`, `tags` including "change-proposal" and "ai-session-capture", and `sourceTitle = "ai-session-capture/proposal.md"`

### Requirement: Specs queryable via HTTP API and CLI

The system SHALL return spec ContextItems through existing search endpoints. No new endpoints are needed -- specs are just ContextItems with a different kind.

#### Scenario: API search returns specs

- **WHEN** `POST /api/search/sessions` is called with `{"query": "session capture"}`
- **THEN** relevant spec ContextItems appear alongside session results

#### Scenario: CLI search returns specs

- **WHEN** `vapor search "project anchoring" --format json` is executed
- **THEN** the JSON output includes spec ContextItems matching the query
