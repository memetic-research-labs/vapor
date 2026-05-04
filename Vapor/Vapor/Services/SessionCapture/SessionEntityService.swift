import Foundation
import SwiftData
import OSLog

nonisolated private let sessionEntityLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "SessionEntity")

@MainActor
@Observable
final class SessionEntityService {
    static let shared = SessionEntityService()

    private let entityExtractor = EntityExtractionService()
    private let taggerService = TaggerService()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func extractAndLinkEntities(for turn: AITurn) async {
        guard let modelContext else { return }

        let result = await entityExtractor.extract(from: turn.content)
        let filtered = filterEntities(result.entities)

        for entity in filtered {
            let normalizedText = URLCanonicalizer.normalizeEntityText(entity.text)
            guard !normalizedText.isEmpty else { continue }

            let entityHash = URLCanonicalizer.entityHash(kind: entity.kind, normalizedText: normalizedText)
            let entityRecord = fetchOrCreateEntityRecord(
                entityHash: entityHash,
                kind: entity.kind,
                normalizedText: normalizedText,
                displayText: entity.text,
                seenAt: turn.capturedAt
            )

            if turn.entityLinks.first(where: { $0.entityRecord?.entityHash == entityHash }) == nil {
                let link = AITurnEntityLink(
                    confidence: entity.confidence,
                    surfaceText: entity.text,
                    turn: turn,
                    entityRecord: entityRecord,
                    createdAt: turn.capturedAt
                )
                modelContext.insert(link)
            }
        }

        try? modelContext.save()
    }

