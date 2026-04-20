import Foundation
import SwiftData
import OSLog
import SQLiteVec

nonisolated private let vectorLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Vectorization")
nonisolated private let vectorDatabaseQueue = DispatchQueue(label: "lol.mrl.app.Vapor.sqlitevec", qos: .userInitiated)
nonisolated(unsafe) private var sharedVectorDatabase: Database?

@MainActor
@Observable
final class VectorizationService {
    static let shared = VectorizationService()

    private static let tableName = "vec_items_minilm_l12_multilingual_v2"
    private static let contextEmbeddingPrefix = "ctx:"
    private static let promptEmbeddingPrefix = "prompt:"

    private let embeddingService = MiniLMEmbeddingService()

    private(set) var isInitializing = false
    private(set) var isReady = false
    private(set) var indexedVectorCount = 0
    private(set) var lastError: String?

    private init() {}

    var providerDisplayName: String {
        "MiniLM paraphrase-multilingual-L12-v2"
    }

    func initialize() async {
        guard !isInitializing else { return }
        if isReady {
            await refreshVectorCount()
            return
        }

        isInitializing = true
        defer { isInitializing = false }

        do {
            _ = try await Self.sharedDatabase()
            try await embeddingService.initialize()
            isReady = true
            lastError = nil
            StatusBarService.shared.log("Vectorization model ready", domain: .vectorization, level: .success)
            await refreshVectorCount()
        } catch {
            isReady = false
            lastError = error.localizedDescription
            vectorLogger.error("Failed to initialize vectorization service: \(error.localizedDescription, privacy: .public)")
            StatusBarService.shared.log(
                "Vectorization initialization failed",
                domain: .vectorization,
                level: .error,
                metadata: ["error": error.localizedDescription],
                includeInFooter: true,
                minimumDisplayDuration: .seconds(3)
            )
        }
    }

    func ensureEmbedding(for item: ContextItem, force: Bool = false) async throws -> String? {
        let embeddingID = Self.namespacedEmbeddingID(item.embeddingID, prefix: Self.contextEmbeddingPrefix, fallback: item.id.uuidString)
        if !force,
           let existingID = item.embeddingID,
           existingID.hasPrefix(Self.contextEmbeddingPrefix),
           try await embeddingExists(id: existingID) {
            return existingID
        }

        guard let text = searchableText(for: item) else { return nil }
        let embedding = try await generateEmbedding(for: text)
        try await upsert(embedding: embedding, id: embeddingID)
        item.embeddingID = embeddingID
        StatusBarService.shared.log(
            "Context item vectorized",
            domain: .vectorization,
            level: .success,
            metadata: ["embeddingID": embeddingID, "itemID": item.id.uuidString]
        )
        return embeddingID
    }

    func ensureEmbedding(for record: PromptRecord, force: Bool = false) async throws -> String? {
        let embeddingID = Self.namespacedEmbeddingID(record.embeddingID, prefix: Self.promptEmbeddingPrefix, fallback: record.stableIdentifier)
        if !force,
           let existingID = record.embeddingID,
           existingID.hasPrefix(Self.promptEmbeddingPrefix),
           try await embeddingExists(id: existingID) {
            return existingID
        }

        let text = record.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let embedding = try await generateEmbedding(for: text)
        try await upsert(embedding: embedding, id: embeddingID)
        record.embeddingID = embeddingID
        StatusBarService.shared.log(
            "Prompt record vectorized",
            domain: .vectorization,
            level: .success,
            metadata: ["embeddingID": embeddingID, "recordID": record.stableIdentifier]
        )
        return embeddingID
    }

