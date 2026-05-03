import Foundation
import SwiftLlama
import OSLog

nonisolated private struct LocalCompressionResponse: Codable {
    let compressed: String
}

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
        let cleaned = try await compressTextPreservingMarkdownImages(text, systemPrompt: systemPrompt)
        let compressedTokens = await countTokens(cleaned)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0

        if let failureReason = CompressionValidation.failureReason(
            original: text,
            compressed: cleaned,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens
        ) {
            logger.warning("Local LLM compression validation failed: \(failureReason, privacy: .public)")
            throw CompressionError.apiError("Compressed output failed validation — \(failureReason). Try again with another model or backend.")
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

    private func generateStructured(systemPrompt: String, userText: String) async throws -> String {
        guard let service = llamaService else {
            throw CompressionError.unavailable
        }

        let messages = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: userText)
        ]

        let response = try await service.respond(to: messages, generating: LocalCompressionResponse.self)
        return response.compressed
    }

    private func compressTextPreservingMarkdownImages(_ text: String, systemPrompt: String) async throws -> String {
        let parts = CompressionProtectedContent.splitMarkdownImageLines(text)
        guard CompressionProtectedContent.containsMarkdownImage(parts) else {
            return cleanCompressedOutput(try await generateStructured(systemPrompt: systemPrompt, userText: text))
        }

        var outputParts: [String] = []
        for part in parts {
            switch part {
            case .text(let block):
                let compressedBlock = cleanCompressedOutput(try await generateStructured(systemPrompt: systemPrompt, userText: block))
                if !compressedBlock.isEmpty {
                    outputParts.append(compressedBlock)
                }
            case .markdownImage(let line):
                outputParts.append(line)
            }
        }
        return outputParts.joined(separator: "\n\n")
    }

    nonisolated private var localCompressorPrompt: String {
        """
        Compress the following text to preserve its meaning in fewer words. Return valid JSON only: {"compressed":"..."}.

        Follow these rules:
        1. Remove unnecessary words (articles, filler phrases, repetition).
        2. Keep all numbers, proper nouns, URLs, file paths, identifiers, hashes, code symbols, filenames, and markdown references exactly as-is.
        3. Use compact noun/verb phrases instead of full sentences.
        4. Keep negations explicit (not, never, unless, no).
        5. Use spaces between semantic chunks. Do not fuse unrelated words into unreadable compounds.
        6. Preserve every markdown image reference exactly as written. If the input contains any line like ![...](...), copy that whole line verbatim into compressed, with the same alt text, path, and relative position.
        7. Do not invent screenshots, markdown image lines, file paths, hashes, URLs, numbers, or filenames that are not in the input.

        Style example: "write a python script that uses pandas in order to allow one to easily query a standard real estate tax data set" becomes "write python script use pandas query real estate tax data set".

        Do NOT generate additional examples. Do NOT include "Input:" or "Output:" labels in your response.
        """
    }

    nonisolated static func computeMaxOutputTokens(inputTokens: Int) -> Int {
        min(768, max(96, Int(Double(inputTokens) * 0.65)))
    }

}