    func aggregateEntities(for session: AISession) {
        guard let modelContext else { return }

        let turnEntityHashes = Set(session.turns.flatMap { turn in
            turn.entityLinks.compactMap { $0.entityRecord?.entityHash }
        })

        for entityHash in turnEntityHashes {
            if session.entityLinks.first(where: { $0.entityRecord?.entityHash == entityHash }) != nil {
                continue
            }

            let targetHash = entityHash
            let descriptor = FetchDescriptor<EntityRecord>(predicate: #Predicate { $0.entityHash == targetHash })
            guard let entityRecord = try? modelContext.fetch(descriptor).first else { continue }

            let occurrenceCount = session.turns.filter { turn in
                turn.entityLinks.contains { $0.entityRecord?.entityHash == entityHash }
            }.count

            let link = AISessionEntityLink(
                confidence: min(1.0, Double(occurrenceCount) * 0.3),
                surfaceText: entityRecord.displayText,
                session: session,
                entityRecord: entityRecord,
                createdAt: Date()
            )
            modelContext.insert(link)
        }

        try? modelContext.save()
    }

    func extractDecisions(from session: AISession) async {
        guard let modelContext else { return }
        let turns = session.turns.sorted { $0.turnIndex < $1.turnIndex }
        guard turns.count >= 2 else { return }

        let assistantTurns = turns.filter { $0.role == "assistant" }
        let concatenated = assistantTurns
            .prefix(5)
            .map { $0.content.prefix(300) }
            .joined(separator: "\n---\n")

        guard concatenated.count > 50 else { return }

        let apiKey = UserDefaults.standard.string(forKey: "openRouterApiKey")
        guard let apiKey, !apiKey.isEmpty else { return }

        let prompt = """
        Analyze these AI assistant responses and extract any architectural or design decisions. \
        Return a JSON array of objects with "text" (the decision description) and "confidence" (0-1). \
        If no clear decisions are found, return [].

        Responses:
        \(concatenated)
        """

        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": UserDefaults.standard.string(forKey: "entityExtractionModel") ?? "google/gemini-2.0-flash-001",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1,
            "max_tokens": 500,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstMessage = choices.first?["message"] as? [String: Any],
              let content = firstMessage["content"] as? String else { return }

        guard let jsonStart = content.firstIndex(of: "["),
              let jsonEnd = content.lastIndex(of: "]"),
              jsonEnd > jsonStart else { return }

        let jsonString = String(content[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8),
              let decisions = try? JSONDecoder().decode([DecisionOutput].self, from: jsonData) else { return }

        for decision in decisions {
            let normalizedText = URLCanonicalizer.normalizeEntityText(decision.text)
            guard !normalizedText.isEmpty else { continue }
            let entityHash = URLCanonicalizer.entityHash(kind: .decision, normalizedText: normalizedText)

            let entityRecord = fetchOrCreateEntityRecord(
                entityHash: entityHash,
                kind: .decision,
                normalizedText: normalizedText,
                displayText: decision.text,
                seenAt: Date()
            )

            if session.entityLinks.first(where: { $0.entityRecord?.entityHash == entityHash }) == nil {
                let link = AISessionEntityLink(
                    confidence: decision.confidence,
                    surfaceText: decision.text,
                    session: session,
                    entityRecord: entityRecord,
                    createdAt: Date()
                )
                modelContext.insert(link)
            }
        }

        try? modelContext.save()
    }

    func tagTurn(_ turn: AITurn) -> [String] {
        var tags: [String] = []

        tags.append(turn.role.lowercased())

        if let tool = turn.toolName, !tool.isEmpty {
            tags.append(tool.lowercased())
        }

        if let model = turn.modelID, !model.isEmpty {
            let shortModel = model.components(separatedBy: "/").last ?? model
            tags.append(shortModel.lowercased())
        }

        let entityNames = turn.entityLinks
            .compactMap { $0.entityRecord?.displayText.lowercased() }
            .filter { $0.count >= 3 && $0.count <= 30 }

        for name in entityNames.prefix(4) {
            if !tags.contains(name) { tags.append(name) }
        }

        let keywords = extractKeywords(from: turn.content, limit: max(0, 6 - tags.count))
        for kw in keywords {
            if !tags.contains(kw) { tags.append(kw) }
        }

        return Array(tags.prefix(8))
    }

    func aggregateTags(for session: AISession) {
        var allTags: [String: Int] = [:]

        for turn in session.turns {
            for tag in turn.content.isEmpty ? [turn.role.lowercased()] : [] {
                allTags[tag, default: 0] += 1
            }
        }

        let sorted = allTags
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { $0.key }

        session.tags = Array(sorted)
        try? modelContext?.save()
    }

    func generateSessionTags(for session: AISession) async {
        guard let modelContext else { return }
        let apiKey = UserDefaults.standard.string(forKey: "openRouterApiKey")
        guard let apiKey, !apiKey.isEmpty else { return }

        let turnSummaries = session.turns
            .sorted { $0.turnIndex < $1.turnIndex }
            .prefix(10)
            .map { "\($0.role): \($0.content.prefix(100))" }
            .joined(separator: "\n")

        guard turnSummaries.count > 50 else { return }

        let prompt = """
        Generate 3-5 concise tags (lowercase, single words or short phrases) for this AI coding session. \
        Return a JSON array of strings. Example: ["authentication", "react-hooks", "api-design"]

        Session turns:
        \(turnSummaries)
        """

        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": UserDefaults.standard.string(forKey: "entityExtractionModel") ?? "google/gemini-2.0-flash-001",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1,
            "max_tokens": 100,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstMessage = choices.first?["message"] as? [String: Any],
              let content = firstMessage["content"] as? String else { return }

        guard let jsonStart = content.firstIndex(of: "["),
              let jsonEnd = content.lastIndex(of: "]"),
              jsonEnd > jsonStart else { return }

        let jsonString = String(content[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: jsonData) else { return }

        var existing = session.tags
        for tag in tags.prefix(5) {
            let normalized = tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty && !existing.contains(normalized) {
                existing.append(normalized)
            }
        }
        session.tags = Array(existing.prefix(10))
        try? modelContext.save()
    }

    private func filterEntities(_ entities: [ExtractedEntity]) -> [ExtractedEntity] {
        var seen = Set<String>()
        return entities.compactMap { entity in
            guard entity.kind != .url else { return nil }
            let normalized = URLCanonicalizer.normalizeEntityText(entity.text)
            guard !normalized.isEmpty else { return nil }
            let key = "\(entity.kind.rawValue):\(normalized)"
            guard seen.insert(key).inserted else { return nil }
            return ExtractedEntity(text: entity.text.trimmingCharacters(in: .whitespacesAndNewlines), kind: entity.kind, confidence: entity.confidence)
        }
    }

    private func fetchOrCreateEntityRecord(
        entityHash: String,
        kind: EntityKind,
        normalizedText: String,
        displayText: String,
        seenAt: Date
    ) -> EntityRecord {
        guard let modelContext else {
            fatalError("SessionEntityService: modelContext is nil")
        }
        let targetHash = entityHash
        let descriptor = FetchDescriptor<EntityRecord>(predicate: #Predicate { $0.entityHash == targetHash })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastSeenAt = max(existing.lastSeenAt, seenAt)
            if existing.displayText.count < displayText.count {
                existing.displayText = displayText
            }
            return existing
        }

        let record = EntityRecord(
            entityHash: entityHash,
            kind: kind,
            normalizedText: normalizedText,
            displayText: displayText,
            firstSeenAt: seenAt,
            lastSeenAt: seenAt
        )
        modelContext.insert(record)
        return record
    }

    private let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "can", "shall", "to", "of", "in", "for",
        "on", "with", "at", "by", "from", "as", "into", "through", "and",
        "but", "or", "not", "no", "if", "then", "that", "this", "it",
    ]

    private func extractKeywords(from text: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        var frequencies: [String: Int] = [:]
        for word in words {
            frequencies[word, default: 0] += 1
        }

        return frequencies
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    private struct DecisionOutput: Codable {
        let text: String
        let confidence: Double
    }
}
