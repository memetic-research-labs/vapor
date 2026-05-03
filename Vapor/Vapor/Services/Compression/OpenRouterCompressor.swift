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
        let originalTokens = await countTokens(text)
        let cleaned = try await compressTextPreservingMarkdownImages(text, systemPrompt: systemPrompt)

        let compressedTokens = await countTokens(cleaned)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0

        if let failureReason = CompressionValidation.failureReason(
            original: text,
            compressed: cleaned,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens
        ) {
            throw CompressionError.apiError("Compressed output failed validation — \(failureReason). Try again with another model or backend.")
        }

        return CompressedResult(
            text: cleaned,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .openRouter
        )
    }

    // MARK: - Request building

    nonisolated static func buildBaseRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/memetic-research-labs-llc/comp-tok-stt", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func buildRequest(systemPrompt: String, userText: String, maxOutputTokens: Int) throws -> URLRequest {
        var request = OpenRouterCompressor.buildBaseRequest(apiKey: apiKey)
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ],
            "max_tokens": maxOutputTokens,
            "temperature": 0.1,
            "stop": ["\n\nInput:", "\n\nOutput:", "\n\n---"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func compressTextPreservingMarkdownImages(_ text: String, systemPrompt: String) async throws -> String {
        let parts = CompressionProtectedContent.splitMarkdownImageLines(text)
        guard CompressionProtectedContent.containsMarkdownImage(parts) else {
            return try await compressTextBlock(text, systemPrompt: systemPrompt)
        }

        var outputParts: [String] = []
        for part in parts {
            switch part {
            case .text(let block):
                let compressedBlock = try await compressTextBlock(block, systemPrompt: systemPrompt)
                if !compressedBlock.isEmpty {
                    outputParts.append(compressedBlock)
                }
            case .markdownImage(let line):
                outputParts.append(line)
            }
        }
        return outputParts.joined(separator: "\n\n")
    }

    private func compressTextBlock(_ text: String, systemPrompt: String) async throws -> String {
        let blockTokens = await countTokens(text)
        let request = try buildRequest(
            systemPrompt: systemPrompt,
            userText: text,
            maxOutputTokens: Self.computeMaxOutputTokens(inputTokens: blockTokens)
        )
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CompressionError.apiError("HTTP \(statusCode): \(body.prefix(200))")
        }

        let result = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        return cleanCompressedOutput(result.choices.first?.message.content ?? "")
    }

    nonisolated static func computeMaxOutputTokens(inputTokens: Int) -> Int {
        min(768, max(96, Int(Double(inputTokens) * 0.65)))
    }

}

nonisolated struct OpenRouterResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message

        struct Message: Codable {
            let content: String
        }
    }
}
