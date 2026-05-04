import Foundation
import SwiftData
import OSLog

nonisolated private let exportLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "GitExport")

struct ExportPreview {
    let sessionID: UUID
    let title: String
    let tool: String
    let totalTurns: Int
    let redactionCount: Int
    let fullyRedactedTurnIDs: [String]
    let sensitiveKeywords: [String]
    let hasProjectPath: Bool
    let projectRoot: String
    let estimatedFiles: [String]
    let branchName: String
}

struct GitExportResult {
    let session: AISession
    let sessionDir: URL
    let filesIncluded: [String]
    let totalBytes: Int64
    let commitSHA: String?
}

@MainActor
@Observable
final class GitExportService {
    static let shared = GitExportService()

    private var modelContext: ModelContext?

    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter
    }()

    private let timeFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm-ss"
        return timeFormatter
    }()

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func previewExport(_ session: AISession) -> ExportPreview {
        let turns = session.turns.sorted { $0.turnIndex < $1.turnIndex }
        let redactionResult = RedactionService.shared.redactTurns(turns)
        let sensitiveKeywords = RedactionService.shared.detectSensitiveContentInSession(turns)
        let hasProjectPath = session.project?.gitLocalPath != nil || session.projectPath != nil
        let projectRoot = session.project?.gitLocalPath ?? session.projectPath ?? ""

        var estimatedFiles = ["transcript.md", "meta.json"]
        if !session.entityLinks.isEmpty { estimatedFiles.append("entities.json") }
        if !turns.allSatisfy({ $0.embeddingID == nil }) { estimatedFiles.append("vectors.jsonl") }
        if turns.contains(where: { !$0.attachedURLs.isEmpty }) { estimatedFiles.append("urls/references.jsonl") }
        if !session.attachedImages.isEmpty { estimatedFiles.append("images/...") }

        return ExportPreview(
            sessionID: session.id,
            title: session.title,
            tool: session.tool,
            totalTurns: turns.count,
            redactionCount: redactionResult.totalMatchCount,
            fullyRedactedTurnIDs: redactionResult.fullyRedactedTurnIDs.map(\.uuidString),
            sensitiveKeywords: sensitiveKeywords,
            hasProjectPath: hasProjectPath,
            projectRoot: projectRoot,
            estimatedFiles: estimatedFiles,
            branchName: session.branchName ?? ""
        )
    }

    func exportSession(_ session: AISession, to projectRoot: String) async throws -> GitExportResult {
        guard let modelContext else { throw GitExportError.noModelContext }

        let turns = session.turns.sorted { $0.turnIndex < $1.turnIndex }

        let redactionResult = RedactionService.shared.redactTurns(turns)
        let redactedMap = Dictionary(uniqueKeysWithValues: redactionResult.redactedContents)

        let dateStr = dateFormatter.string(from: session.startedAt)
        let sessionDir = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(".vapor-context/sessions/\(dateStr)/\(session.id.uuidString)")

        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        var filesIncluded: [String] = []
        var totalBytes: Int64 = 0

        let transcriptContent = renderTranscript(session: session, turns: turns, redactedContents: redactedMap)
        let transcriptURL = sessionDir.appendingPathComponent("transcript.md")
        try transcriptContent.write(to: transcriptURL, atomically: true, encoding: .utf8)
        filesIncluded.append("transcript.md")
        totalBytes += Int64((try? transcriptURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)

        let metaContent = renderMeta(session: session, turns: turns, filesIncluded: filesIncluded, redactionCount: redactionResult.totalMatchCount, redactedTurnIDs: redactionResult.fullyRedactedTurnIDs.map(\.uuidString))
        let metaURL = sessionDir.appendingPathComponent("meta.json")
        try metaContent.write(to: metaURL, atomically: true, encoding: .utf8)
        filesIncluded.append("meta.json")
        totalBytes += Int64((try? metaURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)

        let entitiesContent = renderEntities(session: session)
        if !entitiesContent.isEmpty {
            let entitiesURL = sessionDir.appendingPathComponent("entities.json")
            try entitiesContent.write(to: entitiesURL, atomically: true, encoding: .utf8)
            filesIncluded.append("entities.json")
            totalBytes += Int64((try? entitiesURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }

        let vectorsContent = renderVectors(turns: turns)
        if !vectorsContent.isEmpty {
            let vectorsURL = sessionDir.appendingPathComponent("vectors.jsonl")
            try vectorsContent.write(to: vectorsURL, atomically: true, encoding: .utf8)
            filesIncluded.append("vectors.jsonl")
            totalBytes += Int64((try? vectorsURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }

        let urlsContent = renderURLs(turns: turns)
        if !urlsContent.isEmpty {
            let urlsDir = sessionDir.appendingPathComponent("urls")
            try FileManager.default.createDirectory(at: urlsDir, withIntermediateDirectories: true)
            let urlsURL = urlsDir.appendingPathComponent("references.jsonl")
            try urlsContent.write(to: urlsURL, atomically: true, encoding: .utf8)
            filesIncluded.append("urls/references.jsonl")
            totalBytes += Int64((try? urlsURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }

        let imagesDir = sessionDir.appendingPathComponent("images")
        if !session.attachedImages.isEmpty {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for image in session.attachedImages {
                let blobURL = BlobStore.shared.fileURL(relativePath: image.blobPath)
                guard let data = try? Data(contentsOf: blobURL) else { continue }
                let ext = "webp"
                let filename = "\(image.id.uuidString).\(ext)"
                let fileURL = imagesDir.appendingPathComponent(filename)
                try data.write(to: fileURL)
                filesIncluded.append("images/\(filename)")
                totalBytes += Int64(data.count)
            }
        }

        let mediaDir = sessionDir.appendingPathComponent("media")
        let mediaExtensions: Set<String> = ["pdf", "mp4", "gif", "mov"]
        let allAttachments = session.attachedImages.filter { mediaExtensions.contains($0.mimeType.components(separatedBy: "/").last ?? "") }
        if !allAttachments.isEmpty {
            try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
            for media in allAttachments {
                let blobURL = BlobStore.shared.fileURL(relativePath: media.blobPath)
                guard let data = try? Data(contentsOf: blobURL) else { continue }
                let ext = media.mimeType.components(separatedBy: "/").last ?? "bin"
                let filename = "\(media.id.uuidString).\(ext)"
                let fileURL = mediaDir.appendingPathComponent(filename)
                try data.write(to: fileURL)
                filesIncluded.append("media/\(filename)")
                totalBytes += Int64(data.count)
            }
        }

        try createGitattributes(at: projectRoot)

        let commitSHA = try gitAddAndCommit(sessionDir: sessionDir, projectRoot: projectRoot, session: session, files: filesIncluded)

        if let branch = session.branchName, !branch.isEmpty {
            try createBranchSymlink(sessionDir: sessionDir, projectRoot: projectRoot, branch: branch, sessionID: session.id.uuidString)
            try appendToBranchIndex(projectRoot: projectRoot, branch: branch, session: session)
        }

        let record = AIGitExportRecord(
            gitCommitSHA: commitSHA ?? "",
            branchName: session.branchName ?? "",
            sessionDirPath: sessionDir.path,
            filesIncluded: filesIncluded,
            totalBytes: Int(totalBytes),
            redactionCount: redactionResult.totalMatchCount,
            redactedTurnIDs: redactionResult.fullyRedactedTurnIDs.map(\.uuidString),
            session: session
        )
        modelContext.insert(record)
        try modelContext.save()

        return GitExportResult(
            session: session,
            sessionDir: sessionDir,
            filesIncluded: filesIncluded,
            totalBytes: totalBytes,
            commitSHA: commitSHA
        )
    }

    // MARK: - Renderers

    private func renderTranscript(session: AISession, turns: [AITurn], redactedContents: [UUID: String]) -> String {
        var lines: [String] = []
        lines.append("# \(session.title)")
        lines.append("")
        lines.append("Tool: \(session.tool)")
        if let project = session.projectName { lines.append("Project: \(project)") }
        if let branch = session.branchName { lines.append("Branch: \(branch)") }
        if let pr = session.prNumber { lines.append("PR: #\(pr)") }
        lines.append("Started: \(ISO8601DateFormatter().string(from: session.startedAt))")
        if let ended = session.endedAt {
            lines.append("Ended: \(ISO8601DateFormatter().string(from: ended))")
        }
        lines.append("Turns: \(turns.count)")
        lines.append("")
        lines.append("---")
        lines.append("")

        for turn in turns {
            let timestamp = ISO8601DateFormatter().string(from: turn.capturedAt)
            var roleLine = "## \(turn.role.uppercased())"
            if let model = turn.modelID { roleLine += " (\(model))" }
            roleLine += " — \(timestamp)"
            lines.append(roleLine)
            lines.append("")
            let content = redactedContents[turn.id] ?? turn.content
            lines.append(content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func renderMeta(session: AISession, turns: [AITurn], filesIncluded: [String], redactionCount: Int, redactedTurnIDs: [String]) -> String {
        var meta: [String: Any] = [
            "sessionId": session.id.uuidString,
            "title": session.title,
            "tool": session.tool,
            "totalTurns": turns.count,
            "totalTokensEstimated": session.totalTokensEstimated,
            "startedAt": ISO8601DateFormatter().string(from: session.startedAt),
            "filesIncluded": filesIncluded,
            "vaporVersion": "1.0.6",
            "embeddingModel": "MiniLM paraphrase-multilingual-L12-v2",
            "embeddingDimensions": 384,
        ]
        if let ended = session.endedAt { meta["endedAt"] = ISO8601DateFormatter().string(from: ended) }
        if let project = session.projectName { meta["projectName"] = project }
        if let branch = session.branchName { meta["branchName"] = branch }
        if let pr = session.prNumber { meta["prNumber"] = pr }
        if !session.tags.isEmpty { meta["tags"] = session.tags }
        if let abstract = session.summaryAbstract { meta["summaryAbstract"] = abstract }
        if let keyPointsData = session.summaryKeyPointsData,
           let keyPoints = try? JSONDecoder().decode([String].self, from: keyPointsData) {
            meta["summaryKeyPoints"] = keyPoints
        }

        meta["redaction"] = [
            "totalRedactions": redactionCount,
            "redactedTurnIDs": redactedTurnIDs,
            "redactedPatterns": [] as [String],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func renderEntities(session: AISession) -> String {
        let entityLinks = session.entityLinks
        guard !entityLinks.isEmpty else { return "" }

        let entities: [[String: Any]] = entityLinks.compactMap { link in
            guard let entity = link.entityRecord else { return nil }
            let turnIDs = session.turns.compactMap { turn in
                turn.entityLinks.contains { $0.entityRecord?.id == entity.id } ? turn.id.uuidString : nil
            }
            return [
                "entityId": entity.id.uuidString,
                "text": entity.displayText,
                "kind": entity.kind.rawValue,
                "confidence": link.confidence,
                "occurrences": turnIDs.count,
                "turnIds": turnIDs,
            ] as [String: Any]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: entities, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    private func renderVectors(turns: [AITurn]) -> String {
        var lines: [String] = []
        for turn in turns {
            var dict: [String: Any] = [
                "turnId": turn.id.uuidString,
                "role": turn.role,
                "turnIndex": turn.turnIndex,
                "capturedAt": ISO8601DateFormatter().string(from: turn.capturedAt),
            ]
            if turn.embeddingID != nil {
                dict["embeddingId"] = turn.embeddingID ?? ""
            }
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let json = String(data: data, encoding: .utf8) else { continue }
            lines.append(json)
        }
        return lines.joined(separator: "\n")
    }

    private func renderURLs(turns: [AITurn]) -> String {
        var lines: [String] = []
        var seenURLs = Set<String>()
        for turn in turns {
            for url in turn.attachedURLs {
                guard !seenURLs.contains(url) else { continue }
                seenURLs.insert(url)
                var dict: [String: String] = [
                    "url": url,
                    "turnId": turn.id.uuidString,
                    "capturedAt": ISO8601DateFormatter().string(from: turn.capturedAt),
                ]
                if let components = URL(string: url) {
                    dict["domain"] = components.host ?? ""
                }
                guard let data = try? JSONSerialization.data(withJSONObject: dict),
                      let json = String(data: data, encoding: .utf8) else { continue }
                lines.append(json)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Git operations

    private func gitAddAndCommit(sessionDir: URL, projectRoot: String, session: AISession, files: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)

        let addArgs = files.map { sessionDir.path.dropFirst(projectRoot.count + 1) + "/" + $0 }
        process.arguments = ["add", "-A", ".vapor-context/"]

        try process.run()
        process.waitUntilExit()

        let message = "vapor: add AI session [\(session.tool)] \(session.title) (\(session.turns.count) turns)"

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.currentDirectoryURL = URL(fileURLWithPath: projectRoot)
        commitProcess.arguments = ["commit", "-m", message]

        try commitProcess.run()
        commitProcess.waitUntilExit()

        let shaProcess = Process()
        shaProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        shaProcess.currentDirectoryURL = URL(fileURLWithPath: projectRoot)
        shaProcess.arguments = ["rev-parse", "HEAD"]

        let pipe = Pipe()
        shaProcess.standardOutput = pipe
        try shaProcess.run()
        shaProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createBranchSymlink(sessionDir: URL, projectRoot: String, branch: String, sessionID: String) throws {
        let byBranchDir = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(".vapor-context/by-branch/\(branch)")
        try FileManager.default.createDirectory(at: byBranchDir, withIntermediateDirectories: true)

        let linkURL = byBranchDir.appendingPathComponent(sessionID)
        let relativePath = "../../sessions" + sessionDir.path
            .dropFirst((projectRoot + "/.vapor-context").count)
        if FileManager.default.fileExists(atPath: linkURL.path) {
            try FileManager.default.removeItem(at: linkURL)
        }
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: relativePath)
    }

    private func appendToBranchIndex(projectRoot: String, branch: String, session: AISession) throws {
        let branchDir = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(".vapor-context/branches/\(branch)")
        try FileManager.default.createDirectory(at: branchDir, withIntermediateDirectories: true)

        let indexURL = branchDir.appendingPathComponent("sessions.jsonl")
        var entry: [String: Any] = [
            "sessionId": session.id.uuidString,
            "date": dateFormatter.string(from: session.startedAt),
            "title": session.title,
            "turnCount": session.totalTurns,
        ]
        if let tool = session.projectName { entry["projectName"] = tool }

        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let json = String(data: data, encoding: .utf8) else { return }

        let line = json + "\n"
        if FileManager.default.fileExists(atPath: indexURL.path) {
            if let handle = try? FileHandle(forWritingTo: indexURL) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
            }
        } else {
            try line.write(to: indexURL, atomically: true, encoding: .utf8)
        }
    }

    private func createGitattributes(at projectRoot: String) throws {
        let attrsURL = URL(fileURLWithPath: projectRoot + "/.vapor-context/.gitattributes")
        guard !FileManager.default.fileExists(atPath: attrsURL.path) else { return }

        let content = """
        **/*.webp binary
        **/*.pdf binary
        **/*.mp4 binary
        **/*.gif binary
        by-branch/** symlink

        """
        try content.write(to: attrsURL, atomically: true, encoding: .utf8)

        let gitattrsURL = URL(fileURLWithPath: projectRoot + "/.gitattributes")
        guard !FileManager.default.fileExists(atPath: gitattrsURL.path) else { return }
        try ".vapor-context/** linguist-generated\n".write(to: gitattrsURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Full project export

    func exportFullProject(_ project: VaporProject, to projectRoot: String) async throws -> [GitExportResult] {
        guard let modelContext else { throw GitExportError.noModelContext }

        let sessions = project.sessions.filter { !$0.isArchived }
        var results: [GitExportResult] = []

        for session in sessions {
            let result = try await exportSession(session, to: projectRoot)
            results.append(result)
        }

        return results
    }
}

enum GitExportError: Error, LocalizedError {
    case noModelContext
    case noProjectPath

    var errorDescription: String? {
        switch self {
        case .noModelContext: "ModelContext is not available"
        case .noProjectPath: "Project has no local git path"
        }
    }
}
