import XCTest
import SQLiteVec
@testable import Vapor

final class OpenCodeVectorSearchTests: XCTestCase {

    func testTextChunkerCreatesLargerOverlappingChunks() {
        let paragraph = "authentication token refresh search indexing vector database result context "
        let text = String(repeating: paragraph, count: 80)

        let chunks = TextChunker.chunk(text)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertLessThanOrEqual(chunks[0].count, TextChunker.chunkSize)
        XCTAssertGreaterThan(chunks[1].count, TextChunker.overlap)
        XCTAssertTrue(chunks[1].contains("authentication") || chunks[1].contains("token"))
    }

    func testTurnVectorStoreSearchFindsSessionScopedRelevantChunk() async throws {
        try SQLiteVec.initialize()
        let database = try Database(.inMemory)
        let store = TurnVectorStore(
            database: database,
            turnTableName: "test_turn_vectors",
            chunksTableName: "test_turn_chunks",
            dimensions: 4,
            embed: Self.fakeEmbedding(for:)
        )
        try await TurnVectorStore.initializeSchema(
            database: database,
            turnTableName: "test_turn_vectors",
            chunksTableName: "test_turn_chunks",
            dimensions: 4
        )

        let chunks = [
            TurnVectorChunk(
                embeddingID: "turn:session-a:turn-auth:0",
                text: "Implemented authentication token refresh and bearer token validation for the local API search endpoint.",
                turnSourceID: "turn-auth",
                sessionID: "session-a",
                chunkIndex: 0
            ),
            TurnVectorChunk(
                embeddingID: "turn:session-b:turn-quaker:0",
                text: "Discussed Quaker meeting notes, archival documents, and unrelated historical records.",
                turnSourceID: "turn-quaker",
                sessionID: "session-b",
                chunkIndex: 0
            )
        ]

        let storedCount = try await store.embedAndStore(chunks)
        let sessionChunkCount = await store.turnChunkCount(sessionID: "session-a")
        let sessionVectorCount = await store.turnVectorCount(sessionID: "session-a")
        XCTAssertEqual(storedCount, 2)
        XCTAssertEqual(sessionChunkCount, 1)
        XCTAssertEqual(sessionVectorCount, 1)

        let results = try await store.search(matching: "auth token", sessionID: "session-a", limit: 5)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sessionID, "session-a")
        XCTAssertEqual(results.first?.turnSourceID, "turn-auth")
        XCTAssertTrue(results.first?.chunkText.localizedCaseInsensitiveContains("authentication token") == true)
    }

    func testTurnVectorStoreUpsertDoesNotDuplicateMetadataRows() async throws {
        try SQLiteVec.initialize()
        let database = try Database(.inMemory)
        let store = TurnVectorStore(
            database: database,
            turnTableName: "test_turn_vectors_upsert",
            chunksTableName: "test_turn_chunks_upsert",
            dimensions: 4,
            embed: Self.fakeEmbedding(for:)
        )
        try await TurnVectorStore.initializeSchema(
            database: database,
            turnTableName: "test_turn_vectors_upsert",
            chunksTableName: "test_turn_chunks_upsert",
            dimensions: 4
        )

        let chunk = TurnVectorChunk(
            embeddingID: "turn:session-a:turn-auth:0",
            text: "Authentication token validation context should replace itself when indexed again.",
            turnSourceID: "turn-auth",
            sessionID: "session-a",
            chunkIndex: 0
        )

        _ = try await store.embedAndStore([chunk])
        _ = try await store.embedAndStore([chunk])
        let sessionChunkCount = await store.turnChunkCount(sessionID: "session-a")
        let sessionVectorCount = await store.turnVectorCount(sessionID: "session-a")
        let hasVectors = await store.hasTurnVectors(turnSourceID: "turn-auth")

        XCTAssertEqual(sessionChunkCount, 1)
        XCTAssertEqual(sessionVectorCount, 1)
        XCTAssertTrue(hasVectors)
    }

    func testTurnVectorStoreSearchScopesBeforeRanking() async throws {
        try SQLiteVec.initialize()
        let database = try Database(.inMemory)
        let store = TurnVectorStore(
            database: database,
            turnTableName: "test_turn_vectors_scope",
            chunksTableName: "test_turn_chunks_scope",
            dimensions: 4,
            embed: Self.fakeEmbedding(for:)
        )
        try await TurnVectorStore.initializeSchema(
            database: database,
            turnTableName: "test_turn_vectors_scope",
            chunksTableName: "test_turn_chunks_scope",
            dimensions: 4
        )

        var chunks: [TurnVectorChunk] = [
            TurnVectorChunk(
                embeddingID: "turn:session-a:turn-quaker:0",
                text: "Discussed Quaker archive notes and historical records.",
                turnSourceID: "turn-quaker",
                sessionID: "session-a",
                chunkIndex: 0
            )
        ]
        for index in 0..<20 {
            chunks.append(TurnVectorChunk(
                embeddingID: "turn:session-b:turn-auth-\(index):0",
                text: "Authentication bearer token refresh implementation details.",
                turnSourceID: "turn-auth-\(index)",
                sessionID: "session-b",
                chunkIndex: 0
            ))
        }
        _ = try await store.embedAndStore(chunks)

        let results = try await store.search(matching: "authentication token", sessionID: "session-a", limit: 1)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sessionID, "session-a")
        XCTAssertEqual(results.first?.turnSourceID, "turn-quaker")
    }

    func testRealMiniLMFindsDictationCloudFallbackPhrase() async throws {
        try SQLiteVec.initialize()
        let embeddingService = MiniLMEmbeddingService()
        try await embeddingService.initialize()

        let database = try Database(.inMemory)
        let store = TurnVectorStore(
            database: database,
            turnTableName: "test_minilm_turn_vectors",
            chunksTableName: "test_minilm_turn_chunks",
            dimensions: MiniLMEmbeddingService.dimensions,
            embed: { text in try await embeddingService.embed(text: text) }
        )
        try await TurnVectorStore.initializeSchema(
            database: database,
            turnTableName: "test_minilm_turn_vectors",
            chunksTableName: "test_minilm_turn_chunks",
            dimensions: MiniLMEmbeddingService.dimensions
        )

        let chunks = [
            TurnVectorChunk(
                embeddingID: "turn:session-a:turn-dictation:0",
                text: "Dictation no longer requires on-device recognition and can use cloud fallback. The settings UI reports recognizer availability and current route as Automatic.",
                turnSourceID: "turn-dictation",
                sessionID: "session-a",
                chunkIndex: 0
            ),
            TurnVectorChunk(
                embeddingID: "turn:session-a:turn-build:0",
                text: "Let me do a quick build check to catch compiler issues before continuing with the implementation.",
                turnSourceID: "turn-build",
                sessionID: "session-a",
                chunkIndex: 0
            ),
            TurnVectorChunk(
                embeddingID: "turn:session-a:turn-commit:0",
                text: "Do not auto-commit and push. Stage changes only after reviewing the working tree and generated files.",
                turnSourceID: "turn-commit",
                sessionID: "session-a",
                chunkIndex: 0
            )
        ]

        _ = try await store.embedAndStore(chunks)

        let results = try await store.search(
            matching: "dictation on local device vs cloud based",
            sessionID: "session-a",
            limit: 3
        )

        XCTAssertFalse(results.isEmpty)
        let rankedTurnIDs = results.map(\.turnSourceID)
        XCTAssertTrue(
            rankedTurnIDs.prefix(3).contains("turn-dictation"),
            "Expected dictation chunk in top 3, got: \(rankedTurnIDs)"
        )
    }

    private static func fakeEmbedding(for text: String) async throws -> [Float] {
        let lowercased = text.lowercased()
        if lowercased.contains("auth") || lowercased.contains("token") || lowercased.contains("bearer") {
            return [1, 0, 0, 0]
        }
        if lowercased.contains("quaker") || lowercased.contains("archive") || lowercased.contains("historical") {
            return [0, 1, 0, 0]
        }
        return [0, 0, 1, 0]
    }
}
