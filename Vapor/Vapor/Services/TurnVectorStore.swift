import Foundation
import SQLiteVec

struct TurnVectorChunk: Sendable, Equatable {
    let embeddingID: String
    let text: String
    let turnSourceID: String
    let sessionID: String
    let chunkIndex: Int
}

struct TurnVectorMatch: Sendable, Equatable {
    let embeddingID: String
    let distance: Double
    let chunkText: String
    let turnSourceID: String
    let sessionID: String
    let chunkIndex: Int
}

struct TurnVectorStore: Sendable {
    let database: Database
    let turnTableName: String
    let chunksTableName: String
    let dimensions: Int
    let embed: @Sendable (String) async throws -> [Float]

    static func initializeSchema(
        database: Database,
        turnTableName: String,
        chunksTableName: String,
        dimensions: Int
    ) async throws {
        do {
            let tableInfo = try await database.query("PRAGMA table_info(\(turnTableName))")
            if tableInfo.isEmpty {
                try await database.execute(
                    "CREATE VIRTUAL TABLE \(turnTableName) USING vec0(embedding float[\(dimensions)], embedding_id TEXT)"
                )
            }
        } catch {
            try await database.execute(
                "CREATE VIRTUAL TABLE \(turnTableName) USING vec0(embedding float[\(dimensions)], embedding_id TEXT)"
            )
        }

        do {
            let tableInfo = try await database.query("PRAGMA table_info(\(chunksTableName))")
            if tableInfo.isEmpty {
                try await createChunksTable(database: database, chunksTableName: chunksTableName)
            }
        } catch {
            try await createChunksTable(database: database, chunksTableName: chunksTableName)
        }
    }

    func hasTurnVectors(turnSourceID: String) async -> Bool {
        do {
            let rows = try await database.query(
                "SELECT COUNT(*) AS count FROM \(turnTableName) WHERE embedding_id LIKE ?",
                params: ["%:\(turnSourceID):%"]
            )
            if let count = rows.first?["count"] {
                return Self.integerValue(from: count) > 0
            }
            return false
        } catch {
            return false
        }
    }

    func turnChunkCount(sessionID: String) async -> Int {
        do {
            let rows = try await database.query(
                "SELECT COUNT(*) AS count FROM \(chunksTableName) WHERE session_id = ?",
                params: [sessionID]
            )
            if let count = rows.first?["count"] {
                return Self.integerValue(from: count)
            }
            return 0
        } catch {
            return 0
        }
    }

    func turnVectorCount(sessionID: String) async -> Int {
        do {
            let rows = try await database.query(
                "SELECT COUNT(*) AS count FROM \(turnTableName) WHERE embedding_id LIKE ?",
                params: ["turn:\(sessionID):%"]
            )
            if let count = rows.first?["count"] {
                return Self.integerValue(from: count)
            }
            return 0
        } catch {
            return 0
        }
    }

    func removeTurnEmbeddings(turnSourceID: String) async throws {
        let rows = try await database.query(
            "SELECT embedding_id FROM \(turnTableName) WHERE embedding_id LIKE ?",
            params: ["%:\(turnSourceID):%"]
        )
        for row in rows {
            if let id = row["embedding_id"] as? String {
                try await database.execute("DELETE FROM \(turnTableName) WHERE embedding_id = ?", params: [id])
                try await database.execute("DELETE FROM \(chunksTableName) WHERE embedding_id = ?", params: [id])
            }
        }
    }

    func embedAndStore(_ chunks: [TurnVectorChunk]) async throws -> Int {
        var storedCount = 0
        for chunk in chunks {
            let trimmed = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let embedding = try await embed(trimmed)
            try await upsertTurn(embedding: embedding, id: chunk.embeddingID)
            try await database.execute(
                "INSERT OR REPLACE INTO \(chunksTableName) (embedding_id, chunk_text, turn_source_id, session_id, chunk_index) VALUES (?, ?, ?, ?, ?)",
                params: [chunk.embeddingID, trimmed, chunk.turnSourceID, chunk.sessionID, chunk.chunkIndex]
            )
            storedCount += 1
        }
        return storedCount
    }

