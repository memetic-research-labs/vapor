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

        let systemPrompt = """
        You are a prompt compression assistant. Compress text by removing filler words and fusing related concepts.
        
        Rules:
        1. Remove: articles (a, an, the), prepositions (in, on, at, to, for, of, with, by, from), auxiliary verbs (is, are, was, were, have, has, had, will, would, should, can, could, may, might, must), pronouns (I, you, he, she, it, we, they, my, your, his, her, its, our, their), conjunctions (and, or, but, so, yet)
        2. Keep: nouns, verbs, adjectives, adverbs - the content words
        3. Preserve negations: not, never, don't, won't, can't, no, unless
        4. Preserve exact values: numbers, URLs, file paths
        5. Fuse ONLY words that form a single concept (e.g., "web component" → "webcomponent")
        6. Keep distinct concepts SEPARATED by spaces
        
        Example:
        Input: "write a web component that renders a canvas"
        Output: "write webcomponent renders canvas"
        
        Notice: "web component" became "webcomponent" (single concept), but "renders" and "canvas" stayed separate (distinct concepts).
        
        Return ONLY the compressed text.
        """

        let request = try buildRequest(systemPrompt: systemPrompt, userText: text)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CompressionError.apiError("HTTP \(statusCode)")
        }

        let result = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        let compressed = result.choices.first?.message.content ?? ""

        let originalTokens = estimateTokens(text)
        let compressedTokens = estimateTokens(compressed)
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
        request.setValue("https://github.com/memetic-research-labs/comp-tok-stt", forHTTPHeaderField: "HTTP-Referer")
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
