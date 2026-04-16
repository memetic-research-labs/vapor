import Foundation
import NaturalLanguage
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "EntityExtraction")

enum EntityExtractionBackend: String, CaseIterable, Codable {
    case ollama
    case openRouter
    case nlTagger

    var displayName: String {
        switch self {
        case .ollama: "Ollama (Local)"
        case .openRouter: "OpenRouter (Cloud)"
        case .nlTagger: "NLTagger (Built-in)"
        }
    }
}

struct NERModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let priceLabel: String

    static let curatedModels: [NERModel] = [
        NERModel(id: "google/gemma-3n-e4b-it", displayName: "Gemma 3N E4B", priceLabel: "$0.02/M"),
        NERModel(id: "google/gemma-4-26b-a4b-it", displayName: "Gemma 4 26B A4B", priceLabel: "$0.05/M"),
        NERModel(id: "google/gemma-4-31b-it", displayName: "Gemma 4 31B", priceLabel: "$0.10/M"),
        NERModel(id: "meta-llama/llama-3.1-8b-instruct", displayName: "Llama 3.1 8B", priceLabel: "$0.02/M"),
        NERModel(id: "qwen/qwen3-8b", displayName: "Qwen 3 8B", priceLabel: "$0.05/M"),
        NERModel(id: "google/gemma-3-4b-it", displayName: "Gemma 3 4B", priceLabel: "$0.04/M"),
        NERModel(id: "meta-llama/llama-3.2-3b-instruct", displayName: "Llama 3.2 3B", priceLabel: "$0.05/M"),
        NERModel(id: "microsoft/phi-4", displayName: "Phi-4", priceLabel: "$0.07/M"),
        NERModel(id: "cohere/command-r7b-12-2024", displayName: "Command R7B", priceLabel: "$0.04/M"),
        NERModel(id: "mistralai/ministral-3b-2512", displayName: "Ministral 3B", priceLabel: "$0.10/M"),
    ]

    static let defaultModel = "google/gemma-3n-e4b-it"
}

private let nerSystemPrompt = """
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
"""

@MainActor
final class EntityExtractionService {
    private let backendKey = "entityExtractionBackend"
    private let orModelKey = "entityExtractionModel"
    private let orApiKeyKey = "openRouterApiKey"
    private let ollamaModelKey = "ollamaSelectedModel"

