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
        
        let originalTokens = estimateTokens(text)
        let compressedTokens = estimateTokens(compressed)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0
        
        return CompressedResult(
            text: compressed.trimmingCharacters(in: .whitespacesAndNewlines),
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .localLLM
        )
    }
    
    private func estimateTokens(_ text: String) -> Int {
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return Int(Double(wordCount) * 1.3)
    }
}
