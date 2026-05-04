## 1. Project Anchoring Foundation

- [x] 1.1 Add `ContextKind.spec` enum case to ContextItem
- [x] 1.2 Create `VaporProject` SwiftData model with all fields (id, name, notes, gitLocalPath, gitRemoteURL, gitCurrentBranch, detectedPRNumber, colorHex, sortOrder, createdAt, lastActiveAt) and relationships to ContextItem, PromptRecord, ImageAsset, AISession
- [x] 1.3 Create `VaporProjectBookmark` SwiftData model with bookmarkData for security-scoped folder access
- [x] 1.4 Create VaporSchemaV2 migration registering VaporProject, VaporProjectBookmark, and adding optional project FK to ContextItem, PromptRecord, ImageAsset
- [x] 1.5 Implement `ProjectService` singleton (@MainActor @Observable) with createProject, detectProject(from gitPath:), detectProject(from browserURL:), assign methods, refreshGitState
- [x] 1.6 Implement git detection helpers: git rev-parse --show-toplevel, git remote get-url origin, git rev-parse --abbrev-ref HEAD, branch name PR number parsing
- [x] 1.7 Implement browser URL project detection: GitHub/GitLab/Bitbucket pattern matching, remote URL normalization
- [x] 1.8 Implement security-scoped bookmark save/restore for gitLocalPaths
- [x] 1.9 Add project picker UI to Context Explorer sidebar (list projects with counts, Unassigned, New Project action)
- [x] 1.10 Wire project picker to ContextExplorerStore: filter all facets by selected project, filter semantic search by project

## 2. AI Session Data Models

- [x] 2.1 Create `AISession` SwiftData model with all fields (id, title, tool, projectPath, projectName, branchName, prNumber, startedAt, endedAt, tags, isArchived, gitCommitSHA, embeddingID, summaryAbstract, summaryKeyPoints, totalTokensEstimated, totalTurns, totalAttachedImages, totalAttachedURLs, project FK)
- [x] 2.2 Create `AITurn` SwiftData model with all fields (id, session FK, role, turnIndex, content, contentTokenCount, capturedAt, embeddingID, modelID, toolName, attachedImageIDs, attachedURLs, durationSeconds, isEdited, isRedacted)
- [x] 2.3 Create `AISessionEntityLink` SwiftData model (id, confidence, surfaceText, createdAt, session FK, entityRecord FK)
- [x] 2.4 Create `AITurnEntityLink` SwiftData model (id, confidence, surfaceText, createdAt, turn FK, entityRecord FK)
- [x] 2.5 Create `AISessionTag` SwiftData model (id, text, sourceRaw, confidence, createdAt, session FK)
- [x] 2.6 Create `AIGitExportRecord` SwiftData model (id, session FK, exportedAt, gitCommitSHA, branchName, sessionDirPath, filesIncluded, totalBytes, redactionCount, redactedTurnIDs)
- [x] 2.7 Expand `EntityKind` enum with: model, tool, library, api, file, error, decision
- [x] 2.8 Register all new models in VaporSchemaV2 migration

## 3. Session Capture Facade + OpenCode Adapter

- [x] 3.1 Define `SessionCaptureAdapter` protocol (toolName, isAvailable, startCapture, stopCapture, onTurnCaptured callback)
- [x] 3.2 Define `CapturedTurn` struct (role, content, capturedAt, modelID, toolName, durationSeconds)
- [x] 3.3 Implement `SessionCaptureFacade` (@MainActor @Observable) with registerAdapter, startAll, stopAll, stopAdapter, isCapturing
- [x] 3.4 Implement `AISessionService` singleton: open session on first turn, close on idle timeout/adapter stop/manual, generate summary on close
- [x] 3.5 Implement `OpenCodeAdapter`: log path resolution (config.json, XDG_DATA_HOME, defaults), FSEventStream file watcher, JSONL line parser
- [x] 3.6 Implement OpenCode JSONL parsing: extract role, content, timestamp, model from each line; skip malformed lines; log errors to StatusBar
- [x] 3.7 Wire OpenCodeAdapter to ProjectService.detectProject(from gitPath:) for auto project assignment
- [x] 3.8 Implement idle timeout (configurable, default 30 min) with timer-based session close
- [x] 3.9 Add "Pause capture" toggle to menu bar (discard turns while paused, orange dot indicator)
- [x] 8.8 Implement `import` command (scan .vapor-context/, fast-path from vectors.jsonl, slow-path re-embed)
- [x] 9.17 Implement pre-commit preview UI: file list, byte count, redaction summary, approve/skip/cancel
- [x] 9.18 Implement sensitive content warning dialog (keyword detection: password, secret, token, key, credential)
- [x] 9.19 Implement re-import flow: scan .vapor-context/, validate embedding dimensions, fast-path bulk insert, slow-path re-embed
- [x] 12.4 Add onboarding prompt for first enable (explain capture, request folder access, persist scoped bookmark)
- [x] 12.5 Add StatusBar log integration (session open/close/turn-captured/vectorization/git commit events)
