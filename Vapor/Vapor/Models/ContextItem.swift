import Foundation
import SwiftData

enum ContextItemKind: String, Codable, CaseIterable, Sendable {
    case articleText
    case selectedText
    case image
    case animatedGif
    case videoClip
    case xhrJSON
    case xhrBinary
    case pageSnapshot
    case manualText

    var displayName: String {
        switch self {
        case .articleText: "Article"
        case .selectedText: "Selection"
        case .image: "Image"
        case .animatedGif: "GIF"
        case .videoClip: "Video"
        case .xhrJSON: "API JSON"
        case .xhrBinary: "API Binary"
        case .pageSnapshot: "Page Snapshot"
        case .manualText: "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .articleText: "doc.text"
        case .selectedText: "text.append"
        case .image: "photo"
        case .animatedGif: "photo.on.rectangle"
        case .videoClip: "video"
        case .xhrJSON: "curlybraces"
        case .xhrBinary: "archivebox"
        case .pageSnapshot: "globe"
        case .manualText: "pencil"
        }
    }
}

enum ProcessingStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case processing
    case ready
    case failed
}

nonisolated private func decodeCitation(_ data: Data) -> Citation? {
    try? JSONDecoder().decode(Citation.self, from: data)
}

nonisolated private func encodeCitation(_ citation: Citation) -> Data? {
    try? JSONEncoder().encode(citation)
}

@Model
final class ContextItem {
    var id: UUID
    var sourceURL: String
    var sourceTitle: String
    var sourceAuthor: String?
    var sourcePublishedDate: Date?
    var sourceSiteName: String?
    var capturedAt: Date
    var kindRaw: String
    var statusRaw: String

    var textContent: String?
    var markdownContent: String?
    var blobPath: String?
    var blobMimeType: String?
    var thumbnailPath: String?

    var tags: [String]
    var citationData: Data?
    var summaryData: Data?
    var extractionBackendRaw: String?
    var embeddingID: String?
    var captureJobId: String?

    @Relationship(deleteRule: .cascade, inverse: \ContextItemURLLink.contextItem)
    var urlLinks: [ContextItemURLLink] = []

    @Relationship(deleteRule: .cascade, inverse: \ContextItemEntityLink.contextItem)
    var entityLinks: [ContextItemEntityLink] = []

    init(
        sourceURL: String = "",
        sourceTitle: String = "",
        sourceAuthor: String? = nil,
        sourcePublishedDate: Date? = nil,
        sourceSiteName: String? = nil,
        capturedAt: Date = Date(),
        kind: ContextItemKind,
        textContent: String? = nil,
        markdownContent: String? = nil,
        blobPath: String? = nil,
        blobMimeType: String? = nil,
        thumbnailPath: String? = nil
    ) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.sourceAuthor = sourceAuthor
        self.sourcePublishedDate = sourcePublishedDate
        self.sourceSiteName = sourceSiteName
        self.capturedAt = capturedAt
        self.kindRaw = kind.rawValue
        self.statusRaw = ProcessingStatus.pending.rawValue
        self.textContent = textContent
        self.markdownContent = markdownContent
        self.blobPath = blobPath
        self.blobMimeType = blobMimeType
        self.thumbnailPath = thumbnailPath
        self.tags = []
        self.citationData = nil
        self.summaryData = nil
        self.extractionBackendRaw = nil
        self.embeddingID = nil
    }

    var kind: ContextItemKind {
        get { ContextItemKind(rawValue: kindRaw) ?? .manualText }
        set { kindRaw = newValue.rawValue }
    }

    var status: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var citation: Citation? {
        get {
            guard let data = citationData else { return nil }
            return decodeCitation(data)
        }
        set {
            citationData = newValue.flatMap { encodeCitation($0) }
        }
    }

    var summary: DocumentSummary? {
        get {
            guard let data = summaryData else { return nil }
            return try? JSONDecoder().decode(DocumentSummary.self, from: data)
        }
        set {
            summaryData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var extractionBackend: EntityExtractionBackend? {
        get {
            guard let raw = extractionBackendRaw else { return nil }
            return EntityExtractionBackend(rawValue: raw)
        }
        set {
            extractionBackendRaw = newValue?.rawValue
        }
    }

    var sortedURLLinks: [ContextItemURLLink] {
        urlLinks.sorted {
            if $0.role.sortOrder == $1.role.sortOrder {
                return $0.urlDisplayText.localizedCaseInsensitiveCompare($1.urlDisplayText) == .orderedAscending
            }
            return $0.role.sortOrder < $1.role.sortOrder
        }
    }

    var sortedEntityLinks: [ContextItemEntityLink] {
        entityLinks.sorted {
            if $0.entityKind.rawValue == $1.entityKind.rawValue {
                return $0.displayText.localizedCaseInsensitiveCompare($1.displayText) == .orderedAscending
            }
            return $0.entityKind.rawValue < $1.entityKind.rawValue
        }
    }

    var entityCount: Int {
        sortedEntityLinks.count
    }
}
