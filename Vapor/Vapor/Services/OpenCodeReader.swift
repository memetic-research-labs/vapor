import Foundation
import OSLog
import CSQLiteVec

private let openCodeLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "OpenCodeReader")

struct OpenCodeSession: Identifiable, Sendable {
    let id: String
    let projectID: String
    let directory: String
    let title: String
    let slug: String
    let messageCount: Int
    let timeCreated: Date
    let timeUpdated: Date
    let version: String?
    let summaryFiles: Int?
    let summaryAdditions: Int?
    let summaryDeletions: Int?

    var projectDisplayName: String {
        (directory as NSString).lastPathComponent
    }
}

struct OpenCodeMessage: Identifiable, Sendable {
    let id: String
    let sessionID: String
    let role: String
    let agent: String?
    let mode: String?
    let modelID: String?
    let providerID: String?
    let cost: Double?
    let tokens: TokenInfo?
    let pathCwd: String?
    let pathRoot: String?
    let timeCreated: Date
    let timeCompleted: Date?
    let finishReason: String?
}

struct TokenInfo: Sendable {
    let total: Int
    let input: Int
    let output: Int
    let reasoning: Int
    let cacheRead: Int
    let cacheWrite: Int
}

enum OpenCodePartKind: Sendable {
    case text(String)
    case tool(name: String, callID: String?, status: String, input: String?, output: String?, title: String?)
    case reasoning(String)
    case stepStart(String)
    case stepFinish(reason: String?, cost: Double?, tokens: TokenInfo?)
    case patch(String, files: [String])
    case file(mime: String, filename: String?, url: String?)
    case compaction(auto: Bool)
    case unknown
}

struct OpenCodePart: Identifiable, Sendable {
    let id: String
    let messageID: String
    let sessionID: String
    let kind: OpenCodePartKind
    let timeCreated: Date
}

final class OpenCodeReader: Sendable {

    static let shared = OpenCodeReader()

