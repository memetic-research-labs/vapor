import Foundation
import SwiftLlama

actor LocalLLMCompressor: Compressor {
    let name = "Local LLM (On-Device)"

    private var llamaService: LlamaService?
    private let modelURL: URL

    var isAvailable: Bool {
        get async { llamaService != nil }
    }

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    func loadModel() async throws {
        let config = LlamaConfig(batchSize: 256, maxTokenCount: 4096, useGPU: true)
        llamaService = try LlamaService(modelUrl: modelURL, config: config)
    }

    func compress(_ text: String) async throws -> CompressedResult {
        guard let service = llamaService else {
            throw CompressionError.unavailable
        }

        let systemPrompt = compressionSystemPrompt

        let messages = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: text)
        ]

        let samplingConfig = LlamaSamplingConfig(temperature: 0.5, seed: 42)

        var compressed = ""
        let stream = try await service.streamCompletion(of: messages, samplingConfig: samplingConfig)
        for try await token in stream {
            compressed += token
        }

        let originalTokens = await countTokens(text)
        let compressedTokens = await countTokens(compressed)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0

        return CompressedResult(
            text: cleanCompressedOutput(compressed),
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .localLLM
        )
    }
}
