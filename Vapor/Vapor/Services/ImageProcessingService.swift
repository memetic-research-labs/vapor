import AppKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers
import WebP

nonisolated private let processingLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "ImageProcessing")

final class ImageProcessingService {
    static let shared = ImageProcessingService()

    private let blobStore = BlobStore.shared

    private init() {}

    func processForInjection(asset: ImageAsset, maxDimension: Int = 512) async -> AttachedImage? {
        await Task.detached(priority: .userInitiated) { () -> AttachedImage? in
            guard let rawData = self.blobStore.retrieve(relativePath: asset.blobPath) else {
                processingLogger.error("Cannot retrieve blob data for asset \(asset.contentHash, privacy: .public)")
                return nil
            }

            guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else {
                processingLogger.error("Cannot create CGImageSource for asset \(asset.contentHash, privacy: .public)")
                return nil
            }

            let shaPrefix = String(asset.contentHash.prefix(8))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let downscaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                processingLogger.error("Cannot downscale image for asset \(asset.contentHash, privacy: .public)")
                return nil
            }

            let width = downscaled.width
            let height = downscaled.height
            let bytesPerPixel = 4
            let stride = width * bytesPerPixel
            let pixelBufferSize = stride * height

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                processingLogger.error("Cannot create sRGB color space")
                return nil
            }

            var pixelBuffer = [UInt8](repeating: 0, count: pixelBufferSize)
            guard let context = CGContext(
                data: &pixelBuffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: stride,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                processingLogger.error("Cannot create CGContext for asset \(shaPrefix, privacy: .public)")
                return nil
            }

            context.draw(downscaled, in: CGRect(x: 0, y: 0, width: width, height: height))

            let webpData: Data
            do {
                let encoder = WebPEncoder()
                let config = WebPEncoderConfig.preset(.picture, quality: 80)
                webpData = try pixelBuffer.withUnsafeMutableBufferPointer { buf in
                    try encoder.encode(
                        buf.baseAddress!,
                        format: .rgba,
                        config: config,
                        originWidth: width,
                        originHeight: height,
                        stride: stride
                    )
                }
            } catch {
                processingLogger.error("WebP encoding failed for asset \(shaPrefix, privacy: .public): \(error.localizedDescription)")
                return nil
            }

            let webpFileName = "screenshot_\(shaPrefix).webp"
            let outputDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop", isDirectory: true)
                .appendingPathComponent("vapor-screenshots-webp", isDirectory: true)

            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                processingLogger.error("Cannot create output directory: \(error.localizedDescription)")
                return nil
            }

            let outputURL = outputDir.appendingPathComponent(webpFileName)
            do {
                try webpData.write(to: outputURL, options: .atomic)
            } catch {
                processingLogger.error("Cannot write WebP file: \(error.localizedDescription)")
                return nil
            }

            let base64 = webpData.base64EncodedString()
            let markdownReference = "![screenshot_\(shaPrefix)](\(outputURL.path))"

            processingLogger.info("Processed screenshot \(shaPrefix, privacy: .public): \(rawData.count) bytes → \(webpData.count) bytes WebP (\(width)x\(height))")

            return AttachedImage(
                id: UUID(),
                assetId: asset.id,
                shaPrefix: shaPrefix,
                mimeType: "image/webp",
                webpPath: outputURL.path,
                markdownReference: markdownReference,
                base64: base64
            )
        }.value
    }
}