    func removeEmbedding(id: String) async {
        do {
            let database = try await Self.sharedDatabase()
            for candidateID in Self.candidateEmbeddingIDs(for: id) {
                try await database.execute("DELETE FROM \(Self.tableName) WHERE embedding_id = ?", params: [candidateID])
            }
            await refreshVectorCount()
            StatusBarService.shared.log(
                "Removed vector embedding",
                domain: .vectorization,
                metadata: ["embeddingID": id]
            )
        } catch {
            vectorLogger.error("Failed to delete embedding \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func deleteAllEmbeddings() async throws {
        if !isReady {
            await initialize()
        }
        guard isReady else { throw CocoaError(.fileNoSuchFile) }
        let database = try await Self.sharedDatabase()
        try await database.execute("DELETE FROM \(Self.tableName)")
        await refreshVectorCount()
        StatusBarService.shared.log("Cleared all vector embeddings", domain: .vectorization)
    }

    func backfillMissingPromptEmbeddings(in context: ModelContext) async {
        await initialize()
        guard isReady else { return }
        StatusBarService.shared.log("Backfilling prompt embeddings", domain: .vectorization)

        let descriptor = FetchDescriptor<PromptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            let records = try context.fetch(descriptor)
            var didChange = false
            var didIndexNewEmbeddings = false
            for record in records where record.embeddingID == nil {
                if try await ensureEmbedding(for: record) != nil {
                    didChange = true
                    didIndexNewEmbeddings = true
                }
            }
            if didChange {
                try context.save()
            }
            if didIndexNewEmbeddings {
                await refreshVectorCount()
            }
            StatusBarService.shared.log(
                "Prompt embedding backfill complete",
                domain: .vectorization,
                level: .success,
                metadata: ["records": String(records.count)]
            )
        } catch {
            vectorLogger.error("Failed to backfill prompt embeddings: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            StatusBarService.shared.log(
                "Prompt embedding backfill failed",
                domain: .vectorization,
                level: .error,
                metadata: ["error": error.localizedDescription],
                includeInFooter: true,
                minimumDisplayDuration: .seconds(3)
            )
        }
    }

    func backfillMissingContextEmbeddings(in context: ModelContext) async {
        await initialize()
        guard isReady else { return }
        StatusBarService.shared.log("Backfilling context embeddings", domain: .vectorization)

        let descriptor = FetchDescriptor<ContextItem>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )

        do {
            let items = try context.fetch(descriptor)
            var didChange = false
            var didIndexNewEmbeddings = false
            for item in items where item.embeddingID == nil && item.status == .ready {
                if try await ensureEmbedding(for: item) != nil {
                    didChange = true
                    didIndexNewEmbeddings = true
                }
            }
            if didChange {
                try context.save()
            }
            if didIndexNewEmbeddings {
                await refreshVectorCount()
            }
            StatusBarService.shared.log(
                "Context embedding backfill complete",
                domain: .vectorization,
                level: .success,
                metadata: ["items": String(items.count)]
            )
        } catch {
            vectorLogger.error("Failed to backfill context embeddings: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            StatusBarService.shared.log(
                "Context embedding backfill failed",
                domain: .vectorization,
                level: .error,
                metadata: ["error": error.localizedDescription],
                includeInFooter: true,
                minimumDisplayDuration: .seconds(3)
            )
        }
    }

