# project-anchoring Specification

## Purpose

Anchor all Vapor context (ContextItems, PromptRecords, ImageAssets, AISessions) to git repos, GitHub/GitLab URLs, or custom named workspaces. Enable project-scoped filtering, search, and export.

## ADDED Requirements

### Requirement: VaporProject model

The system SHALL maintain a `VaporProject` SwiftData model with the following fields:
- `id` (UUID, primary key)
- `name` (String)
- `notes` (String, optional)
- `gitLocalPath` (String, optional) -- absolute path to git repo root
- `gitRemoteURL` (String, optional) -- e.g. "https://github.com/org/repo"
- `gitCurrentBranch` (String, optional) -- updated via git rev-parse
- `detectedPRNumber` (Int, optional) -- parsed from branch name
- `colorHex` (String, optional) -- sidebar accent color
- `sortOrder` (Int)
- `createdAt` (Date)
- `lastActiveAt` (Date)

The model SHALL have cascade/nullify relationships to ContextItem, PromptRecord, ImageAsset, and AISession.

#### Scenario: Project created without git

- **WHEN** user creates a project with name "Research Notes" and no git path or remote URL
- **THEN** a VaporProject record is created with `name = "Research Notes"`, `gitLocalPath = nil`, `gitRemoteURL = nil`

#### Scenario: Project created with local git path

- **WHEN** user creates a project with name "Vapor App" and git path "/Users/dev/projects/vapor"
- **THEN** a VaporProject record is created AND the system runs `git rev-parse --show-toplevel` and `git remote get-url origin` to populate `gitLocalPath` and `gitRemoteURL`

### Requirement: Project optional FK on existing models

The system SHALL add an optional `project: VaporProject?` foreign key to `ContextItem`, `PromptRecord`, and `ImageAsset`. Context with no project assignment SHALL have `project == nil` (representing "Unassigned").

#### Scenario: ContextItem with no project

- **WHEN** a browser capture creates a ContextItem and no project is detected
- **THEN** the ContextItem is created with `project == nil`

#### Scenario: ContextItem assigned to project

- **WHEN** user assigns an existing ContextItem to project "Vapor App"
- **THEN** the ContextItem's `project` is set to the VaporProject with name "Vapor App"

### Requirement: Auto-detect project from git working directory

The system SHALL detect the current git repo when an AI session adapter captures a turn by:
1. Reading the tool process working directory
2. Running `git rev-parse --show-toplevel` to get the git root
3. Running `git remote get-url origin` to get the remote URL
4. Running `git rev-parse --abbrev-ref HEAD` to get the current branch
5. Parsing the branch name for PR numbers (patterns: `pr-(\d+)`, `feature/(\d+)-`)
6. Matching against existing VaporProject records by gitLocalPath or gitRemoteURL
7. Creating a new VaporProject if no match is found

#### Scenario: New repo detected during session

- **WHEN** OpenCodeAdapter captures a turn from CWD "/Users/dev/projects/new-api" which is a git repo with remote "https://github.com/dev/new-api"
- **AND** no VaporProject exists with that gitLocalPath or gitRemoteURL
- **THEN** a new VaporProject is created with `name = "new-api"`, `gitLocalPath = "/Users/dev/projects/new-api"`, `gitRemoteURL = "https://github.com/dev/new-api"`

#### Scenario: Existing repo detected during session

- **WHEN** OpenCodeAdapter captures a turn from CWD "/Users/dev/projects/vapor" which matches an existing VaporProject's gitLocalPath
- **THEN** the existing VaporProject is used AND `lastActiveAt` is updated to the current time

#### Scenario: PR number detected from branch name

- **WHEN** the current git branch is "pr-27-dictation-perf"
- **THEN** the VaporProject's `detectedPRNumber` is set to 27

### Requirement: Auto-detect project from browser URL

The system SHALL detect projects from browser capture URLs matching GitHub, GitLab, or Bitbucket patterns (e.g. `github.com/{org}/{repo}`, `gitlab.com/{org}/{repo}`). When a match is found, the system SHALL prompt the user to assign the context to the matching project.

#### Scenario: GitHub URL matches existing project

- **WHEN** a browser capture has sourceURL "https://github.com/memetic-research-labs/vapor/pull/19"
- **AND** a VaporProject exists with gitRemoteURL containing "github.com/memetic-research-labs/vapor"
- **THEN** the system suggests assigning the context to that project

#### Scenario: No URL match found

- **WHEN** a browser capture has sourceURL "https://example.com/article"
- **AND** no VaporProject matches the URL pattern
- **THEN** the ContextItem is created with `project == nil` (Unassigned)

### Requirement: Security-scoped bookmarks for git repo access

The system SHALL save NSURL security-scoped bookmarks for project gitLocalPaths so that folder access persists across app restarts without re-prompting the user.

#### Scenario: Bookmark persists across restart

- **WHEN** user grants access to "/Users/dev/projects/vapor" and then restarts Vapor
- **THEN** Vapor accesses the directory without prompting again

### Requirement: Project picker UI in sidebar

The system SHALL display a project picker in the Context Explorer sidebar showing:
- All projects with context item count
- An "Unassigned" option showing count of items with `project == nil`
- A "New Project" action
- Visual indication of the currently active project

#### Scenario: User selects a project

- **WHEN** user clicks "Vapor App (42)" in the project picker
- **THEN** all Context Explorer facets (domains, entities, tags, types, URLs) are filtered to only show context items belonging to that project

#### Scenario: User selects Unassigned

- **WHEN** user clicks "Unassigned (156)" in the project picker
- **THEN** all Context Explorer facets show only context items with `project == nil`

### Requirement: ProjectService singleton

The system SHALL provide a `@MainActor @Observable ProjectService` singleton with methods for:
- `detectProject(from gitPath:)` -- auto-detect from git directory
- `detectProject(from browserURL:)` -- auto-detect from URL
- `createProject(name:gitPath:remoteURL:)` -- manual creation
- `assignContextItem(_:to:)` -- assign context to project
- `assignPromptRecord(_:to:)` -- assign prompt to project
- `assignImageAsset(_:to:)` -- assign image to project
- `assignSession(_:to:)` -- assign session to project
- `refreshGitState(for:)` -- update branch and PR info
- `watchProjectDirectories()` -- FSEvents on gitLocalPaths

#### Scenario: Assign context item to project

- **WHEN** `ProjectService.assignContextItem(item, to: project)` is called
- **THEN** the ContextItem's `project` is set to the given VaporProject
