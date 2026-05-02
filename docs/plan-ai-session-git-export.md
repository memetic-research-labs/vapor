# Plan: AI Session Git Export

## Overview

This document specifies the git export sub-system for AI Session Capture. It covers the on-disk layout, file formats, commit strategy, and the re-vectorization import flow that lets any developer reconstruct full semantic context from a committed session.

This plan is a companion to `docs/plan-ai-session-capture.md`, which describes the full capture architecture.

---

## Goals

1. Make a committed AI session **human-readable** without Vapor.
2. Make a committed AI session **re-vectorizable** in any Vapor instance without re-running the embedding model.
3. Keep the git footprint **small** — screenshots converted to WebP, embeddings stored as compact binary blobs.
4. Keep the commit **atomic and meaningful** — one commit per session, with a clear commit message.
5. Support **incremental updates** — if a session is long-running, intermediate commits can be pushed and later merged.

---

## On-Disk Layout

```
vapor-sessions/
└── 2025-05-01/
    └── a3f7c912-4b2e-41d0-8e2f-1234567890ab/   ← AISession.id (UUID)
        ├── transcript.md        ← human-readable Q&A with timestamps
        ├── meta.json            ← session metadata
        ├── vectors.jsonl        ← one embedding per AITurn (for re-vectorization)
        └── images/
            ├── 14-23-01.webp    ← screenshot attached to turn at 14:23:01
            └── 14-45-17.webp
```

The `vapor-sessions/` directory is committed to the root of the project's git repository. A `.gitattributes` entry marks `*.webp` as binary so git does not attempt line-ending normalization.

---

## File Formats

### transcript.md

```markdown
# AI Session: My Express API Project

| Field | Value |
|---|---|
| Tool | opencode |
| Model | claude-opus-4-5 |
| Started | 2025-05-01 14:23:01 UTC |
| Ended | 2025-05-01 16:37:14 UTC |
| Turns | 47 |
| Tokens (est.) | 18,432 |
| Session ID | a3f7c912-4b2e-41d0-8e2f-1234567890ab |

---

## Turn 1 — 14:23:01 — USER

How do I add rate limiting to my Express API?

![screenshot](images/14-23-01.webp)

---

## Turn 2 — 14:23:05 — ASSISTANT (claude-opus-4-5, 4.1s)

You can use the `express-rate-limit` package:

```bash
npm install express-rate-limit
```

Then configure it as middleware:

```js
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100
});

app.use(limiter);
```
```

The Markdown is self-contained: every image reference is a relative path to the `images/` subdirectory in the same session folder.

---

### meta.json

```json
{
  "sessionID": "a3f7c912-4b2e-41d0-8e2f-1234567890ab",
  "title": "My Express API Project",
  "tool": "opencode",
  "modelID": "claude-opus-4-5",
  "projectPath": "/Users/alice/projects/my-api",
  "projectName": "my-api",
  "startedAt": "2025-05-01T14:23:01Z",
  "endedAt": "2025-05-01T16:37:14Z",
  "turnCount": 47,
  "estimatedTokens": 18432,
  "vaporVersion": "1.4.0",
  "embeddingModel": "paraphrase-multilingual-MiniLM-L12-v2",
  "embeddingDimensions": 384
}
```

`embeddingModel` and `embeddingDimensions` are stored explicitly so that a future Vapor version can validate compatibility before importing `vectors.jsonl`.

---

### vectors.jsonl

One JSON object per line. Each line corresponds to one `AITurn`:

```json
{"turnID":"b1e2f3a4-...","role":"user","turnIndex":0,"capturedAt":"2025-05-01T14:23:01Z","embedding":[0.0142,-0.0731,...]}
{"turnID":"c2d3e4f5-...","role":"assistant","turnIndex":1,"capturedAt":"2025-05-01T14:23:05Z","embedding":[-0.0218,0.0894,...]}
```

The `embedding` array contains 384 raw `Float32` values serialized as a JSON array of numbers. This is slightly larger than a binary blob but universally parseable without a special reader.

**Why include embeddings in git?**

The MiniLM model produces deterministic embeddings for the same text. However, re-embedding a large session (thousands of turns) takes several minutes on an M1 Mac. Shipping embeddings in the repo means a new team member can import a 100-turn session in under 2 seconds — the `VectorizationService` just bulk-inserts the float arrays without running any inference.

Reviewers who do not use Vapor can safely ignore `vectors.jsonl`. The file is human-unreadable but not harmful.

---

## GitExportService

