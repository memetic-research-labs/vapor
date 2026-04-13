import Foundation
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "OllamaCompressor")

actor OllamaCompressor: Compressor {
    let name = "Ollama (Local)"
    var model: String

    private var port: UInt16

    private var isSmallModel: Bool {
        model.contains(":0.") || model.contains(":1.") || model.contains(":2.") ||
        model.contains(":3.") || model.contains(":4b") || model.contains("mini")
    }

    private var chatEndpoint: String {
        "http://127.0.0.1:\(port)/api/chat"
    }

    private var tagsEndpoint: String {
        "http://127.0.0.1:\(port)/api/tags"
    }

    init(model: String = "qwen2.5:7b", port: UInt16 = 11434) {
        self.model = model
        self.port = port
    }

    var isAvailable: Bool {
        get async {
            guard let url = URL(string: tagsEndpoint) else { return false }
            var request = URLRequest(url: url, timeoutInterval: 3)
            request.httpMethod = "GET"
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
                let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
                return tags.models.contains { $0.name == model || $0.name == "library/\(model)" }
            } catch {
                return false
            }
        }
    }

    func compress(_ text: String) async throws -> CompressedResult {
        let isLargeModel = model.contains("30b") || model.contains("31b")
        let useThinking = isLargeModel
        let systemPrompt = useThinking
            ? "<|think|>\n" + compressionSystemPrompt
            : (isSmallModel ? smallModelSystemPrompt : compressionSystemPrompt)

        let numPredict = max(512, min(4096, text.count / 4 + (useThinking ? 1500 : 0)))
        let timeout = useThinking ? 300.0 : 180.0

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "stream": false,
            "num_predict": numPredict,
            "temperature": 0.1,
            "top_p": 0.9
        ]

        guard let url = URL(string: chatEndpoint) else {
            throw CompressionError.unavailable
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Ollama chat request failed with HTTP \(statusCode)")
            throw CompressionError.apiError("HTTP \(statusCode)")
        }

        let result = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let rawContent = result.message.content
        let strippedContent = stripThinkingBlock(rawContent)
        let compressed = cleanCompressedOutput(strippedContent)

        let originalTokens = await countTokens(text)
        let compressedTokens = await countTokens(compressed)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0

        return CompressedResult(
            text: compressed,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .ollamaLLM
        )
    }

    func setModel(_ model: String) {
        self.model = model
    }

    func setPort(_ port: UInt16) {
        self.port = port
    }

    private func stripThinkingBlock(_ content: String) -> String {
        guard let thinkStart = content.range(of: "<|channel>thought") else {
            return content
        }
        guard let thinkEnd = content.range(of: "<|channel|>", range: thinkStart.upperBound..<content.endIndex) else {
            return content
        }
        let afterThinking = content[thinkEnd.upperBound...]
        return afterThinking.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OllamaChatResponse: Codable {
    let message: OllamaMessage

    struct OllamaMessage: Codable {
        let content: String
    }
}

struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]

    struct OllamaModel: Codable {
        let name: String
        let size: Int64?
        let details: OllamaModelDetails?

        struct OllamaModelDetails: Codable {
            let parameterSize: String?
            let families: [String]?
        }
    }
}
