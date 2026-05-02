import AppKit
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

    private let imageAssetService = ImageAssetService()
    private let imageProcessingService = ImageProcessingService.shared
    private weak var contextQueueService: ContextQueueService?
    private var maxImageDimension: Int = 768
    private var pollTask: Task<Void, Never>?
    private var knownCandidates: [String: Date] = [:]
    private var processingInFlight: Set<String> = []

    private init() {}

    func setModelContext(_ context: ModelContext) {
        imageAssetService.setModelContext(context)
    }

    func setContextQueueService(_ service: ContextQueueService) {
        contextQueueService = service
    }

    func setMaxImageDimension(_ dimension: Int) {
        maxImageDimension = dimension
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
            if let knownDate = knownCandidates[url.path], abs(knownDate.timeIntervalSince(candidate.date)) < 1.0 {
                continue
            }

            do {
                let asset = try await imageAssetService.importImage(from: url, sourceKind: .screenshot, lifecycleState: .shelf)
                processForSidebar(asset: asset)
            } catch {
                screenshotLogger.warning("Skipping screenshot candidate \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        knownCandidates = updatedKnownCandidates
    }

    func insertScreenshot(_ asset: ImageAsset) {
        let shaPrefix = String(asset.contentHash.prefix(8))
        Task { [weak self] in
            guard let self else { return }
            let result = await self.imageProcessingService.processForInjection(asset: asset, maxDimension: self.maxImageDimension)
            let path = result?.webpPath ?? self.webpURL(for: asset).path
            let markdown = "![screenshot_\(shaPrefix)](\(path))"
            NotificationCenter.default.post(name: .vaporInsertContextItem, object: markdown)
        }
        processForSidebar(asset: asset)
    }

    func dismiss(_ asset: ImageAsset) {
        do {
            try imageAssetService.setDismissed(true, for: asset)
        } catch {
            screenshotLogger.error("Failed to dismiss screenshot asset: \(error.localizedDescription, privacy: .public)")
        }
        let shaPrefix = String(asset.contentHash.prefix(8))
        NotificationCenter.default.post(name: .vaporScreenshotDismissedFromSidebar, object: SidebarScreenshotItem(shaPrefix: shaPrefix, mimeType: "image/webp"))
    }

    func addToContext(_ asset: ImageAsset) {
        guard let contextQueueService else {
            screenshotLogger.warning("Cannot add screenshot asset to context because ContextQueueService is unavailable")
            return
        }
        do {
            _ = try imageAssetService.makeImageContextItem(for: asset, in: contextQueueService)
            try imageAssetService.setDismissed(false, for: asset)
        } catch {
            screenshotLogger.error("Failed to add screenshot asset to context: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fileURL(for asset: ImageAsset) -> URL {
        imageAssetService.fileURL(for: asset)
    }

    func revealAsset(_ asset: ImageAsset) {
        let webpURL = webpURL(for: asset)
        if FileManager.default.fileExists(atPath: webpURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([webpURL])
            return
        }
        if let originalPath = asset.originalPath, FileManager.default.fileExists(atPath: originalPath) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: originalPath)])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: asset)])
    }

    func openAsset(_ asset: ImageAsset) {
        let webpURL = webpURL(for: asset)
        if FileManager.default.fileExists(atPath: webpURL.path) {
            NSWorkspace.shared.open(webpURL)
            return
        }
        if let originalPath = asset.originalPath, FileManager.default.fileExists(atPath: originalPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: originalPath))
            return
        }
        NSWorkspace.shared.open(fileURL(for: asset))
    }

    private func processForSidebar(asset: ImageAsset) {
        let shaPrefix = String(asset.contentHash.prefix(8))
        let targetURL = webpURL(for: asset)
        let item = SidebarScreenshotItem(shaPrefix: shaPrefix, mimeType: "image/webp")

        if FileManager.default.fileExists(atPath: targetURL.path) {
            NotificationCenter.default.post(name: .vaporScreenshotReadyForSidebar, object: item)
            return
        }

        guard !processingInFlight.contains(shaPrefix) else { return }
        processingInFlight.insert(shaPrefix)

        Task { @MainActor in
            defer { processingInFlight.remove(shaPrefix) }
            guard let _ = await imageProcessingService.processForInjection(asset: asset, maxDimension: maxImageDimension) else {
                screenshotLogger.error("Failed to process screenshot for sidebar: \(shaPrefix, privacy: .public)")
                return
            }
            NotificationCenter.default.post(name: .vaporScreenshotReadyForSidebar, object: item)
        }
    }

    private func webpURL(for asset: ImageAsset) -> URL {
        let shaPrefix = String(asset.contentHash.prefix(8))
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/vapor-screenshots-webp", isDirectory: true)
        return dir.appendingPathComponent("screenshot_\(shaPrefix).webp")
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