    private static let knownPaths: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".local/share/opencode/opencode.db"),
            home.appendingPathComponent("Library/Application Support/opencode/opencode.db")
        ]
    }()

    private let _databaseURL: URL?
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "lol.mrl.app.Vapor.opencode-reader", qos: .userInitiated)

    private init() {
        var found: URL?
        for path in Self.knownPaths {
            if FileManager.default.isReadableFile(atPath: path.path) {
                found = path
                openCodeLogger.info("Found opencode.db at: \(path.path)")
                break
            } else {
                openCodeLogger.info("No opencode.db at: \(path.path)")
            }
        }
        if found == nil {
            openCodeLogger.warning("No opencode.db found in any known path")
        }
        _databaseURL = found

        if let path = found?.path {
            openDatabase(at: path)
        }
    }

    deinit {
        let ptr = db
        db = nil
        if let ptr { sqlite3_close(ptr) }
    }

    var isAvailable: Bool {
        _databaseURL != nil && db != nil
    }

    var databasePath: String? {
        _databaseURL?.path
    }

    func resolveDatabasePath() -> String? {
        _databaseURL?.path
    }

    // MARK: - Raw Data Extraction (for indexer)

    func fetchSessionsRaw(sinceEpoch: Int = 0) -> [[String: String]] {
        let whereClause = sinceEpoch > 0 ? "WHERE time_updated > \(sinceEpoch)" : ""
        let sql = """
            SELECT id, project_id, parent_id, directory, title, slug,
                   version, time_created, time_updated,
                   summary_files, summary_additions, summary_deletions
            FROM session
            \(whereClause)
            ORDER BY time_updated DESC
            """
        return query(sql)
    }

    func fetchMessagesRaw(sessionIDs: [String], sinceEpoch: Int = 0) -> [[String: String]] {
        guard !sessionIDs.isEmpty else { return [] }
        let ids = sessionIDs.map { "'\(sqlEscape($0))'" }.joined(separator: ",")
        let timeClause = sinceEpoch > 0 ? "AND time_updated > \(sinceEpoch)" : ""
        let sql = """
            SELECT id, session_id, data, time_created, time_updated
            FROM message
            WHERE session_id IN (\(ids))
            \(timeClause)
            ORDER BY time_created ASC
            """
        return query(sql)
    }

    func fetchPartsRaw(sessionIDs: [String], sinceEpoch: Int = 0) -> [[String: String]] {
        guard !sessionIDs.isEmpty else { return [] }
        let ids = sessionIDs.map { "'\(sqlEscape($0))'" }.joined(separator: ",")
        let timeClause = sinceEpoch > 0 ? "AND time_updated > \(sinceEpoch)" : ""
        let sql = """
            SELECT id, message_id, session_id, data, time_created
            FROM part
            WHERE session_id IN (\(ids))
            \(timeClause)
            ORDER BY time_created ASC
            """
        return query(sql)
    }

    func parseConversationRow(_ row: [String: String]) -> AgentConversation {
        AgentConversation(
            sourceID: row["id"] ?? "",
            source: "opencode",
            parentSourceID: row["parent_id"].flatMap { $0.isEmpty ? nil : $0 },
            projectSourceID: row["project_id"],
            directory: row["directory"] ?? "",
            title: row["title"] ?? "",
            slug: row["slug"],
            version: row["version"],
            summaryFiles: row["summary_files"].flatMap { Int($0) },
            summaryAdditions: row["summary_additions"].flatMap { Int($0) },
            summaryDeletions: row["summary_deletions"].flatMap { Int($0) },
            timeCreated: parseEpochMs(row["time_created"]),
            timeUpdated: parseEpochMs(row["time_updated"])
        )
    }

    func parseTurnRow(_ row: [String: String]) -> AgentTurn {
        let data = parseDataJSON(row["data"])
        return AgentTurn(
            sourceID: row["id"] ?? "",
            source: "opencode",
            conversationSourceID: row["session_id"] ?? "",
            role: data["role"] as? String ?? "unknown",
            agent: data["agent"] as? String,
            mode: data["mode"] as? String,
            modelID: data["modelID"] as? String ?? parseNestedString(data["model"], key: "modelID"),
            providerID: data["providerID"] as? String ?? parseNestedString(data["model"], key: "providerID"),
            cost: data["cost"] as? Double,
            tokensInput: parseNestedInt(data["tokens"], key: "input"),
            tokensOutput: parseNestedInt(data["tokens"], key: "output"),
            tokensReasoning: parseNestedInt(data["tokens"], key: "reasoning"),
            tokensCacheRead: parseNestedDoubleNested(data["tokens"], inner: "cache", key: "read").flatMap { Int($0) },
            tokensCacheWrite: parseNestedDoubleNested(data["tokens"], inner: "cache", key: "write").flatMap { Int($0) },
            pathCwd: (data["path"] as? [String: Any])?["cwd"] as? String,
            pathRoot: (data["path"] as? [String: Any])?["root"] as? String,
            finishReason: data["finish"] as? String,
            timeCreated: parseEpochMs(row["time_created"]),
            timeCompleted: parseCompletedTime(data["time"] as? [String: Any])
        )
    }

    func parseContentRow(_ row: [String: String]) -> TurnContent {
        let data = parseDataJSON(row["data"])
        let partType = data["type"] as? String ?? ""

        switch partType {
        case "text":
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.text.rawValue,
                textContent: data["text"] as? String,
                timeCreated: parseEpochMs(row["time_created"])
            )
        case "tool":
            let state = data["state"] as? [String: Any] ?? [:]
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.tool.rawValue,
                toolName: data["tool"] as? String,
                toolStatus: state["status"] as? String,
                toolTitle: data["title"] as? String ?? state["title"] as? String,
                toolInput: stringifyToolInput(state["input"]),
                toolOutput: state["output"] as? String,
                timeCreated: parseEpochMs(row["time_created"])
            )
        case "reasoning":
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.reasoning.rawValue,
                textContent: data["text"] as? String,
                timeCreated: parseEpochMs(row["time_created"])
            )
        case "step-start":
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.stepStart.rawValue,
                timeCreated: parseEpochMs(row["time_created"])
            )
        case "step-finish":
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.stepFinish.rawValue,
                timeCreated: parseEpochMs(row["time_created"])
            )
        case "patch":
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.patch.rawValue,
                patchFiles: data["files"] as? [String],
                timeCreated: parseEpochMs(row["time_created"])
            )
        case "file":
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.file.rawValue,
                fileMime: data["mime"] as? String,
                fileFilename: data["filename"] as? String,
                fileURL: data["url"] as? String,
                timeCreated: parseEpochMs(row["time_created"])
            )
        case "compaction":
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.compaction.rawValue,
                timeCreated: parseEpochMs(row["time_created"])
            )
        default:
            return TurnContent(
                sourceID: row["id"] ?? "",
                source: "opencode",
                turnSourceID: row["message_id"] ?? "",
                conversationSourceID: row["session_id"] ?? "",
                kind: TurnContentKind.unknown.rawValue,
                timeCreated: parseEpochMs(row["time_created"])
            )
        }
    }

    // MARK: - Session Queries (sidebar browsing)

    func fetchSessions(limit: Int = 50, offset: Int = 0, directory: String? = nil) -> [OpenCodeSession] {
        let whereClause = directory.map { "WHERE s.directory = '\(sqlEscape($0))'" } ?? ""
        let sql = """
            SELECT s.id, s.project_id, s.directory, s.title, s.slug,
                   s.version, s.time_created, s.time_updated,
                   s.summary_files, s.summary_additions, s.summary_deletions,
                   (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id) as message_count
            FROM session s
            \(whereClause)
            ORDER BY s.time_updated DESC
            LIMIT \(limit) OFFSET \(offset)
            """

        return query(sql).map { row in
            OpenCodeSession(
                id: row["id"] ?? "",
                projectID: row["project_id"] ?? "",
                directory: row["directory"] ?? "",
                title: row["title"] ?? "",
                slug: row["slug"] ?? "",
                messageCount: Int(row["message_count"] ?? "0") ?? 0,
                timeCreated: parseEpochMs(row["time_created"]),
                timeUpdated: parseEpochMs(row["time_updated"]),
                version: row["version"],
                summaryFiles: row["summary_files"].flatMap { Int($0) },
                summaryAdditions: row["summary_additions"].flatMap { Int($0) },
                summaryDeletions: row["summary_deletions"].flatMap { Int($0) }
            )
        }
    }

    func fetchDirectories() -> [(directory: String, sessionCount: Int)] {
        let sql = """
            SELECT directory, COUNT(*) as cnt
            FROM session
            GROUP BY directory
            ORDER BY cnt DESC
            """

        return query(sql).map { row in
            (directory: row["directory"] ?? "", sessionCount: Int(row["cnt"] ?? "0") ?? 0)
        }
    }

    func fetchMessages(sessionID: String, limit: Int = 100) -> [OpenCodeMessage] {
        let sql = """
            SELECT id, session_id, data, time_created, time_updated
            FROM message
            WHERE session_id = '\(sqlEscape(sessionID))'
            ORDER BY time_created ASC
            LIMIT \(limit)
            """

        return query(sql).map { parseMessage(row: $0) }
    }

    func fetchAllMessages(sessionID: String) -> [OpenCodeMessage] {
        let sql = """
            SELECT id, session_id, data, time_created, time_updated
            FROM message
            WHERE session_id = '\(sqlEscape(sessionID))'
            ORDER BY time_created ASC
            """

        return query(sql).map { parseMessage(row: $0) }
    }

    func fetchParts(messageID: String) -> [OpenCodePart] {
        let sql = """
            SELECT id, message_id, session_id, data, time_created
            FROM part
            WHERE message_id = '\(sqlEscape(messageID))'
            ORDER BY time_created ASC
            """

        return query(sql).map { parsePart(row: $0) }
    }

    func fetchAllParts(sessionID: String) -> [OpenCodePart] {
        let sql = """
            SELECT p.id, p.message_id, p.session_id, p.data, p.time_created
            FROM part p
            WHERE p.session_id = '\(sqlEscape(sessionID))'
            ORDER BY p.time_created ASC
            """

        return query(sql).map { parsePart(row: $0) }
    }

    func messageCount(sessionID: String) -> Int {
        let sql = "SELECT COUNT(*) as cnt FROM message WHERE session_id = '\(sqlEscape(sessionID))'"
        let rows = query(sql)
        return Int(rows.first?["cnt"] ?? "0") ?? 0
    }

    func totalSessionCount() -> Int {
        let sql = "SELECT COUNT(*) as cnt FROM session"
        let rows = query(sql)
        return Int(rows.first?["cnt"] ?? "0") ?? 0
    }

    func totalDirectoryCount() -> Int {
        let sql = "SELECT COUNT(DISTINCT directory) as cnt FROM session"
        let rows = query(sql)
        return Int(rows.first?["cnt"] ?? "0") ?? 0
    }

    func sessionTimeUpdated(sessionID: String) -> Date? {
        let sql = "SELECT time_updated FROM session WHERE id = '\(sqlEscape(sessionID))'"
        let rows = query(sql)
        guard let value = rows.first?["time_updated"] else { return nil }
        let epochMs = Double(value)
        guard let epochMs else { return nil }
        return Date(timeIntervalSince1970: epochMs / 1000.0)
    }

    // MARK: - Private

    private func openDatabase(at path: String) {
        var ptr: OpaquePointer?
        let rc = sqlite3_open_v2(path, &ptr, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK else {
            openCodeLogger.error("Failed to open opencode.db: \(String(cString: sqlite3_errmsg(ptr)))")
            return
        }
        sqlite3_busy_timeout(ptr, 5000)
        self.db = ptr
        openCodeLogger.info("Opened opencode.db (read-only, 5s busy timeout)")
    }

    private func query(_ sql: String) -> [[String: String]] {
        queue.sync { () -> [[String: String]] in
            guard let db else { return [] }

            var statement: OpaquePointer?
            let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            guard rc == SQLITE_OK, let statement else {
                let msg = String(cString: sqlite3_errmsg(db))
                openCodeLogger.error("SQL prepare failed: \(msg) — sql: \(sql.prefix(200))")
                return []
            }
            defer { sqlite3_finalize(statement) }

            let colCount = sqlite3_column_count(statement)
            var results: [[String: String]] = []
            results.reserveCapacity(64)

            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: String] = [:]
                row.reserveCapacity(Int(colCount))
                for col in 0..<Int(colCount) {
                    let col32 = Int32(col)
                    let name = String(cString: sqlite3_column_name(statement, col32))
                    let type = sqlite3_column_type(statement, col32)
                    switch type {
                    case SQLITE_NULL:
                        row[name] = ""
                    case SQLITE_INTEGER:
                        row[name] = String(sqlite3_column_int64(statement, col32))
                    case SQLITE_FLOAT:
                        row[name] = String(sqlite3_column_double(statement, col32))
                    default:
                        if let text = sqlite3_column_text(statement, col32) {
                            row[name] = String(cString: text)
                        } else {
                            row[name] = ""
                        }
                    }
                }
                results.append(row)
            }

            return results
        }
    }

    private func parseMessage(row: [String: String]) -> OpenCodeMessage {
        let data = parseDataJSON(row["data"])

        return OpenCodeMessage(
            id: row["id"] ?? "",
            sessionID: row["session_id"] ?? "",
            role: data["role"] as? String ?? "unknown",
            agent: data["agent"] as? String,
            mode: data["mode"] as? String,
            modelID: data["modelID"] as? String ?? (data["model"] as? [String: Any])?["modelID"] as? String,
            providerID: data["providerID"] as? String ?? (data["model"] as? [String: Any])?["providerID"] as? String,
            cost: data["cost"] as? Double,
            tokens: parseTokens(data["tokens"] as? [String: Any]),
            pathCwd: (data["path"] as? [String: Any])?["cwd"] as? String,
            pathRoot: (data["path"] as? [String: Any])?["root"] as? String,
            timeCreated: parseEpochMs(row["time_created"]),
            timeCompleted: parseCompletedTime(data["time"] as? [String: Any]),
            finishReason: data["finish"] as? String
        )
    }

    private func parsePart(row: [String: String]) -> OpenCodePart {
        let data = parseDataJSON(row["data"])
        let partType = data["type"] as? String ?? ""

        let kind: OpenCodePartKind
        switch partType {
        case "text":
            kind = .text(data["text"] as? String ?? "")
        case "tool":
            let state = data["state"] as? [String: Any] ?? [:]
            let input = stringifyToolInput(state["input"])
            let output = (state["output"] as? String) ?? ""
            kind = .tool(
                name: data["tool"] as? String ?? "unknown",
                callID: data["callID"] as? String,
                status: state["status"] as? String ?? "unknown",
                input: input,
                output: output,
                title: data["title"] as? String ?? state["title"] as? String
            )
        case "reasoning":
            kind = .reasoning(data["text"] as? String ?? "")
        case "step-start":
            kind = .stepStart(data["snapshot"] as? String ?? "")
        case "step-finish":
            kind = .stepFinish(
                reason: data["reason"] as? String,
                cost: data["cost"] as? Double,
                tokens: parseTokens(data["tokens"] as? [String: Any])
            )
        case "patch":
            let hash = data["hash"] as? String ?? ""
            let files = data["files"] as? [String] ?? []
            kind = .patch(hash, files: files)
        case "file":
            kind = .file(
                mime: data["mime"] as? String ?? "",
                filename: data["filename"] as? String,
                url: data["url"] as? String
            )
        case "compaction":
            kind = .compaction(auto: data["auto"] as? Bool ?? false)
        default:
            kind = .unknown
        }

        return OpenCodePart(
            id: row["id"] ?? "",
            messageID: row["message_id"] ?? "",
            sessionID: row["session_id"] ?? "",
            kind: kind,
            timeCreated: parseEpochMs(row["time_created"])
        )
    }

    private func parseDataJSON(_ raw: String?) -> [String: Any] {
        guard let raw, let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func parseTokens(_ dict: [String: Any]?) -> TokenInfo? {
        guard let dict else { return nil }
        let cache = dict["cache"] as? [String: Any] ?? [:]
        return TokenInfo(
            total: dict["total"] as? Int ?? 0,
            input: dict["input"] as? Int ?? 0,
            output: dict["output"] as? Int ?? 0,
            reasoning: dict["reasoning"] as? Int ?? 0,
            cacheRead: cache["read"] as? Int ?? 0,
            cacheWrite: cache["write"] as? Int ?? 0
        )
    }

    private func parseCompletedTime(_ timeDict: [String: Any]?) -> Date? {
        guard let completed = timeDict?["completed"] as? Int else { return nil }
        return Date(timeIntervalSince1970: Double(completed) / 1000.0)
    }

    private func parseEpochMs(_ value: String?) -> Date {
        guard let value, let epochMs = Double(value) else { return .distantPast }
        return Date(timeIntervalSince1970: epochMs / 1000.0)
    }

    private func parseNestedString(_ parent: Any?, key: String) -> String? {
        (parent as? [String: Any])?[key] as? String
    }

    private func parseNestedInt(_ parent: Any?, key: String) -> Int? {
        (parent as? [String: Any])?[key] as? Int
    }

    private func parseNestedDoubleNested(_ parent: Any?, inner: String, key: String) -> Double? {
        guard let outer = parent as? [String: Any],
              let innerDict = outer[inner] as? [String: Any] else { return nil }
        return innerDict[key] as? Double
    }

    private func stringifyToolInput(_ input: Any?) -> String? {
        guard let input else { return nil }
        if let str = input as? String { return str }
        if let dict = input as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        if let arr = input as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return String(describing: input)
    }

    private func sqlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
