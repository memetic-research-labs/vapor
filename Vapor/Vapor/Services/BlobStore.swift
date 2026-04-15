import Foundation
import OSLog

nonisolated private let blobLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "BlobStore")

@MainActor
final class BlobStore {
    static let shared = BlobStore()

    private let baseURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vaporDir = appSupport.appendingPathComponent("Vapor", isDirectory: true)
        let blobsDir = vaporDir.appendingPathComponent("blobs", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        } catch {
            blobLogger.error("Failed to create blob store directory: \(error.localizedDescription)")
        }

        self.baseURL = blobsDir
    }

    func store(data: Data, mimeType: String) throws -> String {
        let id = UUID().uuidString
        let ext = extensionFor(mimeType: mimeType)
        let relativePath = "\(id)\(ext)"
        let fileURL = baseURL.appendingPathComponent(relativePath)

        do {
            try data.write(to: fileURL, options: .atomic)
            blobLogger.debug("Stored blob: \(relativePath) (\(data.count) bytes, \(mimeType))")
            return relativePath
        } catch {
            blobLogger.error("Failed to store blob \(relativePath): \(error.localizedDescription)")
            throw error
        }
    }

    func retrieve(relativePath: String) -> Data? {
        let fileURL = baseURL.appendingPathComponent(relativePath)
        return try? Data(contentsOf: fileURL)
    }

    func delete(relativePath: String) throws {
        let fileURL = baseURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
        blobLogger.debug("Deleted blob: \(relativePath)")
    }

    func totalSize() -> Int64 {
        let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func itemCount() -> Int {
        let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var count = 0
        while enumerator?.nextObject() != nil {
            count += 1
        }
        return count
    }

    func clearAll() throws {
        if FileManager.default.fileExists(atPath: baseURL.path) {
            try FileManager.default.removeItem(at: baseURL)
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            blobLogger.debug("Cleared all blobs")
        }
    }

    private func extensionFor(mimeType: String) -> String {
        switch mimeType {
        case "image/png": return ".png"
        case "image/jpeg": return ".jpg"
        case "image/webp": return ".webp"
        case "image/gif": return ".gif"
        case "video/mp4": return ".mp4"
        case "video/webm": return ".webm"
        case "application/json": return ".json"
        case "text/plain": return ".txt"
        case "text/html": return ".html"
        default: return ".bin"
        }
    }
}