    func search(matching query: String, sessionID: String? = nil, limit: Int = 20) async throws -> [TurnVectorMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let queryEmbedding = try await embed(trimmed)
        let metadataCount: Int
        let vectorCount: Int
        if let sessionID {
            metadataCount = await turnChunkCount(sessionID: sessionID)
            vectorCount = await turnVectorCount(sessionID: sessionID)
        } else {
            let metadataRows = try await database.query("SELECT COUNT(*) AS count FROM \(chunksTableName)")
            let vectorRows = try await database.query("SELECT COUNT(*) AS count FROM \(turnTableName)")
            metadataCount = metadataRows.first?["count"].map(Self.integerValue(from:)) ?? 0
            vectorCount = vectorRows.first?["count"].map(Self.integerValue(from:)) ?? 0
        }

        guard vectorCount > 0 else { return [] }
        let searchLimit = min(max(metadataCount, vectorCount, limit * 250, 5_000), max(vectorCount, 1))
        let rows: [[String: any Sendable]]
        if let sessionID {
            rows = try await database.query(
                """
                SELECT v.embedding_id, vec_distance_cosine(v.embedding, ?) AS distance
                FROM \(turnTableName) v
                JOIN \(chunksTableName) c ON c.embedding_id = v.embedding_id
                WHERE c.session_id = ?
                ORDER BY distance ASC
                LIMIT ?
                """,
                params: [queryEmbedding, sessionID, searchLimit]
            )
        } else {
            rows = try await database.query(
                "SELECT embedding_id, vec_distance_cosine(embedding, ?) AS distance FROM \(turnTableName) ORDER BY distance ASC LIMIT ?",
                params: [queryEmbedding, searchLimit]
            )
        }

        var matchingIDs: [String] = []
        var distanceMap: [String: Double] = [:]
        for row in rows {
            guard let id = row["embedding_id"] as? String else { continue }
            guard let distance = Self.doubleValue(from: row["distance"]) else { continue }
            matchingIDs.append(id)
            distanceMap[id] = distance
            if matchingIDs.count >= limit { break }
        }

        guard !matchingIDs.isEmpty else { return [] }
        let placeholders = matchingIDs.map { _ in "?" }.joined(separator: ",")
        let chunkRows = try await database.query(
            "SELECT embedding_id, chunk_text, turn_source_id, session_id, chunk_index FROM \(chunksTableName) WHERE embedding_id IN (\(placeholders))",
            params: matchingIDs
        )

        return chunkRows.compactMap { row in
            guard let embeddingID = row["embedding_id"] as? String,
                  let distance = distanceMap[embeddingID] else { return nil }
            return TurnVectorMatch(
                embeddingID: embeddingID,
                distance: distance,
                chunkText: row["chunk_text"] as? String ?? "",
                turnSourceID: row["turn_source_id"] as? String ?? "",
                sessionID: row["session_id"] as? String ?? "",
                chunkIndex: Self.integerValue(from: row["chunk_index"] ?? 0)
            )
        }
        .sorted { $0.distance < $1.distance }
    }

    private static func createChunksTable(database: Database, chunksTableName: String) async throws {
        try await database.execute(
            """
            CREATE TABLE \(chunksTableName) (
                embedding_id TEXT PRIMARY KEY,
                chunk_text TEXT NOT NULL,
                turn_source_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                chunk_index INTEGER NOT NULL
            )
            """
        )
    }

    private func upsertTurn(embedding: [Float], id: String) async throws {
        try await database.execute("DELETE FROM \(turnTableName) WHERE embedding_id = ?", params: [id])
        try await database.execute(
            "INSERT INTO \(turnTableName)(embedding, embedding_id) VALUES (?, ?)",
            params: [embedding, id]
        )
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

    private static func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let double as Double: double
        case let int as Int: Double(int)
        case let int64 as Int64: Double(int64)
        case let int32 as Int32: Double(int32)
        case let string as String: Double(string)
        default: nil
        }
    }
}
