import Foundation

enum CitationFormat: String, Codable, CaseIterable {
    case urlOnly = "url"
    case apa = "apa"

    var displayName: String {
        switch self {
        case .urlOnly: "URL only"
        case .apa: "APA"
        }
    }
}

struct Citation: Codable, Sendable {
    var url: String
    var title: String
    var author: String?
    var publishedDate: Date?
    var accessedDate: Date
    var format: CitationFormat
    var rendered: String

    init(
        url: String,
        title: String,
        author: String? = nil,
        publishedDate: Date? = nil,
        format: CitationFormat = .urlOnly
    ) {
        self.url = url
        self.title = title
        self.author = author
        self.publishedDate = publishedDate
        self.accessedDate = Date()
        self.format = format
        let input = RenderInput(url: url, title: title, author: author, publishedDate: publishedDate, accessedDate: self.accessedDate, format: format)
        self.rendered = Self.render(input)
    }

    private struct RenderInput {
        let url: String
        let title: String
        let author: String?
        let publishedDate: Date?
        let accessedDate: Date
        let format: CitationFormat
    }

    private static func render(_ input: RenderInput) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        switch input.format {
        case .urlOnly:
            return input.url
        case .apa:
            var parts: [String] = []
            if let author = input.author {
                parts.append(author)
            }
            var dateStr = "n.d."
            if let publishedDate = input.publishedDate {
                dateStr = formatter.string(from: publishedDate)
            }
            parts.append("(\(dateStr)).")
            parts.append("\(input.title).")
            parts.append("Retrieved \(formatter.string(from: input.accessedDate)), from \(input.url)")
            return parts.joined(separator: " ")
        }
    }
}
