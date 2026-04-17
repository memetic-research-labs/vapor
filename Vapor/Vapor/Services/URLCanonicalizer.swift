import Foundation
import CryptoKit

struct CanonicalURL: Hashable, Sendable {
    let canonicalURL: String
    let urlHash: String
    let domain: String
    let scheme: String
    let path: String
    let query: String?
}

enum URLCanonicalizer {
    private static let marketingParameterNames: Set<String> = [
        "fbclid",
        "gclid",
        "igshid",
        "mc_cid",
        "mc_eid",
        "mkt_tok",
        "msclkid"
    ]

    static func canonicalize(_ rawURL: String) -> CanonicalURL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              let scheme = components.scheme?.lowercased() else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        components.fragment = nil

        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }

        let filteredQueryItems = (components.queryItems ?? [])
            .filter { item in
                let key = item.name.lowercased()
                return !key.hasPrefix("utm_") && !marketingParameterNames.contains(key)
            }
            .sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }

        components.queryItems = filteredQueryItems.isEmpty ? nil : filteredQueryItems

        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        components.percentEncodedPath = path

        guard let canonicalURL = components.url?.absoluteString else { return nil }

        return CanonicalURL(
            canonicalURL: canonicalURL,
            urlHash: sha256(canonicalURL),
            domain: host,
            scheme: scheme,
            path: path,
            query: components.percentEncodedQuery
        )
    }

    static func extractURLs(from text: String) -> [CanonicalURL] {
        guard !text.isEmpty else { return [] }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var results: [CanonicalURL] = []

        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let raw = match?.url?.absoluteString,
                  let canonical = canonicalize(raw),
                  seen.insert(canonical.urlHash).inserted else {
                return
            }
            results.append(canonical)
        }

        return results
    }

    static func normalizeEntityText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func entityHash(kind: EntityKind, normalizedText: String) -> String {
        sha256("\(kind.rawValue)\u{001F}\(normalizedText)")
    }

    private static func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
