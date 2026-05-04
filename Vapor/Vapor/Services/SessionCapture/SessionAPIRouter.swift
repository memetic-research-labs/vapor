import Foundation
import SwiftData
import OSLog

nonisolated private let apiLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "SessionAPI")

struct SessionAPIResponse {
    let status: Int
    let body: [String: Any]
}

@MainActor
final class SessionAPIRouter {
    static let shared = SessionAPIRouter()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func handle(method: String, path: String, query: [String: String], body: [String: Any]?) -> SessionAPIResponse {
        switch (method, path) {
        case ("GET", "/api/sessions"):
            return listSessions(query: query)
        case ("DELETE", _):
            if let id = path.match("/api/sessions/") {
                return archiveSession(id: id)
            }
        case ("POST", _):
            if path == "/api/search/sessions" {
                return searchSessions(query: query, body: body)
            }
            if path == "/api/search/turns" {
                return searchTurns(query: query, body: body)
            }
            if let id = path.match("/api/sessions/"),
               let slashIndex = id.firstIndex(of: "/") {
                let sessionID = String(id[id.startIndex..<slashIndex])
                let action = String(id[id.index(after: slashIndex)...])
                switch action {
                case "export":
                    return previewExport(sessionID: sessionID)
                case "export/commit":
                    return commitExport(sessionID: sessionID, body: body)
                default:
                    break
                }
            }
        case ("GET", _):
            if let id = path.match("/api/sessions/") {
                return getSession(id: id)
            }
            if let id = path.match("/api/sessions/")?.split(separator: "/").first,
               let suffix = path.components(separatedBy: "/api/sessions/\(id)/").last {
                return getSessionSubpath(id: String(id), suffix: suffix, query: query)
            }
            if path == "/api/projects" {
                return listProjects()
            }
            if path == "/api/export/config" {
                return getExportConfig()
            }
            if let id = path.match("/api/projects/") {
                if path.contains("/context") { return projectContext(id: id) }
                if path.contains("/sessions") { return projectSessions(id: id) }
                if path.contains("/entities") { return projectEntities(id: id) }
                return getProject(id: id)
            }
        case ("POST", "/api/projects"):
            return createProject(body: body)
        case ("PUT", _):
            if let id = path.match("/api/projects/") {
                return updateProject(id: id, body: body)
            }
            if path == "/api/export/config" {
                return updateExportConfig(body: body)
            }
        default:
            break
        }
        return SessionAPIResponse(status: 404, body: ["error": "Not found"])
    }

    // MARK: - Sessions

    private func listSessions(query: [String: String]) -> SessionAPIResponse {
        guard let modelContext else { return .error("No model context") }

        var descriptor = FetchDescriptor<AISession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        var sessions = (try? modelContext.fetch(descriptor)) ?? []

        if let tool = query["tool"] {
            sessions = sessions.filter { $0.tool == tool }
        }
        if let projectID = query["project"], let uuid = UUID(uuidString: projectID) {
            sessions = sessions.filter { $0.project?.id == uuid }
        }
        if let branch = query["branch"] {
            sessions = sessions.filter { $0.branchName == branch }
        }
        if let limit = Int(query["limit"] ?? "50") {
            sessions = Array(sessions.prefix(limit))
        }
        if let offset = Int(query["offset"] ?? "0"), offset > 0 {
            sessions = Array(sessions.dropFirst(offset))
        }

        let items = sessions.map { sessionDict($0) }
        return SessionAPIResponse(status: 200, body: [
            "sessions": items,
            "count": items.count
        ])
    }

