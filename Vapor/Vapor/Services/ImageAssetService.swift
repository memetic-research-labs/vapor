import AppKit
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

final class ImageAssetService {
    private let blobStore = BlobStore.shared
    private var modelContext: ModelContext?
    private var archiveQueue: [(source: URL, destination: URL)] = []
    private var isArchiving = false

    @MainActor
    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    @MainActor
    func importImage(
        from fileURL: URL,
        sourceKind: ImageSourceKind,
        lifecycleState: ImageLifecycleState = .shelf
    ) async throws -> ImageAsset {
        guard let modelContext else { throw ImageAssetServiceError.noModelContext }

        let prepared = try await Self.prepareImport(from: fileURL)
        let contentHash = prepared.contentHash
        let createdAt = prepared.createdAt
        let shaPrefix = String(contentHash.prefix(8))
        let canonicalFilename = "screenshot_\(shaPrefix)"

        let archivedPath = Self.archiveDestination(canonicalName: canonicalFilename)
        enqueueArchive(from: fileURL, to: archivedPath)
        let effectiveOriginalPath = archivedPath.path

        let descriptor = FetchDescriptor<ImageAsset>(predicate: #Predicate { $0.contentHash == contentHash })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.originalPath = effectiveOriginalPath
            existing.originalFilename = "\(canonicalFilename).png"
            existing.lastObservedAt = Date()
            if shouldReplaceSourceKind(existing.sourceKind, with: sourceKind) {
                existing.sourceKind = sourceKind
            }
            existing.thumbnailPath = prepared.thumbnailRelativePath
            if lifecycleState == .context {
                existing.lifecycleState = .context
            }
            try modelContext.save()
            return existing
        }

        let asset = ImageAsset(
            contentHash: contentHash,
            mimeType: prepared.mimeType,
            pixelWidth: prepared.dimensions.width,
            pixelHeight: prepared.dimensions.height,
            byteSize: prepared.byteSize,
            originalFilename: "\(canonicalFilename).png",
            originalPath: effectiveOriginalPath,
            blobPath: prepared.blobRelativePath,
            thumbnailPath: prepared.thumbnailRelativePath,
            createdAt: createdAt,
            importedAt: Date(),
            lastObservedAt: Date(),
            sourceKind: sourceKind,
            lifecycleState: lifecycleState
        )

        modelContext.insert(asset)
        try modelContext.save()
        imageAssetLogger.info("Imported image asset \(shaPrefix, privacy: .public)")
        return asset
    }

    nonisolated private static func archiveDestination(canonicalName: String) -> URL {
        let archiveDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/vapor-screenshots-webp/original_png", isDirectory: true)
        try? FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        return archiveDir.appendingPathComponent("\(canonicalName).png")
    }

    @MainActor
    private func enqueueArchive(from source: URL, to destination: URL) {
        archiveQueue.append((source: source, destination: destination))
        processArchiveQueue()
    }

    @MainActor
    private func processArchiveQueue() {
        guard !isArchiving else { return }
        isArchiving = true

        Task.detached(priority: .utility) { [weak self] in
            while true {
                let item: (source: URL, destination: URL)? = await MainActor.run { [weak self] in
                    guard let self, !self.archiveQueue.isEmpty else { return nil }
                    return self.archiveQueue.removeFirst()
                }
                guard let item else { break }

                guard item.source.path != item.destination.path else { continue }

                do {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: item.destination.path) {
                        try fm.removeItem(at: item.destination)
                    }
                    try fm.moveItem(at: item.source, to: item.destination)
                    imageAssetLogger.info("Archived original PNG: \(item.destination.lastPathComponent, privacy: .public)")
                } catch {
                    imageAssetLogger.warning("Failed to archive original PNG \(item.source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
            await MainActor.run { [weak self] in
                self?.isArchiving = false
            }
        }
    }

    @MainActor
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

    @MainActor
    func setDismissed(_ dismissed: Bool, for asset: ImageAsset) throws {
        guard let modelContext else { throw ImageAssetServiceError.noModelContext }
        asset.dismissedFromShelf = dismissed
        try modelContext.save()
    }

    func fileURL(for asset: ImageAsset) -> URL {
        blobStore.fileURL(relativePath: asset.blobPath)
    }

    func thumbnailURL(for asset: ImageAsset) -> URL? {
        guard let thumbnailPath = asset.thumbnailPath,
              blobStore.exists(relativePath: thumbnailPath) else {
            return nil
        }
        return blobStore.fileURL(relativePath: thumbnailPath)
    }

    nonisolated private static func prepareImport(from fileURL: URL) async throws -> PreparedImageImport {
        try await Task.detached(priority: .userInitiated) {
            let blobStore = BlobStore.shared

            guard let data = try? Data(contentsOf: fileURL) else {
                throw ImageAssetServiceError.missingData(fileURL)
            }

            let mimeType = try mimeType(for: fileURL, data: data)
            let dimensions = imageDimensions(for: data)
            let storeResult = try blobStore.storeContentAddressed(data: data, mimeType: mimeType, namespace: "images")
            let thumbnailRelativePath = try makeThumbnailIfPossible(data: data, mimeType: mimeType, dimensions: dimensions, blobStore: blobStore)

            return PreparedImageImport(
                contentHash: storeResult.contentHash,
                mimeType: mimeType,
                dimensions: dimensions,
                byteSize: data.count,
                originalPath: fileURL.path,
                originalFilename: fileURL.lastPathComponent,
                blobRelativePath: storeResult.relativePath,
                thumbnailRelativePath: thumbnailRelativePath,
                createdAt: fileCreationDate(for: fileURL) ?? Date()
            )
        }.value
    }

    nonisolated private static func mimeType(for fileURL: URL, data: Data) throws -> String {
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

    nonisolated private static func imageDimensions(for data: Data) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return (0, 0)
        }
        return (width, height)
    }

    nonisolated private static func fileCreationDate(for fileURL: URL) -> Date? {
        let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    nonisolated private static func makeThumbnailIfPossible(
        data: Data,
        mimeType: String,
        dimensions: (width: Int, height: Int),
        blobStore: BlobStore
    ) throws -> String? {
        guard dimensions.width > 0, dimensions.height > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let maxPixelSize = 320
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let thumbnailData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(thumbnailData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        let stored = try blobStore.storeContentAddressed(data: thumbnailData as Data, mimeType: "image/png", namespace: "image-thumbnails")
        return stored.relativePath
    }

    private func baseTags(for asset: ImageAsset) -> [String] {
        var tags: [String] = []
        if asset.sourceKind == .screenshot {
            tags.append("screenshot")
        }
        return tags
    }

    private func shouldReplaceSourceKind(_ existing: ImageSourceKind, with newValue: ImageSourceKind) -> Bool {
        guard existing != newValue else { return false }

        if newValue == .screenshot, existing != .screenshot {
            return true
        }

        if existing == .screenshot, newValue != .screenshot {
            return false
        }

        return false
    }
}

private struct PreparedImageImport {
    let contentHash: String
    let mimeType: String
    let dimensions: (width: Int, height: Int)
    let byteSize: Int
    let originalPath: String
    let originalFilename: String
    let blobRelativePath: String
    let thumbnailRelativePath: String?
    let createdAt: Date
}
