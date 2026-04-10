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
        tokenLogger.debug("Tiktoken BPE count: \(tokens.count) for \(text.prefix(50))...")
        return tokens.count
    }

    /// Clean LLM output by stripping quotes, whitespace, and common wrapper artifacts.
    func cleanCompressedOutput(_ text: String) -> String {
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

    var compressionSystemPrompt: String {
        """
        You are a prompt compression assistant. Remove filler words and use camelCase to fuse small related phrases (2-3 words) into single tokens. Keep separate semantic concepts separated by spaces.

        Rules:
        1. Remove: articles (a, an, the), prepositions (in, on, at, to, for, of, with, by, from), auxiliary verbs (is, are, was, were, have, has, had, will, would, should, can, could, may, might, must), pronouns (I, you, he, she, it, we, they, my, your, his, her, its, our, their), conjunctions (and, or, but, so, yet)
        2. Keep: nouns, verbs, adjectives, adverbs - the content words
        3. Preserve negations: not, never, don't, won't, can't, no, unless
        4. Preserve exact values: numbers, URLs, file paths, dates, measurements
        5. Use camelCase to fuse ONLY tightly coupled pairs or triplets (e.g., web component → webComponent, time of day → timeOfDay, square feet → squareFeet)
        6. NEVER fuse more than 3 words into one camelCase token
        7. ALWAYS keep separate concepts, actions, and clauses as separate space-delimited tokens

        Examples:
        Input: write a web component that renders a canvas that changes color from blue to golden as the time of day changes
        Output: write webComponent renders canvas changesColor blue golden timeOfDay changes

        Input: write a python script that uses pandas in order to allow one to easily query a standard real estate tax data set one would download from a local governing authority in the United States as an example query we'd like to see the average sized property land by square feet
        Output: write pythonScript uses pandas query realEstate taxData download localAuthority unitedStates exampleQuery averageSize propertyLand squareFeet

        Input: explain how the human immune system responds to a viral infection including the role of T cells and antibodies and why some people recover faster than others
        Output: explain humanImmuneSystem responds viralInfection role tCells antibodies why somePeople recoverFaster others

        Input: I need a recipe for a gluten-free chocolate cake that doesn't use any refined sugar and can be made in under 45 minutes with only 6 ingredients
        Output: recipe glutenFree chocolateCake no refinedSugar under 45 minutes only 6 ingredients

        Input: compare the pros and cons of buying versus renting a home in a high cost of living area like San Francisco when you have $200,000 saved for a down payment
        Output: compare prosAndCons buying versus renting home highCostOfLiving sanFrancisco $200,000 saved downPayment

        Return ONLY the compressed text, no quotes, no explanation.
        """
    }

}
