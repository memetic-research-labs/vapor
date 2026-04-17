import AppKit
import CryptoKit
import Foundation
import ImageIO
import OSLog
import SwiftData
import UniformTypeIdentifiers

nonisolated private let imageAssetLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "ImageAssets")

enum ImageAssetServiceError: LocalizedError {
    case unsupportedImage(URL)
    case missingData(URL)
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .unsupportedImage(let url): "Unsupported image type: \(url.lastPathComponent)"
        case .missingData(let url): "Could not read image data from \(url.lastPathComponent)"
        case .noModelContext: "Image asset service is not attached to a model context"
        }
    }
}

@MainActor
@Observable
final class ImageAssetService {
    private let blobStore = BlobStore.shared
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func importImage(
        from fileURL: URL,
        sourceKind: ImageSourceKind,
        lifecycleState: ImageLifecycleState = .shelf
    ) throws -> ImageAsset {
        guard let modelContext else { throw ImageAssetServiceError.noModelContext }

        guard let data = try? Data(contentsOf: fileURL) else {
            throw ImageAssetServiceError.missingData(fileURL)
        }

        let mimeType = try mimeType(for: fileURL, data: data)
        let dimensions = imageDimensions(for: data)
        let storeResult = try blobStore.storeContentAddressed(data: data, mimeType: mimeType, namespace: "images")
        let contentHash = storeResult.contentHash
        let createdAt = fileCreationDate(for: fileURL) ?? Date()
        let originalPath = fileURL.path
        let originalFilename = fileURL.lastPathComponent

        let descriptor = FetchDescriptor<ImageAsset>(predicate: #Predicate { $0.contentHash == contentHash })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.originalPath = originalPath
            existing.originalFilename = originalFilename
            existing.lastObservedAt = Date()
            existing.sourceKind = sourceKind
            if lifecycleState == .context {
                existing.lifecycleState = .context
            }
            try modelContext.save()
            return existing
        }

        let asset = ImageAsset(
            contentHash: contentHash,
            mimeType: mimeType,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height,
            byteSize: data.count,
            originalFilename: originalFilename,
            originalPath: originalPath,
            blobPath: storeResult.relativePath,
            createdAt: createdAt,
            importedAt: Date(),
            lastObservedAt: Date(),
            sourceKind: sourceKind,
            lifecycleState: lifecycleState
        )

        modelContext.insert(asset)
        try modelContext.save()
        imageAssetLogger.info("Imported image asset \(contentHash, privacy: .public) from \(originalFilename, privacy: .public)")
        return asset
    }

    func makeImageContextItem(for asset: ImageAsset, in queueService: ContextQueueService) throws -> ContextItem {
        if let existing = asset.linkedContextItems.first(where: { $0.kind == .image }) {
            return existing
        }

        guard let modelContext else { throw ImageAssetServiceError.noModelContext }

        asset.lifecycleState = .context

        let item = ContextItem(
            sourceURL: asset.originalPath ?? "",
            sourceTitle: asset.displayTitle,
            capturedAt: asset.createdAt,
            kind: .image,
            blobPath: asset.blobPath,
            blobMimeType: asset.mimeType,
            thumbnailPath: asset.thumbnailPath
        )
        item.status = .ready
        item.tags = baseTags(for: asset)

        let link = ContextItemImageLink(
            role: .primary,
            createdAt: asset.createdAt,
            contextItem: item,
            imageAsset: asset
        )

        modelContext.insert(item)
        modelContext.insert(link)
        item.imageLinks.append(link)
        asset.links.append(link)
        try modelContext.save()

        queueService.addReadyItem(item)
        return item
    }

    func fileURL(for asset: ImageAsset) -> URL {
        blobStore.fileURL(relativePath: asset.blobPath)
    }

    func promptReference(for asset: ImageAsset, annotated: Bool) -> String {
        let referencePath = preferredReferencePath(for: asset)
        guard annotated else { return referencePath }
        return "[Screenshot]\npath: \(referencePath)"
    }

    func preferredReferencePath(for asset: ImageAsset) -> String {
        if let originalPath = asset.originalPath, FileManager.default.fileExists(atPath: originalPath) {
            return originalPath
        }
        return fileURL(for: asset).path
    }

    private func mimeType(for fileURL: URL, data: Data) throws -> String {
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let typeIdentifier = CGImageSourceGetType(source) as String?,
           let type = UTType(typeIdentifier),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        throw ImageAssetServiceError.unsupportedImage(fileURL)
    }

    private func imageDimensions(for data: Data) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return (0, 0)
        }
        return (width, height)
    }

    private func fileCreationDate(for fileURL: URL) -> Date? {
        let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    private func baseTags(for asset: ImageAsset) -> [String] {
        var tags: [String] = []
        if asset.sourceKind == .screenshot {
            tags.append("screenshot")
        }
        return tags
    }
}