    var backend: EntityExtractionBackend {
        get {
            if let raw = UserDefaults.standard.string(forKey: backendKey),
               let val = EntityExtractionBackend(rawValue: raw) {
                return val
            }
            if let apiKey = UserDefaults.standard.string(forKey: orApiKeyKey), !apiKey.isEmpty {
                return .openRouter
            }
            return .ollama
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: backendKey)
        }
    }

    var openRouterModel: String {
        UserDefaults.standard.string(forKey: orModelKey) ?? NERModel.defaultModel
    }

    var ollamaModel: String {
        UserDefaults.standard.string(forKey: ollamaModelKey) ?? "qwen2.5:7b"
    }

    var ollamaPort: UInt16 = 11434

    struct ExtractionResult {
        let entities: [ExtractedEntity]
        let backend: EntityExtractionBackend
    }

    func extract(from text: String) async -> ExtractionResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ExtractionResult(entities: [], backend: .nlTagger)
        }

        logger.info("Extraction backend: \(self.backend.displayName), ollamaModel: \(self.ollamaModel), text length: \(text.count)")

        switch backend {
        case .openRouter:
            let orEntities = await extractViaOpenRouter(from: text)
            if !orEntities.isEmpty {
                logger.info("Extracted \(orEntities.count) entities via OpenRouter")
                return ExtractionResult(entities: orEntities, backend: .openRouter)
            }
            logger.warning("OpenRouter extraction returned empty, falling back to Ollama")

            let ollamaEntities = await extractViaOllama(from: text)
            if !ollamaEntities.isEmpty {
                logger.info("Extracted \(ollamaEntities.count) entities via Ollama (OpenRouter fallback)")
                return ExtractionResult(entities: ollamaEntities, backend: .ollama)
            }
            logger.warning("Ollama extraction returned empty, falling back to NLTagger")
            let nlEntities = extractViaNLTagger(from: text)
            logger.info("Extracted \(nlEntities.count) entities via NLTagger (last resort)")
            return ExtractionResult(entities: nlEntities, backend: .nlTagger)

        case .ollama:
            let ollamaEntities = await extractViaOllama(from: text)
            if !ollamaEntities.isEmpty {
                logger.info("Extracted \(ollamaEntities.count) entities via Ollama")
                return ExtractionResult(entities: ollamaEntities, backend: .ollama)
            }
            logger.warning("Ollama extraction returned empty, falling back to NLTagger")
            let nlEntities = extractViaNLTagger(from: text)
            logger.info("Extracted \(nlEntities.count) entities via NLTagger (fallback)")
            return ExtractionResult(entities: nlEntities, backend: .nlTagger)

        case .nlTagger:
            let nlEntities = extractViaNLTagger(from: text)
            logger.info("Extracted \(nlEntities.count) entities via NLTagger")
            return ExtractionResult(entities: nlEntities, backend: .nlTagger)
        }
    }

    private func extractViaOpenRouter(from text: String) async -> [ExtractedEntity] {
        guard let apiKey = UserDefaults.standard.string(forKey: orApiKeyKey), !apiKey.isEmpty else {
            logger.warning("OpenRouter API key not set, skipping")
            return []
        }

        let truncated = String(text.prefix(8000))
        let model = openRouterModel
        logger.info("OpenRouter NER: model=\(model), truncated text=\(truncated.count) chars")

        let userMessage = "Extract named entities from this text:\n\n\(truncated)"

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/memetic-research-labs-llc/comp-tok-stt", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": nerSystemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.0
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.error("OpenRouter NER failed: HTTP \(status) in \(String(format: "%.1f", elapsed))s")
                return []
            }

            let openRouterResult = try? JSONDecoder().decode(OpenRouterResponse.self, from: data)
            let raw = openRouterResult?.choices.first?.message.content ?? ""

            logger.info("OpenRouter NER response: \(data.count) bytes, content=\(raw.count) chars in \(String(format: "%.1f", elapsed))s")

            if raw.isEmpty {
                logger.warning("OpenRouter NER returned empty content")
                return []
            }

            let jsonStr = extractJSON(from: raw)

            guard !jsonStr.isEmpty,
                  let jsonData = jsonStr.data(using: .utf8) else {
                logger.warning("OpenRouter NER returned non-JSON: \(raw.prefix(200))")
                return []
            }

            let decoded = try? JSONDecoder().decode([NEREntity].self, from: jsonData)
            return decoded?.map { $0.toExtractedEntity() } ?? []
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("OpenRouter NER failed: \(error.localizedDescription) after \(String(format: "%.1f", elapsed))s")
            return []
        }
    }

    private func extractViaOllama(from text: String) async -> [ExtractedEntity] {
        let truncated = String(text.prefix(8000))
        let model = ollamaModel
        logger.info("Ollama NER: model=\(model), port=\(self.ollamaPort), truncated text=\(truncated.count) chars")

        let userMessage = "Extract named entities from this text:\n\n\(truncated)"

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": nerSystemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "stream": false,
            "temperature": 0.0,
            "top_p": 0.9,
            "num_predict": 2048
        ]

        guard let url = URL(string: "http://127.0.0.1:\(self.ollamaPort)/api/chat") else {
            logger.error("Ollama NER: invalid URL for port \(self.ollamaPort)")
            return []
        }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.error("Ollama NER failed: HTTP \(status) in \(String(format: "%.1f", elapsed))s")
                return []
            }

            let ollamaResult = try? JSONDecoder().decode(OllamaChatResponse.self, from: data)
            let content = ollamaResult?.message.content ?? ""

            logger.info("Ollama NER response: \(data.count) bytes, content=\(content.count) chars in \(String(format: "%.1f", elapsed))s")

            if content.isEmpty {
                logger.warning("Ollama NER returned empty content")
                return []
            }

            let jsonStr = extractJSON(from: content)

            guard !jsonStr.isEmpty,
                  let jsonData = jsonStr.data(using: .utf8) else {
                logger.warning("Ollama NER returned non-JSON: \(content.prefix(200))")
                return []
            }

            let decoded = try? JSONDecoder().decode([NEREntity].self, from: jsonData)
            return decoded?.map { $0.toExtractedEntity() } ?? []
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("Ollama NER failed: \(error.localizedDescription) after \(String(format: "%.1f", elapsed))s")
            return []
        }
    }

    private func extractJSON(from raw: String) -> String {
        if let startIdx = raw.firstIndex(of: "["),
           let endIdx = raw.lastIndex(of: "]"),
           endIdx > startIdx {
            return String(raw[startIdx...endIdx])
        }
        return raw
    }

    private struct NEREntity: Codable {
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

    private func extractViaNLTagger(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            guard let tag else { return true }
            let entityText = String(text[tokenRange])
            guard entityText.count > 3 else { return true }

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