    func refreshVectorCount() async {
        do {
            let database = try await Self.sharedDatabase()
            let result = try await database.query("SELECT COUNT(*) AS count FROM \(Self.tableName)")
            if let count = result.first?["count"] {
                indexedVectorCount = Self.integerValue(from: count)
            }
        } catch {
            vectorLogger.error("Failed to refresh vector count: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func searchContextItemIDs(matching query: String, limit: Int = 50) async -> [UUID] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            let embedding = try await generateEmbedding(for: trimmed)
            let database = try await Self.sharedDatabase()
            let rows = try await database.query(
                "SELECT embedding_id, distance FROM \(Self.tableName) WHERE embedding_id LIKE ? AND embedding MATCH ? AND k = ?",
                params: ["\(Self.contextEmbeddingPrefix)%", embedding, max(limit * 3, limit)]
            )

            return rows.compactMap { row in
                guard let value = row["embedding_id"] as? String else { return nil }
                return UUID(uuidString: Self.stripEmbeddingPrefix(from: value))
            }
        } catch {
            vectorLogger.error("Semantic context search failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            return []
        }
    }

    private func generateEmbedding(for text: String) async throws -> [Float] {
        await initialize()
        guard isReady else {
            throw MiniLMEmbeddingError.serviceNotReady
        }
        return try await embeddingService.embed(text: text)
    }

    private func upsert(embedding: [Float], id: String) async throws {
        let database = try await Self.sharedDatabase()
        let existed = try await embeddingExists(id: id)
        for candidateID in Self.candidateEmbeddingIDs(for: id) {
            try await database.execute("DELETE FROM \(Self.tableName) WHERE embedding_id = ?", params: [candidateID])
        }
        try await database.execute(
            "INSERT INTO \(Self.tableName)(embedding, embedding_id) VALUES (?, ?)",
            params: [embedding, id]
        )
        StatusBarService.shared.log(
            "Stored vector embedding",
            domain: .vectorization,
            metadata: ["embeddingID": id, "dimensions": String(embedding.count)]
        )
        if !existed {
            indexedVectorCount += 1
        }
    }

    private func embeddingExists(id: String) async throws -> Bool {
        let database = try await Self.sharedDatabase()
        for candidateID in Self.candidateEmbeddingIDs(for: id) {
            let result = try await database.query(
                "SELECT COUNT(*) AS count FROM \(Self.tableName) WHERE embedding_id = ?",
                params: [candidateID]
            )
            if let count = result.first?["count"], Self.integerValue(from: count) > 0 {
                return true
            }
        }
        return false
    }

    private func searchableText(for item: ContextItem) -> String? {
        var segments: [String] = []

        if !item.sourceTitle.isEmpty { segments.append("TITLE: \(item.sourceTitle)") }
        if let siteName = item.sourceSiteName, !siteName.isEmpty { segments.append("SITE: \(siteName)") }
        if !item.sourceURL.isEmpty { segments.append("URL: \(item.sourceURL)") }
        if !item.sortedURLLinks.isEmpty {
            let canonicalURLs = item.sortedURLLinks.map(\.urlDisplayText).filter { !$0.isEmpty }
            if !canonicalURLs.isEmpty {
                segments.append("LINKS: \(canonicalURLs.joined(separator: ", "))")
            }
        }
        if let author = item.sourceAuthor, !author.isEmpty { segments.append("AUTHOR: \(author)") }
        if !item.tags.isEmpty { segments.append("TAGS: \(item.tags.joined(separator: ", "))") }
        if !item.sortedEntityLinks.isEmpty {
            segments.append("ENTITIES: \(item.sortedEntityLinks.map(\.displayText).joined(separator: ", "))")
        }
        if let summary = item.summary?.abstract, !summary.isEmpty { segments.append("SUMMARY: \(summary)") }
        if let text = item.textContent, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(text)
        } else if let markdown = item.markdownContent, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(markdown)
        }

        let joined = segments.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func sharedDatabase() async throws -> Database {
        try await withCheckedThrowingContinuation { continuation in
            vectorDatabaseQueue.async {
                if let database = sharedVectorDatabase {
                    continuation.resume(returning: database)
                    return
                }

                let semaphore = DispatchSemaphore(value: 0)
                var result: Result<Database, Error>?

                Task {
                    do {
                        try SQLiteVec.initialize()

                        let directory = try vectorDatabaseDirectory()
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

                        let databaseURL = directory.appendingPathComponent("vectors.db")
                        let database = try Database(.uri(databaseURL.path))
                        try await initializeSchema(database: database)
                        result = .success(database)
                    } catch {
                        result = .failure(error)
                    }
                    semaphore.signal()
                }

                semaphore.wait()

                switch result {
                case let .success(database):
                    sharedVectorDatabase = database
                    continuation.resume(returning: database)
                case let .failure(error):
                    continuation.resume(throwing: error)
                case .none:
                    continuation.resume(throwing: CocoaError(.coderInvalidValue))
                }
            }
        }
    }

    private static func initializeSchema(database: Database) async throws {
        do {
            let tableInfo = try await database.query("PRAGMA table_info(\(tableName))")
            if tableInfo.isEmpty {
                try await database.execute(
                    "CREATE VIRTUAL TABLE \(tableName) USING vec0(embedding float[\(MiniLMEmbeddingService.dimensions)], embedding_id TEXT)"
                )
            }
        } catch {
            try await database.execute(
                "CREATE VIRTUAL TABLE \(tableName) USING vec0(embedding float[\(MiniLMEmbeddingService.dimensions)], embedding_id TEXT)"
            )
        }
    }

    nonisolated private static func vectorDatabaseDirectory() throws -> URL {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return appSupportURL.appendingPathComponent("Vapor", isDirectory: true)
    }

    private static func integerValue(from value: Any) -> Int {
        switch value {
        case let int as Int: int
        case let int64 as Int64: Int(int64)
        case let int32 as Int32: Int(int32)
        case let double as Double: Int(double)
        case let string as String: Int(string) ?? 0
        default: 0
        }
    }

    private static func namespacedEmbeddingID(_ storedID: String?, prefix: String, fallback: String) -> String {
        let baseID = (storedID?.isEmpty == false ? storedID! : fallback)
        guard !baseID.hasPrefix(prefix) else { return baseID }
        return "\(prefix)\(stripEmbeddingPrefix(from: baseID))"
    }

    private static func candidateEmbeddingIDs(for id: String) -> [String] {
        let stripped = stripEmbeddingPrefix(from: id)
        let candidates = [id, stripped, "\(contextEmbeddingPrefix)\(stripped)", "\(promptEmbeddingPrefix)\(stripped)"]
        return Array(Set(candidates))
    }

    private static func stripEmbeddingPrefix(from id: String) -> String {
        if let colonIndex = id.firstIndex(of: ":") {
            let nextIndex = id.index(after: colonIndex)
            return String(id[nextIndex...])
        }
        return id
    }
}