```swift
@MainActor
final class GitExportService {
    static let shared = GitExportService()

    private init() {}

    /// Exports a session to disk and commits it to the project git repository.
    func exportAndCommit(_ session: AISession) async throws {
        guard let projectPath = session.projectPath else {
            throw GitExportError.noProjectPath
        }

        let sessionDir = try prepareSessionDirectory(session: session, under: projectPath)
        try writeTranscript(session: session, to: sessionDir)
        try writeMetadata(session: session, to: sessionDir)
        try await writeVectors(session: session, to: sessionDir)
        try await writeImages(session: session, to: sessionDir)
        try ensureGitattributes(in: projectPath)
        let sha = try gitCommit(session: session, projectPath: projectPath)
        session.gitCommitSHA = sha
    }

    // MARK: - Private helpers

    private func prepareSessionDirectory(session: AISession, under projectPath: String) throws -> URL {
        let root = URL(fileURLWithPath: projectPath)
        let dateStr = ISO8601DateFormatter.localDateString(from: session.startedAt)
        let dir = root
            .appendingPathComponent("vapor-sessions")
            .appendingPathComponent(dateStr)
            .appendingPathComponent(session.id.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTranscript(session: AISession, to dir: URL) throws {
        let md = TranscriptRenderer.markdown(for: session)
        try md.write(to: dir.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
    }

    private func writeMetadata(session: AISession, to dir: URL) throws {
        let meta = SessionMetadata(session: session)
        let data = try JSONEncoder.iso8601Pretty.encode(meta)
        try data.write(to: dir.appendingPathComponent("meta.json"))
    }

    private func writeVectors(session: AISession, to dir: URL) async throws {
        var lines: [String] = []
        for turn in session.turns.sorted(by: { $0.turnIndex < $1.turnIndex }) {
            guard let embeddingID = turn.embeddingID else { continue }
            let vector = try await VectorizationService.shared.loadEmbedding(id: embeddingID)
            let obj = TurnVector(turn: turn, embedding: vector)
            let line = try JSONEncoder().encode(obj)
            lines.append(String(data: line, encoding: .utf8) ?? "")
        }
        let jsonl = lines.joined(separator: "\n")
        try jsonl.write(to: dir.appendingPathComponent("vectors.jsonl"), atomically: true, encoding: .utf8)
    }

    private func writeImages(session: AISession, to dir: URL) async throws {
        let imagesDir = dir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        for asset in session.attachedImages {
            guard let blobPath = asset.blobPath else { continue }
            let src = URL(fileURLWithPath: blobPath)
            let destName = webPFileName(for: asset)
            let dest = imagesDir.appendingPathComponent(destName)
            try await ImageConverter.convertToWebP(src: src, dest: dest, quality: 0.85)
        }
    }

    private func ensureGitattributes(in projectPath: String) throws {
        let attrURL = URL(fileURLWithPath: projectPath).appendingPathComponent(".gitattributes")
        let line = "vapor-sessions/**/*.webp binary\n"
        if FileManager.default.fileExists(atPath: attrURL.path) {
            let existing = try String(contentsOf: attrURL, encoding: .utf8)
            if !existing.contains(line.trimmingCharacters(in: .newlines)) {
                try (existing + line).write(to: attrURL, atomically: true, encoding: .utf8)
            }
        } else {
            try line.write(to: attrURL, atomically: true, encoding: .utf8)
        }
    }

    private func gitCommit(session: AISession, projectPath: String) throws -> String {
        let message = "vapor: add AI session transcript [\(session.tool)] \(session.title)"
        let addResult = shell("git", "-C", projectPath, "add", "vapor-sessions/", ".gitattributes")
        guard addResult.exitCode == 0 else { throw GitExportError.gitCommandFailed(addResult.stderr) }
        let commitResult = shell("git", "-C", projectPath, "commit", "-m", message)
        guard commitResult.exitCode == 0 else { throw GitExportError.gitCommandFailed(commitResult.stderr) }
        let revResult = shell("git", "-C", projectPath, "rev-parse", "HEAD")
        return revResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func webPFileName(for asset: ImageAsset) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH-mm-ss"
        return "\(formatter.string(from: asset.capturedAt)).webp"
    }
}
```

---

## Re-Vectorization Import

When a developer pulls a repo containing `vapor-sessions/` and opens it in Vapor, a background scan detects uncommitted session directories and offers a one-click import:

```
┌────────────────────────────────────────────────────────────┐
│  3 AI sessions found in ~/projects/my-api                  │
│                                                            │
│  • My Express API Project (2025-05-01, 47 turns)           │
│  • Auth Middleware Refactor (2025-05-03, 22 turns)         │
│  • Database Migration Plan (2025-05-05, 31 turns)          │
│                                                            │
│  [Import & Vectorize]  [Dismiss]                           │
└────────────────────────────────────────────────────────────┘
```

The import flow:

