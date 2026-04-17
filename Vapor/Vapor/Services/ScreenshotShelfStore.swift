import Foundation
import OSLog
import SwiftData

nonisolated private let screenshotLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "ScreenshotShelf")

@MainActor
@Observable
final class ScreenshotShelfStore {
    static let shared = ScreenshotShelfStore()

    var isExpanded = true
    var isScanning = false
    var lastScanDate: Date?
    var insertedAssetIDs: Set<UUID> = []
    var dismissedAssetIDs: Set<UUID> = []

    private let imageAssetService = ImageAssetService()
    private weak var contextQueueService: ContextQueueService?
    private var pollTask: Task<Void, Never>?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        imageAssetService.setModelContext(context)
    }

    func setContextQueueService(_ service: ContextQueueService) {
        contextQueueService = service
    }

    func start() {
        guard pollTask == nil else { return }

        pollTask = Task { @MainActor in
            await refresh()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                await refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        let candidates = screenshotCandidateURLs()
        for url in candidates {
            do {
                _ = try imageAssetService.importImage(from: url, sourceKind: .screenshot, lifecycleState: .shelf)
            } catch {
                screenshotLogger.warning("Skipping screenshot candidate \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func insertAnnotatedReference(for asset: ImageAsset) {
        NotificationCenter.default.post(name: .vaporInsertContextItem, object: imageAssetService.promptReference(for: asset, annotated: true))
        insertedAssetIDs.insert(asset.id)
    }

    func insertPlainPath(for asset: ImageAsset) {
        NotificationCenter.default.post(name: .vaporInsertContextItem, object: imageAssetService.promptReference(for: asset, annotated: false))
        insertedAssetIDs.insert(asset.id)
    }

    func dismiss(_ asset: ImageAsset) {
        dismissedAssetIDs.insert(asset.id)
    }

    func addToContext(_ asset: ImageAsset) {
        guard let contextQueueService else { return }
        do {
            _ = try imageAssetService.makeImageContextItem(for: asset, in: contextQueueService)
            dismissedAssetIDs.remove(asset.id)
        } catch {
            screenshotLogger.error("Failed to add screenshot asset to context: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fileURL(for asset: ImageAsset) -> URL {
        imageAssetService.fileURL(for: asset)
    }

    func displayPath(for asset: ImageAsset) -> String {
        imageAssetService.preferredReferencePath(for: asset)
    }

    private func screenshotCandidateURLs() -> [URL] {
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: desktopURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast

        let urls = (enumerator.allObjects as? [URL] ?? [])
            .filter { url in
                guard url.lastPathComponent.localizedCaseInsensitiveContains("screenshot") else { return false }
                let ext = url.pathExtension.lowercased()
                return ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext)
            }
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { return false }
                let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                return date >= cutoff
            }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]).creationDate)
                    ?? (try? lhs.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]).creationDate)
                    ?? (try? rhs.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return leftDate > rightDate
            }

        return Array(urls.prefix(20))
    }
}
