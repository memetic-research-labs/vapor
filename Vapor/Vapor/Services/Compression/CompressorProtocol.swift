import Foundation
import Tiktoken
import OSLog

private let tokenLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Tokenizer")

struct CompressedResult {
    let text: String
    let originalTokens: Int
    let compressedTokens: Int
    let ratio: Double
    let compressorUsed: CompressorType
}

protocol Compressor {
    var name: String { get }
    var isAvailable: Bool { get async }

    func compress(_ text: String) async throws -> CompressedResult
}

extension Compressor {
    func countTokens(_ text: String) async -> Int {
        // Pass a model name ("gpt-4") not an encoding name ("cl100k_base")
        // because Tiktoken.shared.getEncoding looks up model → encoding internally.
        guard let encoder = try? await Tiktoken.shared.getEncoding("gpt-4") else {
            tokenLogger.warning("Tiktoken encoding failed to load, using word estimate fallback")
            let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            return Int(Double(wordCount) * 1.3)
        }
        let tokens = encoder.encode(value: text)
        tokenLogger.debug("Tiktoken BPE count: \(tokens.count), input length: \(text.count) characters")
        return tokens.count
    }

    /// Clean LLM output by stripping quotes, whitespace, and common wrapper artifacts.
    nonisolated func cleanCompressedOutput(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip wrapping quotes (single or double)
        while (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
              (result.hasPrefix("'") && result.hasSuffix("'")) {
            result = String(result.dropFirst().dropLast())
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Strip leading "Output:" if the model echoes the format
        if result.lowercased().hasPrefix("output:") {
            result = String(result.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    nonisolated var compressionSystemPrompt: String {
        """
        You are a Prompt-Cloud (PC) compression engine. Compress prompts into dense, token-efficient form that preserves functional equivalence — the model processing the compressed form should activate the same semantic patterns as the original.

        Compression rules:
        1. Strip articles, prepositions, auxiliary verbs, pronouns, conjunctions — all grammatical scaffolding that carries no semantic weight.
        2. Bundle semantically overlapping concepts into dense lowercase compound strings. Fuse aggressively — related concepts become single tokens.
        3. Use camelCase ONLY where two fused concepts would be ambiguous without it (e.g., prReviewer not prreviewer). Default is lowercase.
        4. Preserve all exact values verbatim inline: numbers, URLs, paths, dates, identifiers, proper nouns.
        5. Preserve all negations and exclusions explicitly — never bury a negation inside a compound where it could be lost. Keep not, never, unless, no visible.
        6. Use minimal whitespace. Break only where running tokens together would create genuine ambiguity. Dense blocks are preferred.
        7. Compress behavioral/intent content aggressively. Preserve structured data, conditionals, and exact instructions verbatim.

        Target: 40-60% token reduction. The compressed form is model-readable, not human-readable.

        Examples:
        Input: You are a senior backend engineer reviewing pull requests. Focus on correctness, performance, and maintainability. Be direct but not harsh. If you see a pattern that will cause problems at scale, flag it clearly. Don't nitpick formatting or style unless it hurts readability. Always explain why something matters, not just what's wrong.
        Output: seniorbackendprReviewer focuscorrectnessperformancemaintainability directnotharsh flagscaleproblems skipformattingstyle unlessreadabilityhurt alwaysexplainwhymatters notwhatswrong

        Input: write a python script that uses pandas in order to allow one to easily query a standard real estate tax data set one would download from a local governing authority in the United States as an example query we'd like to see the average sized property land by square feet
        Output: writepythonscript usespandas queryrealestatetaxdata downloadlocalauthority unitedStates examplequery averagepropertyland squarefeet

        Input: explain how the human immune system responds to a viral infection including the role of T cells and antibodies and why some people recover faster than others
        Output: explainhumanimmunesystem respondsviralinFection roletcellsantibodies whysomepeople recoverfasterothers

        Input: I need a recipe for a gluten-free chocolate cake that doesn't use any refined sugar and can be made in under 45 minutes with only 6 ingredients
        Output: recipeglutenfreechocolatecake norefinedsugar under45minutes only6ingredients

        Input: compare the pros and cons of buying versus renting a home in a high cost of living area like San Francisco when you have $200,000 saved for a down payment
        Output: compareproscons buyingvsrenting homehighcostliving sanFrancisco $200,000saved downpayment

        Return ONLY the compressed text, no quotes, no explanation.
        """
    }

    nonisolated var smallModelSystemPrompt: String {
        """
        Compress the following text to preserve its meaning in fewer words. Follow these rules:
        1. Remove unnecessary words (articles, filler phrases, repetition).
        2. Keep all numbers, proper nouns, URLs, file paths, and technical terms exactly as-is.
        3. Use short clear phrases instead of full sentences.
        4. Keep negations explicit (not, never, unless, no).
        5. Use spaces between compressed words. Do not fuse words together.

        Return ONLY the compressed text, no quotes, no explanation.
        """
    }

}