1. Read `meta.json` — validate `embeddingDimensions` matches local MiniLM (384).
2. If dimensions match: read `vectors.jsonl` and bulk-insert into local SQLite-vec (fast path, ~1s for 100 turns).
3. If dimensions mismatch or `vectors.jsonl` is absent: re-embed `transcript.md` turn-by-turn using local MiniLM (~10s for 100 turns on Apple Silicon).
4. Create `AISession` and `AITurn` SwiftData records from `meta.json` + `transcript.md`.
5. Link any images in `images/` to their corresponding turns.

### Import Service

```swift
@MainActor
final class SessionImportService {
    static let shared = SessionImportService()
    private let vectorService = VectorizationService.shared

    func importSession(from sessionDir: URL) async throws -> AISession {
        let meta = try loadMetadata(from: sessionDir)
        let turns = try parseTranscript(from: sessionDir)

        let session = AISession(from: meta)
        for turn in turns { session.turns.append(turn) }

        if meta.embeddingDimensions == MiniLMEmbeddingService.dimensions,
           let vectorsURL = vectorsJSONL(in: sessionDir),
           let vectors = try? loadVectors(from: vectorsURL) {
            try await bulkInsertVectors(vectors, for: turns)
        } else {
            for turn in turns {
                _ = try await vectorService.ensureEmbedding(for: turn)
            }
        }

        try await importImages(from: sessionDir, into: session)
        return session
    }

    private func bulkInsertVectors(_ vectors: [TurnVector], for turns: [AITurn]) async throws {
        let turnMap = Dictionary(uniqueKeysWithValues: turns.map { ($0.id.uuidString, $0) })
        for vector in vectors {
            guard let turn = turnMap[vector.turnID] else { continue }
            let embeddingID = "aisession:\(turn.id.uuidString)"
            try await VectorizationService.shared.upsertEmbedding(vector.embedding, id: embeddingID)
            turn.embeddingID = embeddingID
        }
    }
}
```

---

## gitignore Considerations

The `vapor-sessions/` directory should **not** be in `.gitignore`. It is intended to be tracked.

However, teams that do not want session transcripts in their main branch can use a dedicated branch strategy:

```bash
# Conventional approach for teams that prefer isolation
git checkout -b vapor/alice/2025-05-01
# Vapor commits here automatically
git push origin vapor/alice/2025-05-01
```

Vapor's git export settings include a **"Use dedicated branch"** toggle that automates this workflow: Vapor creates/checks out `vapor/<username>/<date>` before committing and pushes to origin after the commit.

---

## Security Considerations

- Vapor shows a **pre-commit diff preview** listing all files and total byte count before any `git commit` is run.
- If the session contains the word "password", "secret", "token", "key", or "credential" in any turn, Vapor displays a **"Sensitive content warning"** dialog.
- The user can redact individual turns before export using the session reader view ("Mark as private" → turn omitted from `transcript.md` and `vectors.jsonl`).
- `meta.json` never includes user credentials, API keys, or file contents outside of session text.

---

## Implementation Phases

### Phase 1 — Core Export (1 week)

- [ ] `GitExportService.exportAndCommit(_:)` with transcript, meta, and git commit
- [ ] `TranscriptRenderer` (turns → Markdown)
- [ ] `.gitattributes` management
- [ ] "Commit Session" button in session detail view with pre-commit preview
- [ ] Sensitive content warning dialog

### Phase 2 — Image Export (3 days)

- [ ] `ImageConverter.convertToWebP(src:dest:quality:)` using `NSBitmapImageRep`
- [ ] Image filename generation (`HH-mm-ss.webp`)
- [ ] Inline image references in `transcript.md`

### Phase 3 — Vector Export & Import (4 days)

- [ ] `vectors.jsonl` write path
- [ ] `SessionImportService` — fast path (bulk insert) and slow path (re-embed)
- [ ] "Scan for vapor-sessions" on app launch / project open
- [ ] Import sheet UI

### Phase 4 — Dedicated Branch Workflow (2 days)

- [ ] "Use dedicated branch" toggle in git export settings
- [ ] Auto-create / checkout `vapor/<user>/<date>` before commit
- [ ] Auto-push after commit (requires git credentials already configured)

---

## Dependencies

- `GitExportService` depends on `AISession` and `AITurn` models from `plan-ai-session-capture.md`
- `ImageConverter` depends on `NSBitmapImageRep` (AppKit) — already available in the macOS target
- `SessionImportService` depends on `VectorizationService.shared.upsertEmbedding` (new public method needed)
- `TranscriptRenderer` has no external dependencies

---

## References

- [NSBitmapImageRep webp representation](https://developer.apple.com/documentation/appkit/nsbitmapimagerep)
- [git-rev-parse documentation](https://git-scm.com/docs/git-rev-parse)
- [.gitattributes binary attribute](https://git-scm.com/docs/gitattributes#_binary_files)
