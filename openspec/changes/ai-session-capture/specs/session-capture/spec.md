# session-capture Specification

## Purpose

Capture AI coding sessions from OpenCode and other tools, storing full Q&A transcripts with screenshot interleaving, model metadata, and session lifecycle management.

## ADDED Requirements

### Requirement: SessionCaptureFacade protocol

The system SHALL provide a `SessionCaptureFacade` that manages multiple `SessionCaptureAdapter` instances. The facade SHALL support:
- `registerAdapter(_:)` -- register an adapter by tool name
- `startAll()` -- start all registered adapters
- `stopAll()` -- stop all registered adapters
- `stopAdapter(for:)` -- stop a specific adapter by tool name
- `isCapturing` observable property

#### Scenario: Start all adapters

- **WHEN** `SessionCaptureFacade.startAll()` is called with 3 registered adapters (opencode, claude-desktop, cursor)
- **THEN** all 3 adapters begin capturing AND `isCapturing` becomes `true`

#### Scenario: Stop specific adapter

- **WHEN** `SessionCaptureFacade.stopAdapter(for: "claude-desktop")` is called
- **THEN** only the Claude Desktop adapter stops AND other adapters continue capturing

### Requirement: SessionCaptureAdapter protocol

The system SHALL define a `SessionCaptureAdapter` protocol with:
- `toolName: String` -- unique identifier (e.g. "opencode")
- `isAvailable() async -> Bool` -- check if the tool is running
- `startCapture() async throws` -- begin capturing turns
- `stopCapture() async` -- stop capturing
- `onTurnCaptured: (@Sendable (CapturedTurn) async -> Void)?` -- callback for captured turns

A `CapturedTurn` struct SHALL carry: `role`, `content`, `capturedAt`, `modelID?`, `toolName?`, `durationSeconds?`.

#### Scenario: Adapter reports availability

- **WHEN** `OpenCodeAdapter.isAvailable()` is called and the OpenCode log file exists
- **THEN** it returns `true`

#### Scenario: Adapter reports unavailability

- **WHEN** `ClaudeDesktopAdapter.isAvailable()` is called and Claude Desktop is not installed
- **THEN** it returns `false`

### Requirement: OpenCodeAdapter

The system SHALL implement `OpenCodeAdapter` that:
1. Resolves the OpenCode log path via: config.json `logDir` field -> `$XDG_DATA_HOME/opencode/` -> `~/.local/share/opencode/` -> `~/.config/opencode/`
2. Watches the log file with FSEventStream for new line appends
3. Parses JSONL lines with format: `{"role":"...","content":"...","timestamp":"...","model":"..."}`
4. Fires `onTurnCaptured` for each parsed turn
5. Uses `ProjectService.detectProject(from:)` to auto-assign the session to a project

#### Scenario: Log file found at default path

- **WHEN** OpenCodeAdapter starts AND no config.json logDir is set AND `~/.local/share/opencode/conversations.jsonl` exists
- **THEN** the adapter begins watching that file for new lines

#### Scenario: JSONL line parsed into CapturedTurn

- **WHEN** a new JSONL line `{"role":"user","content":"How do I add rate limiting?","timestamp":"2025-05-01T14:23:01Z","model":"claude-opus-4-5"}` is appended to the log file
- **THEN** `onTurnCaptured` fires with a CapturedTurn with role="user", content="How do I add rate limiting?", capturedAt=parsed timestamp, modelID="claude-opus-4-5"

#### Scenario: Malformed JSONL line

- **WHEN** a non-JSON line is appended to the log file
- **THEN** the line is skipped AND an error is logged to StatusBarService

### Requirement: AISession model

The system SHALL maintain an `AISession` SwiftData model with:
- `id` (UUID), `title` (String), `tool` (String), `projectPath` (String?), `projectName` (String?)
- `branchName` (String?), `prNumber` (Int?)
- `startedAt` (Date), `endedAt` (Date?)
- `tags: [String]`, `isArchived: Bool`, `gitCommitSHA: String?`
- `embeddingID: String?` -- session summary embedding
- `summaryAbstract: String?`, `summaryKeyPoints: [String]?`
- `totalTokensEstimated: Int`, `totalTurns: Int`, `totalAttachedImages: Int`, `totalAttachedURLs: Int`
- `project: VaporProject?`
- Cascade relationship to `turns: [AITurn]`
- Nullify relationship to `attachedImages: [ImageAsset]`
- Cascade relationship to `entityLinks: [AISessionEntityLink]`

#### Scenario: Session created on first turn

- **WHEN** the first user turn is captured for a tool that has no active session
- **THEN** a new AISession is created with `title` derived from the first turn content, `tool` set to the adapter's toolName, `startedAt` set to the turn's timestamp, and `endedAt = nil`

#### Scenario: Session closed after idle timeout

- **WHEN** no new turns are captured for the configured idle timeout (default 30 minutes)
- **THEN** `AISession.endedAt` is set to the current time AND the session summary is generated

### Requirement: AITurn model

The system SHALL maintain an `AITurn` SwiftData model with:
- `id` (UUID), `session: AISession?`, `role` (String), `turnIndex` (Int)
- `content` (String), `contentTokenCount` (Int), `capturedAt` (Date)
- `embeddingID: String?` -- `aisession:<turn-uuid>` namespace
- `modelID` (String?), `toolName` (String?)
- `attachedImageIDs: [String]`, `attachedURLs: [String]`
- `durationSeconds: Double?`, `isEdited: Bool`, `isRedacted: Bool`
- Cascade relationship to `entityLinks: [AITurnEntityLink]`

#### Scenario: Turn created from captured turn

- **WHEN** `onTurnCaptured` fires with a CapturedTurn
- **THEN** an AITurn is created with `turnIndex` incremented from the session's last turn, `content` set to the captured text, and `contentTokenCount` estimated via Tiktoken

### Requirement: Screenshot interleaving

The system SHALL automatically link screenshots to AI turns when a screenshot is captured within a configurable time window (default 30 seconds) of a turn's `capturedAt` timestamp. The screenshot's ImageAsset ID SHALL be appended to `AITurn.attachedImageIDs`.

#### Scenario: Screenshot captured near a turn

- **WHEN** a screenshot is captured at T+15s and an AITurn was captured at T+0s
- **THEN** the screenshot's ImageAsset ID is added to that AITurn's `attachedImageIDs`

#### Scenario: Screenshot captured outside the window

- **WHEN** a screenshot is captured at T+45s and the closest AITurn was at T+0s (window is 30s)
- **THEN** the screenshot is NOT linked to any turn

### Requirement: Session lifecycle management

The system SHALL manage session lifecycle via `AISessionService` singleton:
- Open session when first turn arrives from an adapter
- Close session when adapter stops, idle timeout expires, or user manually closes
- On close: generate summary, aggregate entities, create summary embedding
- Support pausing capture (discard turns captured while paused)

#### Scenario: Manual session close

- **WHEN** user clicks "End Session" in the session reader view
- **THEN** the session is closed immediately AND summary is generated AND entities are aggregated
