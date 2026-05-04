# session-redaction Specification

## Purpose

Sanitize AI session content before git export using a regex + LLM hybrid approach, with user-configurable denylists and a pre-commit preview.

## ADDED Requirements

### Requirement: Regex-based secret detection

The system SHALL detect secrets using regex patterns in Phase 1 of the redaction pipeline. Patterns SHALL include:
- API key patterns: `sk-or-v1-*`, `sk-ant-*`, `ghp_*`, `gho_*`, `glpat-*`
- Generic secret patterns: `password=`, `secret=`, `token=`, `api_key=`, `Bearer <token>`
- Sensitive file paths: `~/.ssh/`, `~/.aws/credentials`, `.env`, `.id_rsa`
- Private/internal URLs: `internal.*\.com`, `localhost:\d+`

#### Scenario: API key detected

- **WHEN** a turn contains `sk-or-v1-abc123def456...` (48+ chars)
- **THEN** the key is flagged for redaction with reason "api-key-pattern"

#### Scenario: Password assignment detected

- **WHEN** a turn contains `password = mySecretPassword123`
- **THEN** the password value is flagged for redaction with reason "generic-secret-pattern"

#### Scenario: No secrets in turn

- **WHEN** a turn contains only code discussion without secrets
- **THEN** Phase 1 produces no redactions

### Requirement: LLM-based contextual secret detection

The system SHALL run an LLM pass (Phase 2) on turn content to detect contextual secrets not caught by regex, including:
- Credentials mentioned in prose ("my password is...")
- Internal/private URLs or endpoints
- Personally identifiable information (PII)
- Company-internal project names or codenames
- Database connection strings
- Private keys or certificates

The LLM SHALL return a JSON array of `{match, reason}` objects.

#### Scenario: Prose password detected

- **WHEN** a turn contains "I used the password SuperSecret123 for the database"
- **THEN** the LLM flags "SuperSecret123" for redaction with reason "credential-in-prose"

#### Scenario: Internal URL detected

- **WHEN** a turn contains "Deploy to staging at deploy.internal.mycompany.com"
- **THEN** the LLM flags the URL for redaction with reason "internal-url"

#### Scenario: LLM pass on already-redacted content

- **WHEN** Phase 1 already redacted an API key
- **THEN** Phase 2 does not flag the redacted placeholder

### Requirement: User-configurable denylist

The system SHALL support a user-configurable denylist of strings and regex patterns via UserPreferences (`exportDenylistPatterns: [String]`). These are checked in Phase 3 after regex and LLM passes.

#### Scenario: Custom denylist pattern matches

- **WHEN** the denylist contains "my-company-internal-api" AND a turn mentions that string
- **THEN** the string is flagged for redaction with reason "user-denylist"

#### Scenario: Regex denylist pattern

- **WHEN** the denylist contains `\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}` AND a turn contains an internal IP
- **THEN** the IP is flagged for redaction with reason "user-denylist"

### Requirement: Redaction output format

The system SHALL replace redacted text with `[REDACTED: <reason>]` in the exported `transcript.md`. The original text SHALL NOT appear in any exported file.

#### Scenario: Turn fully redacted

- **WHEN** a turn contains only a single API key and nothing else
- **THEN** the turn in transcript.md shows `[REDACTED: api-key-pattern]`

#### Scenario: Partial turn redaction

- **WHEN** a turn contains code with an embedded API key
- **THEN** only the API key portion is replaced with `[REDACTED: api-key-pattern]` AND surrounding code is preserved

### Requirement: Pre-commit preview with redaction summary

The system SHALL show a pre-commit preview before git export that includes:
- List of all files to be committed with sizes
- Total byte count
- Number of redactions applied
- For each redaction: truncated original text (first 20 chars) and reason
- Option to approve, skip specific redactions, or cancel

#### Scenario: User reviews redactions

- **WHEN** a session with 3 redactions is previewed
- **THEN** the preview shows all 3 redactions with reasons AND the user can approve all or cancel

#### Scenario: User skips a redaction

- **WHEN** the user unchecks one redaction from the preview
- **THEN** that text is NOT redacted in the export AND the redaction count is updated

### Requirement: Sensitive content warning

The system SHALL display a warning dialog when any turn contains keywords from a predefined list (password, secret, token, key, credential) regardless of regex/LLM detection, advising the user to review before exporting.

#### Scenario: Warning shown for keyword match

- **WHEN** a turn contains the word "password" but no actual password value
- **THEN** the warning dialog is shown BUT the turn is not automatically redacted

### Requirement: Redaction metadata in meta.json

The system SHALL include a `redaction` object in the exported `meta.json`:
- `totalRedactions` (Int) -- count of applied redactions
- `redactedTurnIDs` (array of strings) -- turn IDs that were fully redacted
- `redactedPatterns` (array of strings) -- list of pattern reasons used

#### Scenario: Meta.json includes redaction info

- **WHEN** a session with 3 redactions is exported
- **THEN** `meta.json` contains `"redaction": {"totalRedactions": 3, "redactedTurnIDs": [...], "redactedPatterns": ["api-key-pattern", "generic-secret-pattern", "user-denylist"]}`

### Requirement: isRedacted flag on AITurn

The system SHALL set `AITurn.isRedacted = true` for turns that contain any redacted content. Fully redacted turns (all content replaced) SHALL be flagged so they can be excluded from export entirely if the user prefers.

#### Scenario: Partially redacted turn

- **WHEN** a turn has one API key redacted but remaining text preserved
- **THEN** `isRedacted` is set to `true` AND the turn appears in the export with the redacted section replaced

#### Scenario: Fully redacted turn

- **WHEN** a turn's entire content consists of a single secret
- **THEN** `isRedacted` is set to `true` AND the turn appears in export as a single `[REDACTED]` line
