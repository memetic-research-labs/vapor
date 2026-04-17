import Foundation

@MainActor
final class CitationBuilder {

    func build(for item: ContextItem, format: CitationFormat? = nil) -> Citation? {
        guard !item.sourceURL.isEmpty else { return nil }

        let title = item.sourceTitle.isEmpty ? item.sourceURL : item.sourceTitle
        let effectiveFormat = format ?? .apa

        return Citation(
            url: item.sourceURL,
            title: title,
            author: item.sourceAuthor,
            publishedDate: item.sourcePublishedDate,
            format: effectiveFormat
        )
    }
}
