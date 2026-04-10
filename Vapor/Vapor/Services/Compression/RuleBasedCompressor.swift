import Foundation

actor RuleBasedCompressor: Compressor {
    let name = "Rule-Based (Local)"
    let isAvailable = true

    private let articles = Set(["a", "an", "the"])
    private let prepositions = Set(["in", "on", "at", "to", "for", "of", "with", "by", "from", "into", "onto", "upon", "about", "above", "across", "after", "against", "along", "among", "around", "before", "behind", "below", "beneath", "beside", "between", "beyond", "down", "during", "except", "inside", "near", "off", "out", "over", "through", "toward", "under", "until", "up", "within", "without"])
    private let auxiliaryVerbs = Set(["is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did", "will", "would", "shall", "should", "can", "could", "may", "might", "must"])
    private let pronouns = Set(["i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his", "its", "our", "their", "mine", "yours", "hers", "ours", "theirs", "this", "that", "these", "those"])
    private let conjunctions = Set(["and", "or", "but", "so", "yet", "for", "nor"])
    private let negations = Set(["not", "never", "dont", "don't", "won't", "wont", "can't", "cant", "no", "unless", "without"])

    func compress(_ text: String) async throws -> CompressedResult {
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        var result: [String] = []

        for word in words {
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
            guard !cleanWord.isEmpty else { continue }
            if negations.contains(cleanWord) || isExactValue(cleanWord) {
                result.append(cleanWord)
            } else if shouldStrip(cleanWord) {
                continue
            } else {
                result.append(cleanWord)
            }
        }

        let compressed = result.joined(separator: " ")
        let originalTokens = await countTokens(text)
        let compressedTokens = await countTokens(compressed)
        let ratio = originalTokens > 0 ? Double(compressedTokens) / Double(originalTokens) : 0.0

        return CompressedResult(
            text: compressed,
            originalTokens: originalTokens,
            compressedTokens: compressedTokens,
            ratio: ratio,
            compressorUsed: .ruleBased
        )
    }

    private func shouldStrip(_ word: String) -> Bool {
        articles.contains(word) ||
        prepositions.contains(word) ||
        auxiliaryVerbs.contains(word) ||
        pronouns.contains(word) ||
        conjunctions.contains(word)
    }

    private func isExactValue(_ word: String) -> Bool {
        let numberPattern = #"^\d+(\.\d+)?$"#
        let urlPattern = #"^https?://"#
        let pathPattern = #"^/[\w/\.]+$"#
        let apiPattern = #"/api/|/v\d+/"#

        if word.range(of: numberPattern, options: .regularExpression) != nil { return true }
        if word.range(of: urlPattern, options: .regularExpression) != nil { return true }
        if word.range(of: pathPattern, options: .regularExpression) != nil { return true }
        if word.range(of: apiPattern, options: .regularExpression) != nil { return true }

        return false
    }
}
