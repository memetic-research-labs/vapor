import Foundation
import OSLog
import SwiftData

nonisolated private let screenshotLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "ScreenshotShelf")

@MainActor
@Observable
final class ScreenshotShelfStore {
    static let shared = ScreenshotShelfStore()

    private static let isExpandedKey = "screenshotShelf.isExpanded"

    var isExpanded = UserDefaults.standard.object(forKey: isExpandedKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isExpanded, forKey: Self.isExpandedKey)
        }
    }
    var isScanning = false
    var lastScanDate: Date?
    var insertedAssetIDs: Set<UUID> = []

    private let imageAssetService = ImageAssetService()
    private weak var contextQueueService: ContextQueueService?
    private var pollTask: Task<Void, Never>?
    private var knownCandidates: [String: Date] = [:]

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
                    try await Task.sleep(for: .seconds(10))
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

        let candidates = await Self.screenshotCandidateURLs()
        var updatedKnownCandidates: [String: Date] = [:]

        for candidate in candidates {
            let url = candidate.url
            updatedKnownCandidates[url.path] = candidate.date
            if knownCandidates[url.path] == candidate.date {
                continue
            }

            do {
                _ = try await imageAssetService.importImage(from: url, sourceKind: .screenshot, lifecycleState: .shelf)
            } catch {
                screenshotLogger.warning("Skipping screenshot candidate \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        knownCandidates = updatedKnownCandidates
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
        try? imageAssetService.setDismissed(true, for: asset)
    }

    func addToContext(_ asset: ImageAsset) {
        guard let contextQueueService else { return }
        do {
            _ = try imageAssetService.makeImageContextItem(for: asset, in: contextQueueService)
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

    private static func screenshotCandidateURLs() async -> [(url: URL, date: Date)] {
        await Task.detached(priority: .utility) {
            let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast

            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: desktopURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }

            let candidates = urls.compactMap { url -> (url: URL, date: Date)? in
                guard url.lastPathComponent.localizedCaseInsensitiveContains("screenshot") else { return nil }

                let ext = url.pathExtension.lowercased()
                guard ["png", "jpg", "jpeg", "heic", "gif", "webp"].contains(ext) else { return nil }

                guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else {
                    return nil
                }

                let date = values.creationDate ?? values.contentModificationDate ?? .distantPast
                guard date >= cutoff else { return nil }

                return (url, date)
            }

            return Array(candidates.sorted { $0.date > $1.date }.prefix(20))
        }.value
    }
}
