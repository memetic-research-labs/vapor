import AppKit
import SwiftUI
import SwiftData

struct ImageAssetThumbnailView<Placeholder: View>: View {
    let asset: ImageAsset
    let size: CGSize?
    let preferThumbnail: Bool
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: taskKey) {
            await loadImage()
        }
    }

    private var taskKey: String {
        [asset.id.uuidString, asset.thumbnailPath ?? "", asset.blobPath, asset.originalPath ?? "", preferThumbnail ? "thumb" : "full"].joined(separator: "|")
    }

    private func loadImage() async {
        let url = imageURL(for: asset, preferThumbnail: preferThumbnail)
        guard let url else {
            nsImage = nil
            return
        }

        let targetSize = size
        let loadedImage: NSImage? = await {
            guard let image = NSImage(contentsOf: url) else { return nil }
            if let targetSize {
                image.size = targetSize
            }
            return image
        }()

        nsImage = loadedImage
    }
}

private func imageURL(for asset: ImageAsset, preferThumbnail: Bool) -> URL? {
    if preferThumbnail,
       let thumbnailPath = asset.thumbnailPath,
       BlobStore.shared.exists(relativePath: thumbnailPath) {
        return BlobStore.shared.fileURL(relativePath: thumbnailPath)
    }

    if let originalPath = asset.originalPath, FileManager.default.fileExists(atPath: originalPath) {
        return URL(fileURLWithPath: originalPath)
    }

    if BlobStore.shared.exists(relativePath: asset.blobPath) {
        return BlobStore.shared.fileURL(relativePath: asset.blobPath)
    }

    return nil
}
