# session-http-api Specification

## Purpose

Provide programmatic access to AI sessions, search, entities, projects, and export via REST endpoints on the existing VaporEmbeddedServer (port 8766).

## ADDED Requirements

### Requirement: Session CRUD endpoints

The system SHALL expose the following endpoints on the existing embedded server:

- `GET /api/sessions` -- list sessions with query params: `tool`, `project`, `branch`, `limit`, `offset`
- `GET /api/sessions/:id` -- full session with turns, entities, tags, images
- `GET /api/sessions/:id/turns` -- paginated turns with query params: `limit`, `offset`, `role`
- `GET /api/sessions/:id/summary` -- session summary (abstract + key points)
- `GET /api/sessions/:id/entities` -- all entities linked to session
- `GET /api/sessions/:id/tags` -- all tags
- `DELETE /api/sessions/:id` -- archive session

All endpoints SHALL use the existing auth mechanism (bearer token / query param) and CORS configuration.

#### Scenario: List sessions filtered by project

- **WHEN** `GET /api/sessions?project=vapor-app&limit=10` is called
- **THEN** the response returns up to 10 AISession records belonging to the "vapor-app" project as JSON

#### Scenario: Get session with full details

- **WHEN** `GET /api/sessions/<uuid>` is called
- **THEN** the response returns the session with all turns, entity links, tags, and attached image IDs as JSON

### Requirement: Faceted semantic search endpoints

The system SHALL expose search endpoints:

- `POST /api/search/sessions` -- semantic search across sessions with body: `{query, limit, filters}`
- `POST /api/search/turns` -- semantic search across individual turns with body: `{query, limit, filters}`
- `GET /api/search/entities` -- entity search with query params: `kind`, `text`, `limit`
- `GET /api/search/tags` -- tag search with query params: `text`, `limit`

The `filters` object SHALL support: `projectId`, `tool`, `branch`, `entityKind`, `entityText`, `tags`, `dateFrom`, `dateTo`, `modelID`, `minTurns`.

#### Scenario: Semantic search with project filter

- **WHEN** `POST /api/search/turns` is called with `{"query": "rate limiting", "filters": {"projectId": "<uuid>"}}`
- **THEN** the response returns matching turns from only that project, ranked by vector distance

#### Scenario: Search by entity kind

- **WHEN** `POST /api/search/sessions` is called with `{"query": "", "filters": {"entityKind": "decision"}}`
- **THEN** the response returns sessions that contain entities of kind "decision"

### Requirement: Entity graph endpoints

The system SHALL expose entity graph endpoints:

- `GET /api/entities/:id` -- entity detail with all linked sessions and turns
- `GET /api/entities/:id/related` -- related entities (co-occurring in same sessions)
- `GET /api/entities/graph` -- adjacency list for entity graph visualization with query params: `kind`, `project`

#### Scenario: Get entity with linked sessions

- **WHEN** `GET /api/entities/<uuid>` is called
- **THEN** the response returns the entity record plus all sessions and turns it is linked to

#### Scenario: Get related entities

- **WHEN** `GET /api/entities/<uuid>/related` is called
- **THEN** the response returns entities that co-occur in the same sessions, ordered by co-occurrence count

### Requirement: Project endpoints

The system SHALL expose project endpoints:

- `GET /api/projects` -- list all projects
- `POST /api/projects` -- create project with body: `{name, gitPath?, remoteURL?}`
- `GET /api/projects/:id` -- project detail with context/session/entity counts
- `PUT /api/projects/:id` -- update project
- `GET /api/projects/:id/context` -- list context items for project
- `GET /api/projects/:id/sessions` -- list AI sessions for project
- `GET /api/projects/:id/entities` -- entity summary for project

#### Scenario: Create project via API

- **WHEN** `POST /api/projects` is called with `{"name": "My API", "gitPath": "/Users/dev/my-api"}`
- **THEN** a VaporProject is created AND the git info is auto-detected from the path AND the project is returned

#### Scenario: Get project sessions

- **WHEN** `GET /api/projects/<uuid>/sessions` is called
- **THEN** the response returns all AISession records belonging to that project

### Requirement: Export preview and commit endpoints

The system SHALL expose export endpoints:

- `POST /api/sessions/:id/export` -- preview export (returns file list + redaction summary, no git commit)
- `POST /api/sessions/:id/export/commit` -- export + git commit
- `GET /api/export/config` -- get current export settings
- `PUT /api/export/config` -- update export settings (denylist, redaction rules)

#### Scenario: Preview export

- **WHEN** `POST /api/sessions/<uuid>/export` is called
- **THEN** the response returns a JSON object listing all files that would be exported, total byte count, and any redactions that would be applied

#### Scenario: Commit export

- **WHEN** `POST /api/sessions/<uuid>/export/commit` is called AND the session has a project with gitLocalPath
- **THEN** the session is exported to `.vapor-context/` in the project's git repo AND a git commit is made AND the response returns the commit SHA

### Requirement: aisession_meta SQLite table for faceted search

The system SHALL create an `aisession_meta` table in vectors.db with columns:
- `embedding_id` (TEXT PRIMARY KEY)
- `turn_id` (TEXT NOT NULL)
- `session_id` (TEXT NOT NULL)
- `project_id` (TEXT)
- `role` (TEXT NOT NULL)
- `tool` (TEXT)
- `branch` (TEXT)
- `model_id` (TEXT)
- `captured_at` (REAL NOT NULL)
- `tags` (TEXT) -- JSON array
- `entity_kinds` (TEXT) -- JSON array

This table SHALL be used to filter KNN vector search results by project, tool, branch, role, etc.

#### Scenario: Filtered vector search

- **WHEN** a semantic search is performed with `projectId` filter
- **THEN** the query JOINs `vec_items_minilm_l12_multilingual_v2` with `aisession_meta` WHERE `project_id` matches AND results are ranked by distance
