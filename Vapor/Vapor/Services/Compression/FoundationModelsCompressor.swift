import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "FoundationModels")

@available(macOS 26, *)
actor FoundationModelsCompressor: Compressor {
    let name = "Apple Foundation Models"

    var isAvailable: Bool {
        get async {
            return SystemLanguageModel.default.isAvailable
        }
    }

    func compress(_ text: String) async throws -> CompressedResult {
        let systemPrompt = compressionSystemPrompt

        let userPrompt = """
        Compress using prompt-cloud rules:
        
        \(text)
        """

        let session = LanguageModelSession {
            systemPrompt
        }

        logger.debug("Sending to model: \(text)")
        let response = try await session.respond(to: Prompt { userPrompt })
        let compressed = cleanCompressedOutput(response.content)
        logger.debug("Model response: \(compressed)")

        let originalTokens = await countTokens(text)
        let compressedTokens = await countTokens(compressed)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0

        return CompressedResult(
            text: compressed,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .foundationModels
        )
    }
}
#endif

enum CompressionError: Error {
    case unavailable
    case apiError(String)
}
