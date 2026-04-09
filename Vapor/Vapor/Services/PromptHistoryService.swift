import Foundation
import SwiftData

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
    
    func fetchRecent(limit: Int = 50) throws -> [PromptRecord] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<PromptRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        var results = try modelContext.fetch(descriptor)
        if results.count > limit {
            results = Array(results.prefix(limit))
        }
        return results
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
