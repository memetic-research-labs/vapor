import Foundation

struct BrowserTab: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let platform: String
    let title: String
    let url: String

    var host: String {
        Self.normalizedHost(from: url)
    }

    var displayHost: String {
        guard !host.isEmpty else { return platform == "browser" ? "browser" : platform }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    var displayTitle: String {
        title.isEmpty ? displayHost : title
    }

    var matchesKnownAIHost: Bool {
        let host = displayHost.lowercased()
        return ["chatgpt.com", "openai.com", "claude.ai", "gemini.google.com", "grok.com", "x.com", "perplexity.ai"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    var systemImage: String {
        let host = displayHost.lowercased()
        if host.contains("chatgpt") || host.contains("openai") { return "sparkles" }
        if host.contains("claude") { return "text.bubble" }
        if host.contains("gemini") { return "diamond" }
        if host.contains("grok") || host == "x.com" { return "bolt.horizontal" }
        if host.contains("perplexity") { return "questionmark.circle" }
        return "globe"
    }

    static func normalizedHost(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return "" }
        return host
    }
}

struct BrowserTarget: Hashable, Codable, Sendable {
    var tabID: Int?
    var title: String
    var url: String
    var host: String
    var platform: String
    var isConnected: Bool

    init(tab: BrowserTab, isConnected: Bool = true) {
        self.tabID = tab.id
        self.title = tab.title
        self.url = tab.url
        self.host = tab.displayHost
        self.platform = tab.platform
        self.isConnected = isConnected
    }

    var displayLabel: String {
        if !host.isEmpty { return host }
        return platform == "browser" ? "browser" : platform
    }

    var reopenURL: String {
        if !url.isEmpty { return url }
        guard !host.isEmpty else { return "" }
        return "https://\(host)"
    }
}
