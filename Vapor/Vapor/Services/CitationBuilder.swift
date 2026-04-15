import Foundation

@MainActor
final class CitationBuilder {

    func build(for item: ContextItem, format: CitationFormat = .urlOnly) -> Citation? {
        guard !item.sourceURL.isEmpty else { return nil }

        let title = item.sourceTitle.isEmpty ? item.sourceURL : item.sourceTitle

        return Citation(
            url: item.sourceURL,
            title: title,
            format: format
        )
    }
}
