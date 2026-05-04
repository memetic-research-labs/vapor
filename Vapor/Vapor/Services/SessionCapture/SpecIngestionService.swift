import Foundation
import SwiftData
import OSLog

nonisolated private let specLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "SpecIngestion")

@MainActor
@Observable
final class SpecIngestionService {
    static let shared = SpecIngestionService()

    private var modelContext: ModelContext?
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var watchedPath: String?

    private let queue = DispatchQueue(label: "lol.mrl.app.Vapor.spec-watcher", qos: .utility)

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func startWatching() {
        guard let openspecDir = resolveOpenspecDir() else {
            specLogger.info("openspec/ directory not found, skipping spec watching")
            return
        }

        watchedPath = openspecDir

        let fd = open(openspecDir, O_RDONLY)
        guard fd >= 0 else {
            specLogger.error("Failed to open openspec directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.scanAndIngest()
            }
        }

        source.setCancelHandler { close(fd) }
        source.resume()
        dispatchSource = source

        Task { @MainActor in
            await scanAndIngest()
        }

        specLogger.info("Watching openspec directory: \(openspecDir, privacy: .public)")
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    func scanAndIngest() async {
        guard let modelContext else { return }
        guard let openspecDir = watchedPath ?? resolveOpenspecDir() else { return }

        let fm = FileManager.default
        var ingestedCount = 0

        let specDirs = ["openspec/specs", "openspec/changes"]
        for specDir in specDirs {
            let fullPath = (openspecDir as NSString).deletingLastPathComponent + "/" + specDir
            guard fm.fileExists(atPath: fullPath) else { continue }

            let enumerator = fm.enumerator(at: URL(fileURLWithPath: fullPath), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            guard let enumerator else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "md" else { continue }

                let fileURLString = fileURL.absoluteString
                let targetURL = "file://" + fileURL.path

                let descriptor = FetchDescriptor<ContextItem>(
                    predicate: #Predicate { $0.sourceURL == targetURL }
                )
                let existing = try? modelContext.fetch(descriptor).first

                let fileTitle = deriveSpecTitle(from: fileURL.path, relativeTo: fullPath)
                let isProposal = fileURL.path.contains("/changes/") && fileURL.lastPathComponent == "proposal.md"

                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                if let existing {
                    if existing.markdownContent != content {
                        existing.markdownContent = content
                        existing.textContent = content
                        ingestedCount += 1
                    }
                } else {
                    var tags: [String] = []
                    if isProposal {
                        tags.append("change-proposal")
                        if let changeName = fileURL.path.components(separatedBy: "/changes/").last?
                            .components(separatedBy: "/").first {
                            tags.append(changeName)
                        }
                    }

                    let item = ContextItem(
                        sourceURL: targetURL,
                        sourceTitle: fileTitle,
                        kind: .spec,
                        textContent: content,
                        markdownContent: content
                    )
                    item.tags = tags
                    item.status = .ready

                    if let project = ProjectService.shared.detectProject(from: (fullPath as NSString).deletingLastPathComponent) {
                        item.project = project
                    }

                    modelContext.insert(item)
                    ingestedCount += 1
                }
            }
        }

        if ingestedCount > 0 {
            try? modelContext.save()
            StatusBarService.shared.log("Ingested \(ingestedCount) spec(s)", domain: .system, level: .success)

            if let items = try? modelContext.fetch(FetchDescriptor<ContextItem>(predicate: #Predicate { $0.kind.rawValue == "spec" && $0.embeddingID == nil })) {
                for item in items {
                    if let _ = try? await VectorizationService.shared.ensureEmbedding(for: item) {
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    private func resolveOpenspecDir() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["PWD"].map { "\($0)/openspec" } ?? "",
            FileManager.default.currentDirectoryPath + "/openspec",
        ]
        for path in candidates {
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { continue }
            return path
        }
        return nil
    }

    private func deriveSpecTitle(from filePath: String, relativeTo basePath: String) -> String {
        let relative = filePath.replacingOccurrences(of: basePath + "/", with: "")
        let withoutExtension = (relative as NSString).deletingPathExtension
        return withoutExtension
    }
}
