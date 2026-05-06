import Foundation
import SwiftData
import OSLog

private let indexerLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "OpenCodeSessionIndexer")

@Observable
@MainActor
final class OpenCodeSessionIndexer {

    static let shared = OpenCodeSessionIndexer()

    enum IndexState: Equatable, Sendable {
        case idle
        case importing(sourceID: String, current: Int, total: Int)
        case indexing(sourceID: String, current: Int, total: Int)
        case done(sourceID: String, turnCount: Int, chunkCount: Int)
        case error(String)
    }

    enum ImportStatus: Equatable, Sendable {
        case notImported
        case ready(turnCount: Int, chunkCount: Int, vectorCount: Int)
        case dirty(turnCount: Int, chunkCount: Int, vectorCount: Int)
        case needsRepair(turnCount: Int, chunkCount: Int, vectorCount: Int)
    }

    private(set) var state: IndexState = .idle
    private(set) var isProcessing = false
    private(set) var importStatuses: [String: ImportStatus] = [:]

    private var container: ModelContainer?

    private init() {}

    func setModelContainer(_ container: ModelContainer) {
        self.container = container
    }

    func status(for sourceID: String) -> ImportStatus {
        importStatuses[sourceID] ?? .notImported
    }

    func importAndIndex(sourceID: String, vectorizationService: VectorizationService) {
        guard !isProcessing, let container else { return }
        isProcessing = true

        let service = vectorizationService

        Task.detached { @Sendable [container, sourceID, service] in
            let result = await Self.executeImportAndIndex(
                sourceID: sourceID,
                container: container,
                vectorizationService: service,
                onProgress: { newState in
                    Task { @MainActor [weak self] in self?.state = newState }
                }
            )
            await MainActor.run { [weak self] in
                switch result {
                case let .success(turnCount, chunkCount):
                    self?.state = .done(sourceID: sourceID, turnCount: turnCount, chunkCount: chunkCount)
                case let .failure(message):
                    self?.state = .error(message)
                }
                self?.isProcessing = false
                Task { @MainActor [weak self] in
                    await self?.refreshImportState(sourceID: sourceID, vectorizationService: service)
                }
            }
        }
    }

