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
        let systemPrompt = localCompressorPrompt

        let originalTokens = await countTokens(text)
        let maxOutputTokens = Self.computeMaxOutputTokens(inputTokens: originalTokens)

        let raw = try await generate(
            systemPrompt: systemPrompt,
            userText: text,
            maxOutputTokens: maxOutputTokens
        )

        let cleaned = cleanCompressedOutput(raw)
        let compressedTokens = await countTokens(cleaned)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0

        guard Self.isOutputValid(cleaned: cleaned, compressedTokens: compressedTokens, originalTokens: originalTokens) else {
            logger.warning("Local LLM compression validation failed: output \(compressedTokens) tokens vs input \(originalTokens) tokens")
            throw CompressionError.apiError("Compressed output failed validation — output was longer than input or contained hallucinated examples. Try again.")
        }

        return CompressedResult(
            text: cleaned,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .localLLM
        )
    }

    func generate(systemPrompt: String, userText: String, maxOutputTokens: Int) async throws -> String {
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
                lastN: 128,
                repeatPenalty: 1.2,
                freqPenalty: 0.2,
                presentPenalty: 0.1
            )
        )

        var output = ""
        var tokenCount = 0
        let stream = try await service.streamCompletion(of: messages, samplingConfig: samplingConfig)
        for try await token in stream {
            if tokenCount >= maxOutputTokens { break }
            output += token
            tokenCount += 1
        }

        return output
    }

    nonisolated private var localCompressorPrompt: String {
        """
        Compress the following text to preserve its meaning in fewer words. Follow these rules:
        1. Remove unnecessary words (articles, filler phrases, repetition).
        2. Keep all numbers, proper nouns, URLs, file paths, identifiers, hashes, code symbols, filenames, and markdown references exactly as-is.
        3. Use short clear phrases instead of full sentences.
        4. Keep negations explicit (not, never, unless, no).
        5. Use spaces between compressed words. Do not fuse words together.
        6. Preserve all markdown image references exactly as written — any ![...](...) line must appear unchanged with the same path.

        Example:
        Input: write a python script that uses pandas in order to allow one to easily query a standard real estate tax data set
        Output: write python script use pandas query real estate tax data set

        Do NOT generate additional examples. Do NOT include "Input:" or "Output:" labels in your response. Return ONLY the compressed text, nothing else.
        """
    }

    nonisolated static func computeMaxOutputTokens(inputTokens: Int) -> Int {
        min(768, max(96, Int(Double(inputTokens) * 0.65)))
    }

    nonisolated static func isOutputValid(cleaned: String, compressedTokens: Int, originalTokens: Int) -> Bool {
        if originalTokens < 16 { return true }
        let acceptableMax = max(originalTokens - 8, Int(Double(originalTokens) * 0.85))
        if compressedTokens > acceptableMax { return false }
        if cleaned.contains("\nInput:") || cleaned.contains("\nOutput:") { return false }
        return true
    }
}
