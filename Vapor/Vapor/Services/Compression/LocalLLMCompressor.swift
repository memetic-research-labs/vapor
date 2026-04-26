import Foundation
import SwiftLlama
import OSLog

actor LocalLLMCompressor: Compressor {
    let name = "Local LLM (On-Device)"

    nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "LocalLLM")

    private var llamaService: LlamaService?
    private let modelURL: URL

    var isAvailable: Bool {
        get async { llamaService != nil }
    }

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    func loadModel() async throws {
        let start = CFAbsoluteTimeGetCurrent()
        let config = LlamaConfig(batchSize: 256, maxTokenCount: 4096, useGPU: true)
        llamaService = LlamaService(modelUrl: modelURL, config: config)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.info("Local LLM model loaded in \(String(format: "%.1f", elapsed))s")
        Task { @MainActor in
            CompressionTelemetry.shared.recordServiceEvent(.modelLoad(
                backend: "Local LLM",
                model: modelURL.deletingPathExtension().lastPathComponent,
                duration: elapsed
            ))
        }
    }

    func compress(_ text: String) async throws -> CompressedResult {
        let compressed = try await generate(systemPrompt: compressionSystemPrompt, userText: text)

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

    func generate(systemPrompt: String, userText: String) async throws -> String {
        guard let service = llamaService else {
            throw CompressionError.unavailable
        }

        let messages = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: userText)
        ]

        let samplingConfig = LlamaSamplingConfig(
            temperature: 0.1,
            seed: 42,
            topP: 0.9,
            repetitionPenaltyConfig: LlamaRepetitionPenaltyConfig(
                lastN: 64,
                repeatPenalty: 1.0,
                freqPenalty: 0.0,
                presentPenalty: 0.0
            )
        )

        var output = ""
        let stream = try await service.streamCompletion(of: messages, samplingConfig: samplingConfig)
        for try await token in stream {
            output += token
        }

        return output
    }
}
