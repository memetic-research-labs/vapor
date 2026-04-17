import Foundation
import SwiftData
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "PromptHistory")

struct PromptHistorySnapshot {
    let originalText: String
    let compressedText: String
    let originalTokenCount: Int
    let compressedTokenCount: Int
    let compressionRatio: Double
    let compressorUsed: CompressorType
}

@MainActor
@Observable
final class PromptHistoryService {
    private var modelContext: ModelContext?
    private let vectorizationService = VectorizationService.shared

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        Task { @MainActor in
            await vectorizationService.backfillMissingPromptEmbeddings(in: context)
        }
    }

    func save(_ record: PromptRecord) throws {
        guard let modelContext else { return }
        modelContext.insert(record)
        try modelContext.save()
        scheduleEmbedding(for: record)
    }

    @discardableResult
    func saveSnapshot(_ snapshot: PromptHistorySnapshot) throws -> PromptRecord? {
        guard let modelContext else {
            logger.error("saveSnapshot called but modelContext is nil")
            return nil
        }

        let trimmedOriginal = snapshot.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else { return nil }

        let hash = PromptRecord.makeContentHash(
            originalText: snapshot.originalText,
            compressedText: snapshot.compressedText,
            compressorUsed: snapshot.compressorUsed.rawValue
        )

        let predicate = #Predicate<PromptRecord> { record in
            record.contentHash == hash
        }
        var descriptor = FetchDescriptor<PromptRecord>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.modifiedAt = Date()
            try modelContext.save()
            if existing.embeddingID == nil {
                scheduleEmbedding(for: existing)
            }
            logger.info("Updated existing prompt record (hash: \(String(hash.prefix(8))))")
            return existing
        }

        let record = PromptRecord(
            originalText: snapshot.originalText,
            compressedText: snapshot.compressedText,
            originalTokenCount: snapshot.originalTokenCount,
            compressedTokenCount: snapshot.compressedTokenCount,
            compressionRatio: snapshot.compressionRatio,
            compressorUsed: snapshot.compressorUsed
        )
        modelContext.insert(record)
        try modelContext.save()
        scheduleEmbedding(for: record)
        logger.info("Saved new prompt record (hash: \(String(hash.prefix(8))))")
        return record
    }

    func fetchRecent(limit: Int = 50) throws -> [PromptRecord] {
        guard let modelContext else { return [] }
        var descriptor = FetchDescriptor<PromptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func search(_ query: String) throws -> [PromptRecord] {
        guard let modelContext else { return [] }
        let predicate = #Predicate<PromptRecord> { record in
            record.originalText.localizedStandardContains(query) ||
            record.compressedText.localizedStandardContains(query)
        }
        let descriptor = FetchDescriptor<PromptRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func delete(_ record: PromptRecord) throws {
        guard let modelContext else { return }
        let embeddingID = record.embeddingID
        modelContext.delete(record)
        try modelContext.save()
        if let embeddingID {
            Task { @MainActor in
                await vectorizationService.removeEmbedding(id: embeddingID)
            }
        }
    }

    func toggleFavorite(_ record: PromptRecord) throws {
        record.isFavorite.toggle()
        record.modifiedAt = Date()
        try modelContext?.save()
    }

    private func scheduleEmbedding(for record: PromptRecord) {
        guard modelContext != nil else { return }
        Task { @MainActor in
            do {
                if try await vectorizationService.ensureEmbedding(for: record) != nil {
                    try self.modelContext?.save()
                }
            } catch {
                logger.error("Failed to vectorize prompt record: \(error.localizedDescription)")
            }
        }
    }
}
