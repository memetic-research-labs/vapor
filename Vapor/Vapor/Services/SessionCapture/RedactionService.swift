import Foundation
import OSLog

nonisolated private let redactionLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Redaction")

struct RedactionMatch {
    let range: Range<String.Index>
    let original: String
    let reason: String
}

struct RedactionResult {
    let redactedContent: String
    let matches: [RedactionMatch]
    let fullyRedactedTurnIDs: [UUID]
}

struct RedactedTurnsResult {
    let redactedContents: [(turnID: UUID, content: String)]
    let fullyRedactedTurnIDs: [UUID]
    let totalMatchCount: Int
}

@MainActor
final class RedactionService {
    static let shared = RedactionService()

    private let sensitiveKeywords = ["password", "secret", "token", "credential", "api.key", "private.key"]

    private lazy var regexPatterns: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            (#"(sk-or-v1-[a-zA-Z0-9]{48,})"#, "api-key-pattern"),
            (#"(sk-ant-[a-zA-Z0-9]{20,})"#, "api-key-pattern"),
            (#"(ghp_[a-zA-Z0-9]{36,})"#, "api-key-pattern"),
            (#"(gho_[a-zA-Z0-9]{36,})"#, "api-key-pattern"),
            (#"(glpat-[a-zA-Z0-9\-_]{20,})"#, "api-key-pattern"),
            (#"Bearer\s+[a-zA-Z0-9\-\._~+/]+=*"#, "bearer-token-pattern"),
            (#"(password|secret|token|api_key)\s*[=:]\s*\S+"#, "generic-secret-pattern"),
            (#"~/.ssh/[^\s\"']+"#, "sensitive-path"),
            (#"\.env\b"#, "sensitive-path"),
            (#"\.id_rsa"#, "sensitive-path"),
            (#"~/.aws/credentials"#, "sensitive-path"),
            (#"(?i)internal\.[a-z0-9\-]+\.(com|net|io)"#, "internal-url"),
            (#"localhost:\d+"#, "internal-url"),
        ]
        return patterns.compactMap { pattern, reason in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, reason)
        }
    }()

    private init() {}

    func detectSecrets(in text: String) -> [RedactionMatch] {
        var matches: [RedactionMatch] = []

        for (regex, reason) in regexPatterns {
            let fullRange = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: fullRange) { nsResult, _, _ in
                guard let result = nsResult, let textRange = Range(result.range, in: text) else { return }
                matches.append(RedactionMatch(range: textRange, original: String(text[textRange]), reason: reason))
            }
        }

        matches.sort { $0.range.lowerBound > $1.range.lowerBound }
        return matches
    }

    func detectSensitiveKeywords(in text: String) -> [String] {
        sensitiveKeywords.filter { text.localizedCaseInsensitiveContains($0) }
    }

    func applyDenylistPatterns(_ patterns: [String], to text: String) -> [RedactionMatch] {
        var matches: [RedactionMatch] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let fullRange = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: fullRange) { nsResult, _, _ in
                guard let result = nsResult, let textRange = Range(result.range, in: text) else { return }
                matches.append(RedactionMatch(range: textRange, original: String(text[textRange]), reason: "user-denylist"))
            }
        }
        matches.sort { $0.range.lowerBound > $1.range.lowerBound }
        return matches
    }

    func redact(text: String, matches: [RedactionMatch]) -> String {
        guard !matches.isEmpty else { return text }
        var result = text
        for match in matches.reversed() {
            let replacement = "[REDACTED: \(match.reason)]"
            result.replaceSubrange(match.range, with: replacement)
        }
        return result
    }

    func redactTurns(_ turns: [AITurn]) -> RedactedTurnsResult {
        var fullyRedactedTurnIDs: [UUID] = []
        var redactedContents: [(turnID: UUID, content: String)] = []
        var totalMatchCount = 0

        for turn in turns {
            let regexMatches = detectSecrets(in: turn.content)
            let denylistPatterns = UserDefaults.standard.stringArray(forKey: "exportDenylistPatterns") ?? []
            let denylistMatches = applyDenylistPatterns(denylistPatterns, to: turn.content)

            var allMatches = regexMatches + denylistMatches
            allMatches.sort { $0.range.lowerBound < $1.range.lowerBound }
            let merged = mergeMatches(allMatches)
            totalMatchCount += merged.count

            let redacted = redact(text: turn.content, matches: merged)

            if merged.count == 1 && turn.content == merged.first?.original {
                fullyRedactedTurnIDs.append(turn.id)
            }

            redactedContents.append((turnID: turn.id, content: redacted))
        }

        return RedactedTurnsResult(
            redactedContents: redactedContents,
            fullyRedactedTurnIDs: fullyRedactedTurnIDs,
            totalMatchCount: totalMatchCount
        )
    }

    func detectSensitiveContentInSession(_ turns: [AITurn]) -> [String] {
        var foundKeywords = Set<String>()
        for turn in turns {
            for keyword in detectSensitiveKeywords(in: turn.content) {
                foundKeywords.insert(keyword)
            }
        }
        return foundKeywords.sorted()
    }

    private func mergeMatches(_ matches: [RedactionMatch]) -> [RedactionMatch] {
        guard !matches.isEmpty else { return [] }
        let sorted = matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var merged: [RedactionMatch] = []
        for match in sorted {
            if let last = merged.last, match.range.lowerBound < last.range.upperBound {
                continue
            }
            merged.append(match)
        }
        return merged
    }
}
