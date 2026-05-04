import Foundation
import SwiftData

enum ImageSourceKind: String, Codable, CaseIterable, Sendable {
    case screenshot
    case pastedImage
    case droppedFile
    case articleMedia
    case browserCaptured
    case manualImport

    var displayName: String {
        switch self {
        case .screenshot: "Screenshot"
        case .pastedImage: "Pasted Image"
        case .droppedFile: "Dropped File"
        case .articleMedia: "Article Media"
        case .browserCaptured: "Browser Capture"
        case .manualImport: "Imported Image"
        }
    }
}

enum ImageLifecycleState: String, Codable, CaseIterable, Sendable {
    case shelf
    case context
}

enum ContextImageRole: String, Codable, CaseIterable, Sendable {
    case primary
    case attachment
    case inlineArticleMedia
    case promptAttachment
    case screenshotReference

    var sortOrder: Int {
        switch self {
        case .primary: 0
        case .attachment: 1
        case .inlineArticleMedia: 2
        case .promptAttachment: 3
        case .screenshotReference: 4
        }
    }
}

@Model
final class ImageAsset {
    var id: UUID
    @Attribute(.unique) var contentHash: String
    var mimeType: String
    var pixelWidth: Int
    var pixelHeight: Int
    var byteSize: Int
    var originalFilename: String
    var originalPath: String?
    var blobPath: String
    var thumbnailPath: String?
    var createdAt: Date
    var importedAt: Date
    var lastObservedAt: Date
    var sourceKindRaw: String
    var lifecycleStateRaw: String
    var dismissedFromShelf: Bool

    var project: VaporProject?
    var aiSession: AISession?

    @Relationship(deleteRule: .cascade, inverse: \ContextItemImageLink.imageAsset)
    var links: [ContextItemImageLink] = []

    init(
        contentHash: String,
        mimeType: String,
        pixelWidth: Int,
        pixelHeight: Int,
        byteSize: Int,
        originalFilename: String,
        originalPath: String?,
        blobPath: String,
        thumbnailPath: String? = nil,
        createdAt: Date = Date(),
        importedAt: Date = Date(),
        lastObservedAt: Date = Date(),
        sourceKind: ImageSourceKind,
        lifecycleState: ImageLifecycleState = .shelf,
        dismissedFromShelf: Bool = false
    ) {
        self.id = UUID()
        self.contentHash = contentHash
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
        self.originalFilename = originalFilename
        self.originalPath = originalPath
        self.blobPath = blobPath
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.lastObservedAt = lastObservedAt
        self.sourceKindRaw = sourceKind.rawValue
        self.lifecycleStateRaw = lifecycleState.rawValue
        self.dismissedFromShelf = dismissedFromShelf
    }

    var sourceKind: ImageSourceKind {
        get { ImageSourceKind(rawValue: sourceKindRaw) ?? .manualImport }
        set { sourceKindRaw = newValue.rawValue }
    }

    var lifecycleState: ImageLifecycleState {
        get { ImageLifecycleState(rawValue: lifecycleStateRaw) ?? .shelf }
        set { lifecycleStateRaw = newValue.rawValue }
    }

    var displayTitle: String {
        String(contentHash.prefix(8))
    }

    var sortDate: Date {
        max(lastObservedAt, importedAt)
    }

    var linkedContextItems: [ContextItem] {
        links.compactMap(\.contextItem)
    }
}

@Model
final class ContextItemImageLink {
    var id: UUID
    var roleRaw: String
    var sortIndex: Int
    var caption: String?
    var altText: String?
    var sourceURL: String?
    var createdAt: Date

    var contextItem: ContextItem?
    var imageAsset: ImageAsset?

    init(
        role: ContextImageRole,
        sortIndex: Int = 0,
        caption: String? = nil,
        altText: String? = nil,
        sourceURL: String? = nil,
        createdAt: Date = Date(),
        contextItem: ContextItem? = nil,
        imageAsset: ImageAsset? = nil
    ) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.sortIndex = sortIndex
        self.caption = caption
        self.altText = altText
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.contextItem = contextItem
        self.imageAsset = imageAsset
    }

    var role: ContextImageRole {
        get { ContextImageRole(rawValue: roleRaw) ?? .attachment }
        set { roleRaw = newValue.rawValue }
    }
}