    private func getSession(id: String) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: id) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid session ID"])
        }
        let descriptor = FetchDescriptor<AISession>(predicate: #Predicate { $0.id == uuid })
        guard let session = try? modelContext.fetch(descriptor).first else {
            return SessionAPIResponse(status: 404, body: ["error": "Session not found"])
        }
        return SessionAPIResponse(status: 200, body: sessionDetailDict(session))
    }

    private func archiveSession(id: String) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: id) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid session ID"])
        }
        let descriptor = FetchDescriptor<AISession>(predicate: #Predicate { $0.id == uuid })
        guard let session = try? modelContext.fetch(descriptor).first else {
            return SessionAPIResponse(status: 404, body: ["error": "Session not found"])
        }
        session.isArchived = true
        try? modelContext.save()
        return SessionAPIResponse(status: 200, body: ["status": "archived"])
    }

    private func getSessionSubpath(id: String, suffix: String, query: [String: String]) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: id) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid session ID"])
        }
        let descriptor = FetchDescriptor<AISession>(predicate: #Predicate { $0.id == uuid })
        guard let session = try? modelContext.fetch(descriptor).first else {
            return SessionAPIResponse(status: 404, body: ["error": "Session not found"])
        }

        let turns = session.turns.sorted { $0.turnIndex < $1.turnIndex }

        switch suffix {
        case "turns":
            var filtered = turns
            if let role = query["role"] {
                filtered = filtered.filter { $0.role == role }
            }
            if let limit = Int(query["limit"] ?? "50") {
                filtered = Array(filtered.prefix(limit))
            }
            if let offset = Int(query["offset"] ?? "0"), offset > 0 {
                filtered = Array(filtered.dropFirst(offset))
            }
            let items = filtered.map { turnDict($0) }
            return SessionAPIResponse(status: 200, body: [
                "turns": items,
                "count": items.count
            ])
        case "summary":
            return SessionAPIResponse(status: 200, body: [
                "abstract": session.summaryAbstract ?? "",
                "keyPoints": session.summaryKeyPointsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [],
                "totalTokens": session.totalTokensEstimated,
                "totalTurns": session.totalTurns,
                "totalImages": session.totalAttachedImages,
                "totalURLs": session.totalAttachedURLs,
                "duration": sessionDuration(session)
            ])
        case "entities":
            let entities = session.entityLinks.map { [
                "text": $0.surfaceText,
                "confidence": $0.confidence,
                "kind": $0.entityRecord?.kind.rawValue ?? "",
                "entityId": $0.entityRecord?.id.uuidString ?? ""
            ] as [String: Any] }
            return SessionAPIResponse(status: 200, body: ["entities": entities])
        case "tags":
            return SessionAPIResponse(status: 200, body: ["tags": session.tags])
        default:
            return SessionAPIResponse(status: 404, body: ["error": "Not found"])
        }
    }

    // MARK: - Search

    private func searchSessions(query: [String: String], body: [String: Any]?) -> SessionAPIResponse {
        guard let q = body?["query"] as? String, !q.isEmpty else {
            return SessionAPIResponse(status: 400, body: ["error": "Missing query"])
        }
        let limit = body?["limit"] as? Int ?? 50
        let projectID = body?["projectId"] as? String
        let tool = body?["tool"] as? String

        Task { @MainActor in
            let ids = await VectorizationService.shared.searchTurnIDs(matching: q, limit: limit)
            var turnIDsBySession: [UUID: [UUID]] = [:]
            for id in ids {
                guard let modelContext else { break }
                let desc = FetchDescriptor<AITurn>(predicate: #Predicate { $0.id == id })
                if let turn = try? modelContext.fetch(desc).first, let sessionID = turn.session?.id {
                    turnIDsBySession[sessionID, default: []].append(id)
                }
            }
        }

        guard let modelContext else { return .error("No model context") }
        var descriptor = FetchDescriptor<AISession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        var sessions = (try? modelContext.fetch(descriptor)) ?? []
        if let projectID, let uuid = UUID(uuidString: projectID) {
            sessions = sessions.filter { $0.project?.id == uuid }
        }
        if let tool {
            sessions = sessions.filter { $0.tool == tool }
        }
        let items = sessions.prefix(limit).map { sessionDict($0) }
        return SessionAPIResponse(status: 200, body: ["sessions": items])
    }

    private func searchTurns(query: [String: String], body: [String: Any]?) -> SessionAPIResponse {
        guard let q = body?["query"] as? String, !q.isEmpty else {
            return SessionAPIResponse(status: 400, body: ["error": "Missing query"])
        }
        let limit = body?["limit"] as? Int ?? 50

        guard let modelContext else { return .error("No model context") }
        var descriptor = FetchDescriptor<AITurn>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        var turns = (try? modelContext.fetch(descriptor)) ?? []

        if let projectID = body?["projectId"] as? String, let uuid = UUID(uuidString: projectID) {
            turns = turns.filter { $0.session?.project?.id == uuid }
        }
        if let role = body?["role"] as? String {
            turns = turns.filter { $0.role == role }
        }

        let items = turns.prefix(limit).map { turnDict($0) }
        return SessionAPIResponse(status: 200, body: ["turns": items, "count": items.count])
    }

    // MARK: - Projects

    private func listProjects() -> SessionAPIResponse {
        guard let modelContext else { return .error("No model context") }
        let descriptor = FetchDescriptor<VaporProject>(sortBy: [SortDescriptor(\.lastActiveAt, order: .reverse)])
        let projects = (try? modelContext.fetch(descriptor)) ?? []
        let items = projects.map { projectDict($0) }
        return SessionAPIResponse(status: 200, body: ["projects": items])
    }

    private func createProject(body: [String: Any]?) -> SessionAPIResponse {
        guard let name = body?["name"] as? String, !name.isEmpty else {
            return SessionAPIResponse(status: 400, body: ["error": "Missing name"])
        }
        do {
            let project = try ProjectService.shared.createProject(name: name)
            return SessionAPIResponse(status: 201, body: projectDict(project))
        } catch {
            return SessionAPIResponse(status: 500, body: ["error": error.localizedDescription])
        }
    }

    private func getProject(id: String) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: id) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid project ID"])
        }
        let descriptor = FetchDescriptor<VaporProject>(predicate: #Predicate { $0.id == uuid })
        guard let project = try? modelContext.fetch(descriptor).first else {
            return SessionAPIResponse(status: 404, body: ["error": "Project not found"])
        }
        return SessionAPIResponse(status: 200, body: projectDict(project))
    }

    private func updateProject(id: String, body: [String: Any]?) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: id) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid project ID"])
        }
        let descriptor = FetchDescriptor<VaporProject>(predicate: #Predicate { $0.id == uuid })
        guard let project = try? modelContext.fetch(descriptor).first else {
            return SessionAPIResponse(status: 404, body: ["error": "Project not found"])
        }
        if let name = body?["name"] as? String { project.name = name }
        if let notes = body?["notes"] as? String { project.notes = notes }
        if let color = body?["colorHex"] as? String { project.colorHex = color }
        try? modelContext.save()
        return SessionAPIResponse(status: 200, body: projectDict(project))
    }

    private func projectContext(id: String) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: id) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid project ID"])
        }
        let projectID = uuid
        let descriptor = FetchDescriptor<ContextItem>(predicate: #Predicate { $0.project?.id == projectID })
        let items = (try? modelContext.fetch(descriptor)) ?? []
        let dicts = items.map { [
            "id": $0.id.uuidString,
            "title": $0.sourceTitle,
            "type": $0.kind.rawValue,
            "capturedAt": ISO8601DateFormatter().string(from: $0.capturedAt)
        ] as [String: Any] }
        return SessionAPIResponse(status: 200, body: ["items": dicts, "count": dicts.count])
    }

    private func projectSessions(id: String) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: id) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid project ID"])
        }
        let projectID = uuid
        let descriptor = FetchDescriptor<AISession>(predicate: #Predicate { $0.project?.id == projectID })
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        let items = sessions.map { sessionDict($0) }
        return SessionAPIResponse(status: 200, body: ["sessions": items, "count": items.count])
    }

    private func projectEntities(id: String) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: id) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid project ID"])
        }
        let projectID = uuid
        let sessions = FetchDescriptor<AISession>(predicate: #Predicate { $0.project?.id == projectID })
        let allSessions = (try? modelContext.fetch(sessions)) ?? []
        let entitySet = Set(allSessions.flatMap { $0.entityLinks.compactMap { $0.entityRecord } })
        let dicts = entitySet.map { [
            "id": $0.id.uuidString,
            "text": $0.displayText,
            "kind": $0.kind.rawValue
        ] as [String: Any] }
        return SessionAPIResponse(status: 200, body: ["entities": dicts, "count": dicts.count])
    }

    // MARK: - Export

    private func previewExport(sessionID: String) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: sessionID) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid session ID"])
        }
        let descriptor = FetchDescriptor<AISession>(predicate: #Predicate { $0.id == uuid })
        guard let session = try? modelContext.fetch(descriptor).first else {
            return SessionAPIResponse(status: 404, body: ["error": "Session not found"])
        }

        let preview = GitExportService.shared.previewExport(session)

        return SessionAPIResponse(status: 200, body: [
            "sessionId": preview.sessionID.uuidString,
            "title": preview.title,
            "tool": preview.tool,
            "totalTurns": preview.totalTurns,
            "redactionCount": preview.redactionCount,
            "fullyRedactedTurnIDs": preview.fullyRedactedTurnIDs,
            "sensitiveKeywords": preview.sensitiveKeywords,
            "hasProjectPath": preview.hasProjectPath,
            "projectRoot": preview.projectRoot,
            "files": preview.estimatedFiles,
            "branchName": preview.branchName,
        ])
    }

    private func commitExport(sessionID: String, body: [String: Any]?) -> SessionAPIResponse {
        guard let modelContext, let uuid = UUID(uuidString: sessionID) else {
            return SessionAPIResponse(status: 400, body: ["error": "Invalid session ID"])
        }
        let descriptor = FetchDescriptor<AISession>(predicate: #Predicate { $0.id == uuid })
        guard let session = try? modelContext.fetch(descriptor).first else {
            return SessionAPIResponse(status: 404, body: ["error": "Session not found"])
        }

        let projectRoot = body?["projectRoot"] as? String ?? session.project?.gitLocalPath ?? session.projectPath ?? ""
        guard !projectRoot.isEmpty else {
            return SessionAPIResponse(status: 400, body: ["error": "No project root path provided"])
        }

        Task { @MainActor in
            do {
                let result = try await GitExportService.shared.exportSession(session, to: projectRoot)
                apiLogger.info("Export completed: \(result.commitSHA ?? "no commit") (\(result.totalBytes) bytes, \(result.filesIncluded.count) files)")
            } catch {
                apiLogger.error("Export failed: \(error.localizedDescription)")
            }
        }

        return SessionAPIResponse(status: 202, body: [
            "status": "exporting",
            "sessionId": session.id.uuidString,
            "projectRoot": projectRoot,
        ])
    }

    private func getExportConfig() -> SessionAPIResponse {
        let denylistPatterns = UserDefaults.standard.stringArray(forKey: "exportDenylistPatterns") ?? []
        let autoCommit = UserDefaults.standard.bool(forKey: "exportAutoCommit")
        let includeMedia = UserDefaults.standard.bool(forKey: "exportIncludeMedia")
        let includeVectors = UserDefaults.standard.bool(forKey: "exportIncludeVectors")
        let screenshotLinkWindow = UserDefaults.standard.double(forKey: "screenshotLinkWindow")

        return SessionAPIResponse(status: 200, body: [
            "denylistPatterns": denylistPatterns,
            "autoCommit": autoCommit,
            "includeMedia": includeMedia,
            "includeVectors": includeVectors,
            "screenshotLinkWindow": screenshotLinkWindow > 0 ? screenshotLinkWindow : 30.0,
        ])
    }

    private func updateExportConfig(body: [String: Any]?) -> SessionAPIResponse {
        if let patterns = body?["denylistPatterns"] as? [String] {
            UserDefaults.standard.set(patterns, forKey: "exportDenylistPatterns")
        }
        if let auto = body?["autoCommit"] as? Bool {
            UserDefaults.standard.set(auto, forKey: "exportAutoCommit")
        }
        if let media = body?["includeMedia"] as? Bool {
            UserDefaults.standard.set(media, forKey: "exportIncludeMedia")
        }
        if let vectors = body?["includeVectors"] as? Bool {
            UserDefaults.standard.set(vectors, forKey: "exportIncludeVectors")
        }
        if let window = body?["screenshotLinkWindow"] as? Double, window > 0 {
            UserDefaults.standard.set(window, forKey: "screenshotLinkWindow")
        }

        return SessionAPIResponse(status: 200, body: ["status": "updated"])
    }

    // MARK: - Dict helpers

    private func sessionDict(_ session: AISession) -> [String: Any] {
        var dict: [String: Any] = [
            "id": session.id.uuidString,
            "title": session.title,
            "tool": session.tool,
            "startedAt": ISO8601DateFormatter().string(from: session.startedAt),
            "totalTurns": session.totalTurns,
            "totalTokens": session.totalTokensEstimated,
            "isArchived": session.isArchived,
            "tags": session.tags
        ]
        if let ended = session.endedAt { dict["endedAt"] = ISO8601DateFormatter().string(from: ended) }
        if let name = session.projectName { dict["projectName"] = name }
        if let branch = session.branchName { dict["branchName"] = branch }
        if session.prNumber != nil { dict["prNumber"] = session.prNumber ?? 0 }
        return dict
    }

    private func sessionDetailDict(_ session: AISession) -> [String: Any] {
        var dict = sessionDict(session)
        dict["turns"] = session.turns.sorted { $0.turnIndex < $1.turnIndex }.map { turnDict($0) }
        dict["entities"] = session.entityLinks.map { [
            "text": $0.surfaceText,
            "confidence": $0.confidence,
            "kind": $0.entityRecord?.kind.rawValue ?? ""
        ] as [String: Any] }
        dict["summaryAbstract"] = session.summaryAbstract ?? ""
        return dict
    }

    private func turnDict(_ turn: AITurn) -> [String: Any] {
        var dict: [String: Any] = [
            "id": turn.id.uuidString,
            "role": turn.role,
            "content": turn.content,
            "turnIndex": turn.turnIndex,
            "capturedAt": ISO8601DateFormatter().string(from: turn.capturedAt),
            "tokenCount": turn.contentTokenCount,
            "isRedacted": turn.isRedacted
        ]
        if let model = turn.modelID { dict["modelId"] = model }
        if let tool = turn.toolName { dict["toolName"] = tool }
        if !turn.attachedImageIDs.isEmpty { dict["attachedImageIds"] = turn.attachedImageIDs }
        if !turn.attachedURLs.isEmpty { dict["attachedUrls"] = turn.attachedURLs }
        if let dur = turn.durationSeconds { dict["durationSeconds"] = dur }
        return dict
    }

    private func projectDict(_ project: VaporProject) -> [String: Any] {
        var dict: [String: Any] = [
            "id": project.id.uuidString,
            "name": project.name,
            "createdAt": ISO8601DateFormatter().string(from: project.createdAt),
            "lastActiveAt": ISO8601DateFormatter().string(from: project.lastActiveAt),
            "contextItemCount": project.contextItems.count
        ]
        if let notes = project.notes { dict["notes"] = notes }
        if let path = project.gitLocalPath { dict["gitLocalPath"] = path }
        if let remote = project.gitRemoteURL { dict["gitRemoteUrl"] = remote }
        if let branch = project.gitCurrentBranch { dict["branchName"] = branch }
        if let pr = project.detectedPRNumber { dict["prNumber"] = pr }
        if let color = project.colorHex { dict["colorHex"] = color }
        return dict
    }

    private func sessionDuration(_ session: AISession) -> Double {
        let end = session.endedAt ?? Date()
        return end.timeIntervalSince(session.startedAt)
    }
}

extension SessionAPIResponse {
    static func error(_ message: String) -> SessionAPIResponse {
        SessionAPIResponse(status: 500, body: ["error": message])
    }
}

extension String {
    func match(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
