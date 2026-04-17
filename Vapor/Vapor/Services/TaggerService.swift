import Foundation

@MainActor
final class TaggerService {
    private let stopWords: Set<String> = {
        let words: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "shall", "can", "need", "dare", "ought",
            "used", "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "as", "into", "through", "during", "before", "after", "above", "below",
            "between", "out", "off", "over", "under", "again", "further", "then",
            "once", "here", "there", "when", "where", "why", "how", "all", "each",
            "every", "both", "few", "more", "most", "other", "some", "such", "no",
            "nor", "not", "only", "own", "same", "so", "than", "too", "very",
            "just", "because", "but", "and", "or", "if", "while", "that", "this",
            "these", "those", "it", "its", "i", "me", "my", "we", "our", "you",
            "your", "he", "him", "his", "she", "her", "they", "them", "their",
            "what", "which", "who", "whom", "whose", "about", "up", "also"
        ]
        return words
    }()

    private let minTagLength = 3
    private let maxTags = 8

    func tag(contextItem: ContextItem) -> [String] {
        var tags: [String] = []

        if !contextItem.sourceURL.isEmpty {
            if let host = URL(string: contextItem.sourceURL)?.host {
                let domain = host.replacingOccurrences(of: "www.", with: "")
                tags.append(domain)
            }
        }

        if !contextItem.sourceTitle.isEmpty {
            let titleTags = extractKeywords(from: contextItem.sourceTitle, limit: 3)
            for tag in titleTags {
                if !tags.contains(tag) { tags.append(tag) }
            }
        }

        for entity in contextItem.entities where entity.confidence > 0.6 {
            let tag = entity.text.lowercased()
            if !tags.contains(tag) && tag.count >= minTagLength {
                tags.append(tag)
            }
        }

        if let text = contextItem.textContent, !text.isEmpty {
            let remaining = max(0, maxTags - tags.count)
            let textTags = extractKeywords(from: text, limit: remaining)
            for tag in textTags {
                if !tags.contains(tag) { tags.append(tag) }
            }
        }

        switch contextItem.kind {
        case .articleText: tags.append("article")
        case .selectedText: tags.append("selection")
        case .image: tags.append("image")
        case .pageSnapshot: tags.append("snapshot")
        case .xhrJSON, .xhrBinary: tags.append("api")
        default: break
        }

        return Array(tags.prefix(maxTags))
    }

    private func extractKeywords(from text: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= minTagLength && !stopWords.contains($0) }

        var frequencies: [String: Int] = [:]
        for word in words {
            frequencies[word, default: 0] += 1
        }

        return frequencies
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
}
