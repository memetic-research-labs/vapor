import Foundation

actor OpenRouterCompressor: Compressor {
    let name = "OpenRouter"
    let apiKey: String
    let model: String

    var isAvailable: Bool {
        get async { !apiKey.isEmpty }
    }

    init(apiKey: String, model: String = "glm-5") {
        self.apiKey = apiKey
        self.model = model
    }

    func compress(_ text: String) async throws -> CompressedResult {
        guard !apiKey.isEmpty else {
            throw CompressionError.unavailable
        }

        let systemPrompt = compressionSystemPrompt

        let request = try buildRequest(systemPrompt: systemPrompt, userText: text)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CompressionError.apiError("HTTP \(statusCode)")
        }

        let result = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        let compressed = cleanCompressedOutput(result.choices.first?.message.content ?? "")

        let originalTokens = await countTokens(text)
        let compressedTokens = await countTokens(compressed)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0

        return CompressedResult(
            text: compressed,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .openRouter
        )
    }

    // MARK: - Request building

    /// Builds a base URLRequest with the required OpenRouter headers.
    /// Exposed as `static` so the test sidebar can reuse the same header configuration.
    static func buildBaseRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/memetic-research-labs-llc/comp-tok-stt", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func buildRequest(systemPrompt: String, userText: String) throws -> URLRequest {
        var request = OpenRouterCompressor.buildBaseRequest(apiKey: apiKey)
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

struct OpenRouterResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message

        struct Message: Codable {
            let content: String
        }
    }
}
