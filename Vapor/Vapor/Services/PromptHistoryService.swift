import Foundation
import SwiftData

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

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func save(_ record: PromptRecord) throws {
        guard let modelContext else { return }
        modelContext.insert(record)
        try modelContext.save()
    }

    @discardableResult
    func saveSnapshot(_ snapshot: PromptHistorySnapshot) throws -> PromptRecord? {
        guard let modelContext else { return nil }

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
        modelContext.delete(record)
        try modelContext.save()
    }

    func toggleFavorite(_ record: PromptRecord) throws {
        record.isFavorite.toggle()
        record.modifiedAt = Date()
        try modelContext?.save()
    }
}