    func checkImportState(sourceID: String, sessionTimeUpdated: Date, vectorizationService: VectorizationService) async -> ImportStatus {
        guard let container else {
            importStatuses[sourceID] = .notImported
            return .notImported
        }

        let bgContext = ModelContext(container)
        var descriptor = FetchDescriptor<AgentConversation>(
            predicate: #Predicate { $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1

        guard let conversation = try? bgContext.fetch(descriptor).first else {
            importStatuses[sourceID] = .notImported
            return .notImported
        }

        let turnDescriptor = FetchDescriptor<AgentTurn>(
            predicate: #Predicate { $0.conversationSourceID == sourceID }
        )
        let turnCount = (try? bgContext.fetch(turnDescriptor).count) ?? 0

        let chunkCount = await vectorizationService.turnChunkCount(sessionID: sourceID)
        let vectorCount = await vectorizationService.turnVectorCount(sessionID: sourceID)

        let status: ImportStatus
        if chunkCount > 0, vectorCount >= chunkCount {
            if let lastImportedAt = conversation.lastImportedAt, lastImportedAt >= sessionTimeUpdated {
                status = .ready(turnCount: turnCount, chunkCount: chunkCount, vectorCount: vectorCount)
            } else {
                status = .dirty(turnCount: turnCount, chunkCount: chunkCount, vectorCount: vectorCount)
            }
        } else if vectorCount > 0 {
            status = .dirty(turnCount: turnCount, chunkCount: chunkCount, vectorCount: vectorCount)
        } else if turnCount > 0 || chunkCount > 0 || vectorCount > 0 {
            status = .needsRepair(turnCount: turnCount, chunkCount: chunkCount, vectorCount: vectorCount)
        } else {
            status = .notImported
        }
        importStatuses[sourceID] = status
        return status
    }

    func refreshImportState(sourceID: String, vectorizationService: VectorizationService) async {
        let sessionTimeUpdated = OpenCodeReader.shared.sessionTimeUpdated(sessionID: sourceID) ?? Date.distantPast
        _ = await checkImportState(
            sourceID: sourceID,
            sessionTimeUpdated: sessionTimeUpdated,
            vectorizationService: vectorizationService
        )
    }

    func repairSearchIndex(sourceID: String, vectorizationService: VectorizationService) {
        guard !isProcessing, let container else { return }
        isProcessing = true
        state = .indexing(sourceID: sourceID, current: 0, total: 0)

        let service = vectorizationService

        Task.detached { @Sendable [container, sourceID, service] in
            do {
                try await service.clearTurnVectors(sessionID: sourceID)
            } catch {
                indexerLogger.error("Failed to clear search vectors for repair: \(error.localizedDescription)")
            }

            let result = await Self.executeRetryEmbedding(
                sourceID: sourceID,
                container: container,
                vectorizationService: service,
                onProgress: { newState in
                    Task { @MainActor [weak self] in self?.state = newState }
                }
            )
            await MainActor.run { [weak self] in
                switch result {
                case let .success(turnCount, chunkCount):
                    self?.state = .done(sourceID: sourceID, turnCount: turnCount, chunkCount: chunkCount)
                case let .failure(message):
                    self?.state = .error(message)
                }
                self?.isProcessing = false
                Task { @MainActor [weak self] in
                    await self?.refreshImportState(sourceID: sourceID, vectorizationService: service)
                }
            }
        }
    }

    func retryEmbedding(sourceID: String, vectorizationService: VectorizationService) {
        guard !isProcessing, let container else { return }
        isProcessing = true

        let service = vectorizationService

        Task.detached { @Sendable [container, sourceID, service] in
            let result = await Self.executeRetryEmbedding(
                sourceID: sourceID,
                container: container,
                vectorizationService: service,
                onProgress: { newState in
                    Task { @MainActor [weak self] in self?.state = newState }
                }
            )
            await MainActor.run { [weak self] in
                switch result {
                case let .success(turnCount, chunkCount):
                    self?.state = .done(sourceID: sourceID, turnCount: turnCount, chunkCount: chunkCount)
                case let .failure(message):
                    self?.state = .error(message)
                }
                self?.isProcessing = false
                Task { @MainActor [weak self] in
                    await self?.refreshImportState(sourceID: sourceID, vectorizationService: service)
                }
            }
        }
    }

    // MARK: - Nonisolated Workers

    private enum ImportResult {
        case success(turnCount: Int, chunkCount: Int)
        case failure(String)
    }

    nonisolated private static func executeImportAndIndex(
        sourceID: String,
        container: ModelContainer,
        vectorizationService: VectorizationService,
        onProgress: @Sendable @escaping (IndexState) -> Void
    ) async -> ImportResult {
        let reader = OpenCodeReader.shared
        let bgContext = ModelContext(container)

        do {
            onProgress(.importing(sourceID: sourceID, current: 0, total: 0))

            let fetchStart = CFAbsoluteTimeGetCurrent()
            let rawSessions = reader.fetchSessionsRaw()
            guard let rawSession = rawSessions.first(where: { $0["id"] == sourceID }) else {
                return .failure("Session not found: \(sourceID)")
            }

            let conv = reader.parseConversationRow(rawSession)
            Self.upsertConversation(conv, in: bgContext)
            try bgContext.save()

            let rawMessages = reader.fetchMessagesRaw(sessionIDs: [sourceID])
            let totalMessages = rawMessages.count
            var importedTurns: [String] = []

            for (index, raw) in rawMessages.enumerated() {
                let turn = reader.parseTurnRow(raw)
                Self.upsertTurn(turn, in: bgContext)
                importedTurns.append(turn.sourceID)
                if index % 200 == 0 {
                    onProgress(.importing(sourceID: sourceID, current: index, total: totalMessages))
                }
            }

            try bgContext.save()

            let rawParts = reader.fetchPartsRaw(sessionIDs: [sourceID])
            for raw in rawParts {
                let content = reader.parseContentRow(raw)
                Self.upsertContent(content, in: bgContext)
            }

            try bgContext.save()

            let fetchElapsed = CFAbsoluteTimeGetCurrent() - fetchStart
            indexerLogger.info("Import phase complete for \(sourceID): \(totalMessages) messages, \(rawParts.count) parts, \(String(format: "%.1f", fetchElapsed))s")

            await vectorizationService.initialize()
            let isReady = await MainActor.run(body: { vectorizationService.isReady })
            guard isReady else {
                indexerLogger.warning("Vectorization service not ready, skipping embedding")
                return .success(turnCount: importedTurns.count, chunkCount: 0)
            }

            let embedStart = CFAbsoluteTimeGetCurrent()
            let textParts = rawParts.filter { ($0["data"] ?? "").contains("\"type\":\"text\"") }
            let totalTurns = importedTurns.count

            onProgress(.indexing(sourceID: sourceID, current: 0, total: totalTurns))

            var totalChunks = 0
            var processed = 0

            for (index, turnSourceID) in importedTurns.enumerated() {
                let alreadyHas = await vectorizationService.hasTurnVectors(turnSourceID: turnSourceID)
                if alreadyHas {
                    processed += 1
                    if processed % 100 == 0 {
                        onProgress(.indexing(sourceID: sourceID, current: index + 1, total: totalTurns))
                    }
                    continue
                }

                let turnParts = textParts.filter { $0["message_id"] == turnSourceID }
                let textContent = turnParts.compactMap { Self.parseTextFromDataJSON($0["data"]) }.joined(separator: "\n\n")
                let hasText = !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                processed += 1

                if hasText {
                    let chunks = TextChunker.chunk(textContent)
                    var batch: [(embeddingID: String, text: String, turnSourceID: String, sessionID: String, chunkIndex: Int)] = []
                    for (chunkIndex, chunk) in chunks.enumerated() {
                        batch.append((
                            embeddingID: "turn:\(sourceID):\(turnSourceID):\(chunkIndex)",
                            text: chunk,
                            turnSourceID: turnSourceID,
                            sessionID: sourceID,
                            chunkIndex: chunkIndex
                        ))
                    }
                    if !batch.isEmpty {
                        let stored = (try? await vectorizationService.embedAndStoreBatch(chunks: batch)) ?? 0
                        totalChunks += stored
                    }
                }

                if processed % 100 == 0 || processed == totalTurns {
                    onProgress(.indexing(sourceID: sourceID, current: index + 1, total: totalTurns))
                }

                if processed % 5 == 0 {
                    await Task.yield()
                }
            }

            let embedElapsed = CFAbsoluteTimeGetCurrent() - embedStart
            indexerLogger.info("Embedding phase complete for \(sourceID): \(totalChunks) chunks in \(String(format: "%.1f", embedElapsed))s")

            let updateContext = ModelContext(container)
            var descriptor = FetchDescriptor<AgentConversation>(
                predicate: #Predicate { $0.sourceID == sourceID }
            )
            descriptor.fetchLimit = 1
            if let existing = try? updateContext.fetch(descriptor).first {
                existing.lastImportedAt = Date()
                try updateContext.save()
            }

            await vectorizationService.refreshVectorCount()

            indexerLogger.info("Import & index complete for \(sourceID): \(importedTurns.count) turns, \(totalChunks) chunks")
            return .success(turnCount: importedTurns.count, chunkCount: totalChunks)

        } catch {
            indexerLogger.error("Import & index failed for \(sourceID): \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    nonisolated private static func executeRetryEmbedding(
        sourceID: String,
        container: ModelContainer,
        vectorizationService: VectorizationService,
        onProgress: @Sendable @escaping (IndexState) -> Void
    ) async -> ImportResult {
        let reader = OpenCodeReader.shared

        do {
            onProgress(.indexing(sourceID: sourceID, current: 0, total: 0))

            let rawMessages = reader.fetchMessagesRaw(sessionIDs: [sourceID])
            let importedTurns = rawMessages.compactMap { $0["id"] }
            let rawParts = reader.fetchPartsRaw(sessionIDs: [sourceID])

            await vectorizationService.initialize()
            let isReady = await MainActor.run(body: { vectorizationService.isReady })
            guard isReady else {
                indexerLogger.warning("Vectorization service not ready during retry")
                return .failure("Vectorization service not ready")
            }

            let textParts = rawParts.filter { ($0["data"] ?? "").contains("\"type\":\"text\"") }
            let totalTurns = importedTurns.count

            onProgress(.indexing(sourceID: sourceID, current: 0, total: totalTurns))

            var totalChunks = 0
            var processed = 0

            for (index, turnSourceID) in importedTurns.enumerated() {
                let turnParts = textParts.filter { $0["message_id"] == turnSourceID }
                let textContent = turnParts.compactMap { Self.parseTextFromDataJSON($0["data"]) }.joined(separator: "\n\n")
                let hasText = !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                processed += 1

                if hasText {
                    await vectorizationService.removeTurnEmbeddings(turnSourceID: turnSourceID)

                    let chunks = TextChunker.chunk(textContent)
                    var batch: [(embeddingID: String, text: String, turnSourceID: String, sessionID: String, chunkIndex: Int)] = []
                    for (chunkIndex, chunk) in chunks.enumerated() {
                        batch.append((
                            embeddingID: "turn:\(sourceID):\(turnSourceID):\(chunkIndex)",
                            text: chunk,
                            turnSourceID: turnSourceID,
                            sessionID: sourceID,
                            chunkIndex: chunkIndex
                        ))
                    }
                    if !batch.isEmpty {
                        let stored = (try? await vectorizationService.embedAndStoreBatch(chunks: batch)) ?? 0
                        totalChunks += stored
                    }
                }

                if processed % 100 == 0 || processed == totalTurns {
                    onProgress(.indexing(sourceID: sourceID, current: index + 1, total: totalTurns))
                }

                if processed % 5 == 0 {
                    await Task.yield()
                }
            }

            let bgContext = ModelContext(container)
            var descriptor = FetchDescriptor<AgentConversation>(
                predicate: #Predicate { $0.sourceID == sourceID }
            )
            descriptor.fetchLimit = 1
            if let existing = try? bgContext.fetch(descriptor).first {
                existing.lastImportedAt = Date()
                try bgContext.save()
            }

            await vectorizationService.refreshVectorCount()

            indexerLogger.info("Retry embedding complete for \(sourceID): \(importedTurns.count) turns, \(totalChunks) chunks")
            return .success(turnCount: importedTurns.count, chunkCount: totalChunks)

        } catch {
            indexerLogger.error("Retry embedding failed for \(sourceID): \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Upsert Helpers

    nonisolated private static func upsertConversation(_ conv: AgentConversation, in context: ModelContext) {
        let sourceID = conv.sourceID
        var descriptor = FetchDescriptor<AgentConversation>(
            predicate: #Predicate { $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.title = conv.title
            existing.timeUpdated = conv.timeUpdated
            existing.summaryFiles = conv.summaryFiles
            existing.summaryAdditions = conv.summaryAdditions
            existing.summaryDeletions = conv.summaryDeletions
            existing.version = conv.version
            existing.lastImportedAt = conv.lastImportedAt
        } else {
            context.insert(conv)
        }
    }

    nonisolated private static func upsertTurn(_ turn: AgentTurn, in context: ModelContext) {
        let sourceID = turn.sourceID
        var descriptor = FetchDescriptor<AgentTurn>(
            predicate: #Predicate { $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.cost = turn.cost
            existing.tokensInput = turn.tokensInput
            existing.tokensOutput = turn.tokensOutput
            existing.tokensReasoning = turn.tokensReasoning
            existing.tokensCacheRead = turn.tokensCacheRead
            existing.tokensCacheWrite = turn.tokensCacheWrite
            existing.finishReason = turn.finishReason
            existing.timeCompleted = turn.timeCompleted
        } else {
            context.insert(turn)
        }
    }

    nonisolated private static func upsertContent(_ content: TurnContent, in context: ModelContext) {
        let sourceID = content.sourceID
        var descriptor = FetchDescriptor<TurnContent>(
            predicate: #Predicate { $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.textContent = content.textContent
            existing.toolStatus = content.toolStatus
            existing.toolOutput = content.toolOutput
        } else {
            context.insert(content)
        }
    }

    // MARK: - Helpers

    nonisolated private static func parseTextFromDataJSON(_ raw: String?) -> String? {
        guard let raw, let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String, !text.isEmpty else { return nil }
        return text
    }

    enum IndexerError: LocalizedError {
        case sessionNotFound(String)

        var errorDescription: String? {
            switch self {
            case .sessionNotFound(let id): "Session not found: \(id)"
            }
        }
    }
}

// MARK: - Text Chunker

enum TextChunker {

    static let chunkSize = 1_400
    static let overlap = 180
    static let wordBoundaryTolerance = 50

    static func chunk(_ text: String) -> [String] {
        let cleaned = normalizeWhitespace(text)
        guard cleaned.count > chunkSize else { return cleaned.isEmpty ? [] : [cleaned] }

        var chunks: [String] = []
        var currentStart = cleaned.startIndex
        var overlapText: Substring = ""

        while currentStart < cleaned.endIndex {
            let endBound = cleaned.index(currentStart, offsetBy: chunkSize, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            let endPosition = optimizedChunkEnd(in: cleaned, from: currentStart, to: endBound)

            var chunk = String(overlapText) + String(cleaned[currentStart..<endPosition])
            chunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { chunks.append(chunk) }

            let overlapStartIndex = cleaned.index(endPosition, offsetBy: -overlap, limitedBy: currentStart) ?? currentStart
            overlapText = extractWordBoundaryOverlap(in: cleaned, from: overlapStartIndex, to: endPosition)

            if endPosition == cleaned.endIndex { break }
            currentStart = cleaned.index(after: endPosition)
        }

        return chunks
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }

    private static func optimizedChunkEnd(in text: String, from start: String.Index, to proposedEnd: String.Index) -> String.Index {
        let limit = text.index(proposedEnd, offsetBy: -wordBoundaryTolerance, limitedBy: start) ?? start
        var searchFrom = text.index(before: proposedEnd)
        while searchFrom > limit {
            let char = text[searchFrom]
            if char.isWhitespace || char == "." || char == "," || char == ";" || char == ":" || char == "!" || char == "?" {
                return text.index(after: searchFrom)
            }
            searchFrom = text.index(before: searchFrom)
        }
        return proposedEnd
    }

    private static func extractWordBoundaryOverlap(in text: String, from start: String.Index, to end: String.Index) -> Substring {
        var searchFrom = start
        let limit = text.index(start, offsetBy: 20, limitedBy: end) ?? end
        while searchFrom < limit {
            if text[searchFrom].isWhitespace {
                return text[searchFrom..<end]
            }
            searchFrom = text.index(after: searchFrom)
        }
        return text[start..<end]
    }
}
