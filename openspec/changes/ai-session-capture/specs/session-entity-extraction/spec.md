# session-entity-extraction Specification

## Purpose

Extract entities from AI session turns, link them to sessions, and expand the EntityKind enum to cover AI-specific entity types like decisions, libraries, APIs, and models.

## ADDED Requirements

### Requirement: Per-turn entity extraction

The system SHALL extract entities from each AITurn's `content` using the existing `EntityExtractionService`. For each extracted entity:
1. Create or find an existing `EntityRecord` by `entityHash` (deduplication)
2. Create an `AITurnEntityLink` with confidence score and surface text
3. Store the turn-level entity for faceted search

#### Scenario: Turn contains library mention

- **WHEN** an AITurn with content "You can use the express-rate-limit package" is captured
- **THEN** an EntityRecord with kind="library", displayText="express-rate-limit" is created (or found by hash) AND an AITurnEntityLink is created linking the turn to that entity

#### Scenario: Duplicate entity across turns

- **WHEN** two AITurns both mention "express-rate-limit"
- **THEN** only one EntityRecord exists AND both turns have their own AITurnEntityLink to it AND the EntityRecord's `lastSeenAt` is updated

### Requirement: Session-level entity aggregation

The system SHALL aggregate all entities from a session's turns into session-level `AISessionEntityLink` records when a session is closed. Each entity SHALL record its total occurrence count and the list of linked turn IDs.

#### Scenario: Session closed with repeated entities

- **WHEN** a session with 10 turns is closed AND "express-rate-limit" appeared in 4 turns
- **THEN** one AISessionEntityLink is created with the entity, `occurrences` set to 4 (tracked via meta.json or summary data)

### Requirement: Expanded EntityKind

The system SHALL expand the `EntityKind` enum to include:
- `model` -- LLM model names (e.g. "claude-opus-4-5", "gpt-4o")
- `tool` -- AI tools (e.g. "opencode", "cursor", "claude-desktop")
- `library` -- Software libraries (e.g. "express-rate-limit", "swift-nio")
- `api` -- API endpoints (e.g. "POST /api/v1/auth/keys")
- `file` -- File paths referenced in sessions (e.g. "src/main.swift")
- `error` -- Error types or messages (e.g. "NSInternalInconsistencyException")
- `decision` -- Architectural decisions (extracted by LLM)

These SHALL be added alongside the existing 9 types: person, organization, product, location, date, url, number, code, concept.

#### Scenario: EntityExtractionService returns model kind

- **WHEN** the NER backend extracts "claude-opus-4-5" from a turn and classifies it as a model
- **THEN** an EntityRecord with `kind = .model` is created

#### Scenario: EntityExtractionService returns decision kind

- **WHEN** the decision extraction LLM prompt identifies "Use 15-minute sliding window for rate limiting"
- **THEN** an EntityRecord with `kind = .decision` is created

### Requirement: Decision extraction via LLM

The system SHALL run a dedicated LLM prompt on session close to extract architectural decisions. The prompt SHALL ask the LLM to identify decisions as JSON objects with `text`, `kind` (always "decision"), and `confidence` fields. Decisions SHALL be stored as EntityRecords with kind `.decision`.

#### Scenario: Decisions extracted from session

- **WHEN** a session about rate limiting is closed
- **THEN** the LLM extracts decisions like "Use express-rate-limit middleware" AND "Configure 15-minute sliding window" AND each is stored as an EntityRecord with kind `.decision`

#### Scenario: No decisions found

- **WHEN** a session contains only Q&A without clear decisions
- **THEN** no EntityRecords with kind `.decision` are created

### Requirement: Per-turn auto-tagging

The system SHALL adapt `TaggerService` to generate auto-tags for AITurns, combining:
- Top keywords from turn content (excluding stop words)
- Entity names with confidence > 0.6
- Role-based tags ("user-question", "assistant-explanation")

Tags SHALL be stored on the AISession's `tags` array (session-level aggregation of turn tags).

#### Scenario: Auto-tags generated for session

- **WHEN** a session about "rate limiting" with "express" library mentions is closed
- **THEN** the AISession's `tags` includes tags like "rate-limiting", "express", "middleware", "api"

### Requirement: AITurnEntityLink model

The system SHALL maintain an `AITurnEntityLink` SwiftData model with:
- `id` (UUID), `confidence` (Double), `surfaceText` (String), `createdAt` (Date)
- `turn: AITurn?` (FK), `entityRecord: EntityRecord?` (FK)

#### Scenario: Entity link created with confidence

- **WHEN** the NER backend extracts "express-rate-limit" with confidence 0.95
- **THEN** the AITurnEntityLink is created with `confidence = 0.95` and `surfaceText = "express-rate-limit"`

### Requirement: AISessionEntityLink model

The system SHALL maintain an `AISessionEntityLink` SwiftData model with:
- `id` (UUID), `confidence` (Double), `surfaceText` (String), `createdAt` (Date)
- `session: AISession?` (FK), `entityRecord: EntityRecord?` (FK)

#### Scenario: Session entity link created on close

- **WHEN** a session is closed AND entity "express-rate-limit" appeared in 4 turns
- **THEN** an AISessionEntityLink is created linking the session to that entity

### Requirement: AISessionTag model

The system SHALL maintain an `AISessionTag` SwiftData model with:
- `id` (UUID), `text` (String), `sourceRaw` (String) -- "auto" | "user" | "llm"
- `confidence` (Double?), `createdAt` (Date), `session: AISession?` (FK)

#### Scenario: LLM-generated tag

- **WHEN** the session summary LLM generates tag "rate-limiting"
- **THEN** an AISessionTag is created with `text = "rate-limiting"`, `sourceRaw = "llm"`

#### Scenario: User-created tag

- **WHEN** user manually adds tag "urgent-fix" to a session
- **THEN** an AISessionTag is created with `text = "urgent-fix"`, `sourceRaw = "user"`
