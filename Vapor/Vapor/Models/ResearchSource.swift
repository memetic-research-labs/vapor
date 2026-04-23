import Foundation

enum ResearchSourceKind: String, Codable, Sendable {
    case domSummary = "domSummary"
    case structuredJSON = "structuredJSON"
    case table = "table"
    case xhrFeed = "xhrFeed"
    case imageFeed = "imageFeed"
}

struct DiscoveredSource: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let sourceKind: ResearchSourceKind
    let label: String
    let detail: String
    let recordEstimate: Int?
    let sizeHint: String?

    var systemImage: String {
        switch sourceKind {
        case .domSummary: return "doc.text.magnifyingglass"
        case .structuredJSON: return "curlybraces"
        case .table: return "tablecells"
        case .xhrFeed: return "arrow.left.arrow.right.circle"
        case .imageFeed: return "photo.on.rectangle.angled"
        }
    }

    var kindLabel: String {
        switch sourceKind {
        case .domSummary: return "Page Content"
        case .structuredJSON: return "JSON"
        case .table: return "Table"
        case .xhrFeed: return "Network"
        case .imageFeed: return "Media"
        }
    }
}

struct SourcePreview: Codable, Sendable {
    let sourceId: String
    let content: String
    let mimeType: String
    let truncated: Bool
    let sizeBytes: Int?
}
