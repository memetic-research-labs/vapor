import Foundation
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Summarization")

private let chunkThreshold = 100_000
private let chunkSize = 80_000

@MainActor
final class SummarizationService {
    private let orModelKey = "summarizationModel"
    private let orApiKeyKey = "openRouterApiKey"
    private let ollamaModelKey = "ollamaSelectedModel"

    var openRouterModel: String {
        UserDefaults.standard.string(forKey: orModelKey)
            ?? UserDefaults.standard.string(forKey: "entityExtractionModel")
            ?? NERModel.defaultModel
    }

    var ollamaModel: String {
        UserDefaults.standard.string(forKey: ollamaModelKey) ?? "qwen2.5:7b"
    }

    var backend: EntityExtractionBackend {
        if let raw = UserDefaults.standard.string(forKey: "entityExtractionBackend"),
           let val = EntityExtractionBackend(rawValue: raw) {
            return val
        }
        if let apiKey = UserDefaults.standard.string(forKey: orApiKeyKey), !apiKey.isEmpty {
            return .openRouter
        }
        return .ollama
    }

    func summarize(text: String) async -> DocumentSummary? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count > chunkThreshold {
            return await summarizeChunked(text: trimmed)
        }

        return await summarizeSinglePass(text: trimmed)
    }

    private func summarizeSinglePass(text: String) async -> DocumentSummary? {
        let truncated = String(text.prefix(100_000))
        let prompt = buildPrompt()

        if backend == .openRouter {
            return await summarizeViaOpenRouter(text: truncated, prompt: prompt)
        } else {
            return await summarizeViaOllama(text: truncated, prompt: prompt)
        }
    }

    private func summarizeChunked(text: String) async -> DocumentSummary? {
        let chunks = chunkText(text)
        guard !chunks.isEmpty else { return nil }

        logger.info("Summarizing chunked document: \(chunks.count) chunks, \(text.count) chars total")

        var runningSummary = ""

        for (index, chunk) in chunks.enumerated() {
            let userMessage: String
            if runningSummary.isEmpty {
                userMessage = "Summarize this first part of a longer document:\n\n\(chunk)"
            } else {
                userMessage = "Previous summary of the document so far:\n\(runningSummary)\n\nContinue summarizing with this next part:\n\(chunk)"
            }

            let prompt = buildPrompt()
            let result: DocumentSummary?

            if backend == .openRouter {
                result = await summarizeViaOpenRouter(text: userMessage, prompt: prompt)
            } else {
                result = await summarizeViaOllama(text: userMessage, prompt: prompt)
            }

            if let summary = result {
                runningSummary = formatSummaryForContinuation(summary)
                logger.info("Chunk \(index + 1)/\(chunks.count) summarized: \(summary.abstract.prefix(80))")
            } else {
                logger.warning("Chunk \(index + 1) summarization failed, skipping")
            }
        }

        return runningSummary.isEmpty ? nil : DocumentSummary(
            abstract: runningSummary,
            keyPoints: []
        )
    }

    private func chunkText(_ text: String) -> [String] {
        var chunks: [String] = []
        var start = text.startIndex
        let end = text.endIndex

        while start < end {
            let remaining = text.distance(from: start, to: end)
            let targetLen = min(chunkSize, remaining)
            let targetIdx = text.index(start, offsetBy: targetLen)

            var breakIdx = targetIdx
            if targetIdx < end {
                let window = text[targetIdx...]
                if let newlineIdx = window.firstIndex(of: "\n") {
                    let newlineOffset = text.distance(from: targetIdx, to: newlineIdx)
                    if newlineOffset < 2000 {
                        breakIdx = text.index(after: newlineIdx)
                    }
                }
                if breakIdx == targetIdx {
                    let window2 = text[targetIdx...]
                    if let spaceIdx = window2.firstIndex(of: " ") {
                        let spaceOffset = text.distance(from: targetIdx, to: spaceIdx)
                        if spaceOffset < 500 {
                            breakIdx = text.index(after: spaceIdx)
                        }
                    }
                }
            }

            chunks.append(String(text[start..<breakIdx]))
            start = breakIdx
        }

        return chunks
    }

    private func formatSummaryForContinuation(_ summary: DocumentSummary) -> String {
        var parts: [String] = []
        if !summary.abstract.isEmpty {
            parts.append(summary.abstract)
        }
        if !summary.keyPoints.isEmpty {
            parts.append("Key points: " + summary.keyPoints.joined(separator: "; "))
        }
        return parts.joined(separator: "\n")
    }

    private func buildPrompt() -> String {
        """
        You are a document summarizer. Produce a structured summary.

        Return ONLY valid JSON with this exact format:
        {
          "abstract": "2-3 sentence overview of the document",
          "key_points": ["point 1", "point 2", "point 3"]
        }

        Rules:
        - The abstract should capture the main thesis or narrative
        - Key points should be specific, factual, and non-redundant
        - 3-5 key points maximum
        - If the text has no meaningful content, return empty strings and empty array
        - When continuing a summary from a previous part, update and refine rather than repeating
        """
    }

    private func summarizeViaOpenRouter(text: String, prompt: String) async -> DocumentSummary? {
        guard let apiKey = UserDefaults.standard.string(forKey: orApiKeyKey), !apiKey.isEmpty else {
            logger.warning("OpenRouter API key not set, skipping summarization")
            return nil
        }

        let model = openRouterModel
        logger.info("OpenRouter Summary: model=\(model), text=\(text.count) chars")

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/memetic-research-labs-llc/comp-tok-stt", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
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
                logger.error("OpenRouter Summary failed: HTTP \(status) in \(String(format: "%.1f", elapsed))s")
                return nil
            }

            let orResult = try? JSONDecoder().decode(OpenRouterResponse.self, from: data)
            let raw = orResult?.choices.first?.message.content ?? ""

            logger.info("OpenRouter Summary response: \(data.count) bytes, content=\(raw.count) chars in \(String(format: "%.1f", elapsed))s")

            if raw.isEmpty {
                logger.warning("OpenRouter Summary returned empty content")
                return nil
            }
            return parseSummaryJSON(raw)
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("OpenRouter Summary failed: \(error.localizedDescription) after \(String(format: "%.1f", elapsed))s")
            return nil
        }
    }

    private func summarizeViaOllama(text: String, prompt: String) async -> DocumentSummary? {
        let model = ollamaModel
        logger.info("Ollama Summary: model=\(model), text=\(text.count) chars")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            "stream": false,
            "temperature": 0.0,
            "top_p": 0.9,
            "num_predict": 2048
        ]

        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else { return nil }

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
                logger.error("Ollama Summary failed: HTTP \(status) in \(String(format: "%.1f", elapsed))s")
                return nil
            }

            let ollamaResult = try? JSONDecoder().decode(OllamaChatResponse.self, from: data)
            let content = ollamaResult?.message.content ?? ""
            if content.isEmpty {
                logger.warning("Ollama Summary returned empty content")
                return nil
            }
            logger.info("Ollama Summary response: \(data.count) bytes, content=\(content.count) chars in \(String(format: "%.1f", elapsed))s")
            return parseSummaryJSON(content)
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("Ollama Summary failed: \(error.localizedDescription) after \(String(format: "%.1f", elapsed))s")
            return nil
        }
    }

    private func parseSummaryJSON(_ raw: String) -> DocumentSummary? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonStart = cleaned.firstIndex(of: "{"),
              let jsonEnd = cleaned.lastIndex(of: "}"),
              jsonEnd > jsonStart else {
            logger.warning("Summarization returned non-JSON: \(cleaned.prefix(200))")
            return nil
        }

        let jsonStr = String(cleaned[jsonStart...jsonEnd])
        guard let jsonData = jsonStr.data(using: .utf8) else { return nil }

        struct SummaryJSON: Codable {
            let abstract: String
            let keyPoints: [String]

            enum CodingKeys: String, CodingKey {
                case abstract
                case keyPoints = "key_points"
            }
        }

        guard let decoded = try? JSONDecoder().decode(SummaryJSON.self, from: jsonData) else {
            logger.warning("Failed to decode summary JSON: \(jsonStr.prefix(200))")
            return nil
        }

        return DocumentSummary(
            abstract: decoded.abstract,
            keyPoints: decoded.keyPoints
        )
    }
}
