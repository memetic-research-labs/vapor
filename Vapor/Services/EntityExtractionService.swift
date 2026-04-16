import Foundation
import NaturalLanguage
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "EntityExtraction")

enum EntityExtractionBackend {
    case ollama
    case nlTagger
}

@MainActor
final class EntityExtractionService {
    var backend: EntityExtractionBackend = .ollama
    var ollamaPort: UInt16 = 11434
    var ollamaModel: String = "qwen2.5:7b"

    func extract(from text: String) async -> [ExtractedEntity] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        if backend == .ollama {
            let ollamaEntities = await extractViaOllama(from: text)
            if !ollamaEntities.isEmpty {
                return ollamaEntities
            }
            logger.warning("Ollama extraction returned empty, falling back to NLTagger")
        }

        return extractViaNLTagger(from: text)
    }

    // MARK: - Ollama-based extraction

    private func extractViaOllama(from text: String) async -> [ExtractedEntity] {
        let truncated = String(text.prefix(8000))
        let systemPrompt = """
You are a named entity recognition system. Extract ALL named entities from the text.

Return ONLY a JSON array. Each entity must have:
- "text": the exact entity text as it appears
- "kind": one of: "person", "organization", "location", "date", "url", "number", "code", "concept"
- "confidence": 0.0 to 1.0

Rules:
- Only extract real named entities (people names, company names, place names, specific dates, URLs)
- Do NOT extract common words, verbs, adjectives, or generic terms
- A "person" must be an actual human name (e.g. "John Smith"), not a role like "spokesman"
- An "organization" must be a specific company, government body, or institution
- A "location" must be a specific geographic place (city, country, region)
- Dates should be in their natural form (e.g. "April 14, 2026")
- Include code identifiers (function names, class names, API endpoints) as "code"
- Include specific URLs as "url"
- If no entities are found, return an empty array []

Examples:
- "John Smith visited Dublin on Monday" → [{"text":"John Smith","kind":"person","confidence":0.95},{"text":"Dublin","kind":"location","confidence":0.9},{"text":"Monday","kind":"date","confidence":0.5}]
"""

        let userMessage = "Extract named entities from this text:\n\n\(truncated)"

        let body: [String: Any] = [
            "model": ollamaModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "stream": false,
            "temperature": 0.0,
            "top_p": 0.9,
            "num_predict": 2048
        ]

        guard let url = URL(string: "http://127.0.0.1:\(ollamaPort)/api/chat") else {
            return []
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let httpBody = request.httpBody else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.error("Ollama entity extraction returned status \(response)")
                return []
            }

            let raw = String(data: data, encoding: .utf8) ?? ""
            let jsonStr = extractJSON(from: raw)

            guard !jsonStr.isEmpty,
                  let jsonData = jsonStr.data(using: .utf8) else {
                logger.warning("Ollama entity extraction returned non-JSON: \(raw.prefix(200))")
                return []
            }

            let decoded = try? JSONDecoder().decode([OllamaEntity].self, from: jsonData)
            return decoded?.map { $0.toExtractedEntity() } ?? []
        } catch {
            logger.error("Ollama entity extraction failed: \(error.localizedDescription)")
            return []
        }
    }

    private func extractJSON(from raw: String) -> String {
        if let range = raw.range(of: "[", options: .literal),
           let endRange = raw.lastIndex(of: "]", options: .literal),
           endRange > range.upperBound {
            return String(raw[range.lowerBound..<endRange.upperBound + 1])
        }
        return raw
    }

    private struct OllamaEntity: Codable {
        let text: String
        let kind: String
        let confidence: Double

        func toExtractedEntity() -> ExtractedEntity {
            ExtractedEntity(
                text: text,
                kind: EntityKind(rawValue: kind) ?? .concept,
                confidence: confidence
            )
        }
    }

    // MARK: - NLTagger fallback (strict, only proper nouns)

    private func extractViaNLTagger(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            guard let tag else { return true }
            let entityText = String(text[tokenRange])
            guard entityText.count > 2 else { return true }

            let kind = mapNLTagToEntityKind(tag)
            guard kind != .concept else { return true }

            let entity = ExtractedEntity(
                text: entityText,
                kind: kind,
                confidence: 0.8
            )
            entities.append(entity)
            return true
        }

        let codeEntities = extractCodeEntities(from: text)
        for codeEntity in codeEntities {
            if !entities.contains(where: { $0.text.lowercased() == codeEntity.text.lowercased() }) {
                entities.append(codeEntity)
            }
        }

        return entities
    }

    private func mapNLTagToEntityKind(_ tag: NLTag) -> EntityKind {
        switch tag {
        case .personalName: return .person
        case .organizationName: return .organization
        case .placeName: return .location
        default: return .concept
        }
    }

    private func extractCodeEntities(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        let urlPattern = #/https?:\/\/[^\s<>"]+/#
        for match in text.matches(of: urlPattern) {
            let url = String(match.output)
            if !entities.contains(where: { $0.text == url && $0.kind == .url }) {
                entities.append(ExtractedEntity(text: url, kind: .url, confidence: 0.95))
            }
        }

        let datePattern = #/\b\d{4}[-/]\d{2}[-/]\d{2}\b/#
        for match in text.matches(of: datePattern) {
            entities.append(ExtractedEntity(text: String(match.output), kind: .date, confidence: 0.85))
        }

        return entities
    }
}
