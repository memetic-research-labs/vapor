import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
actor FoundationModelsCompressor: Compressor {
    let name = "Apple Foundation Models"
    
    var isAvailable: Bool {
        get async {
            return SystemLanguageModel.default.isAvailable
        }
    }
    
    func compress(_ text: String) async throws -> CompressedResult {
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
        
        let userPrompt = """
        Compress using prompt-cloud rules:
        
        \(text)
        """
        
        let session = LanguageModelSession {
            systemPrompt
        }
        
        print("[FoundationModels] Sending to model: \(text)")
        let response = try await session.respond(to: Prompt { userPrompt })
        let compressed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[FoundationModels] Model response: \(compressed)")
        
        let originalTokens = estimateTokens(text)
        let compressedTokens = estimateTokens(compressed)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0
        
        return CompressedResult(
            text: compressed,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .foundationModels
        )
    }
    
    private func estimateTokens(_ text: String) -> Int {
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return Int(Double(wordCount) * 1.3)
    }
}
#endif

enum CompressionError: Error {
    case unavailable
    case apiError(String)
}
