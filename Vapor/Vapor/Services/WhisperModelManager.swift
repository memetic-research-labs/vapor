import Foundation
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "WhisperModel")

/// Available Whisper model sizes, ordered from fastest/smallest to most accurate/largest.
enum WhisperModelSize: String, CaseIterable, Identifiable, Codable {
    case tiny   = "tiny"
    case base   = "base"
    case small  = "small"
    case medium = "medium"
    case largeV3 = "large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:    return "Tiny"
        case .base:    return "Base"
        case .small:   return "Small"
        case .medium:  return "Medium"
        case .largeV3: return "Large v3"
        }
    }

    /// Short annotation shown alongside the model name (e.g. in picker descriptions).
    var annotation: String? {
        switch self {
        case .small: return "Recommended"
        default: return nil
        }
    }

    var sizeDescription: String {
        switch self {
        case .tiny:    return "75 MB · Fastest, decent accuracy"
        case .base:    return "142 MB · Fast, good accuracy"
        case .small:   return "466 MB · ~1–2s latency, very good accuracy"
        case .medium:  return "1.5 GB · ~2–3s latency, excellent accuracy"
        case .largeV3: return "3 GB · ~3–5s latency, best accuracy"
        }
    }

    /// The model identifier string that WhisperKit accepts (used with `WhisperKitConfig(model:)`).
    var whisperKitModelName: String { rawValue }
}

/// Manages downloading, caching, and selecting Whisper models for use with WhisperKit.
///
/// Model availability is tracked via UserDefaults (set after a successful download).
/// The download itself is handled by WhisperKit's built-in HuggingFace fetch mechanism.
@MainActor
@Observable
final class WhisperModelManager {

    static let shared = WhisperModelManager()

    // MARK: - State

    /// The model size the user wants to use (and which will be downloaded/loaded).
    var selectedSize: WhisperModelSize {
        didSet {
            UserDefaults.standard.set(selectedSize.rawValue, forKey: Keys.whisperModelSize)
            isModelAvailable = modelDownloadedFlag(for: selectedSize)
        }
    }

    /// Whether a download operation is currently in progress.
    private(set) var isDownloading: Bool = false

    /// Download progress in the range 0.0 … 1.0.
    private(set) var downloadProgress: Double = 0.0

    /// Whether the currently selected model has been downloaded.
    private(set) var isModelAvailable: Bool = false

    /// Human-readable status message for the current model.
    var modelStatusText: String {
        if isDownloading {
            return "Downloading \(selectedSize.displayName)… \(Int(downloadProgress * 100))%"
        }
        if isModelAvailable {
            return "\(selectedSize.displayName) model ready"
        }
        return "\(selectedSize.displayName) model not downloaded"
    }

    /// The model name string to pass to WhisperKit.
    var selectedModelName: String {
        selectedSize.whisperKitModelName
    }

    // MARK: - Private

    private var downloadTask: Task<Void, Error>?

    private struct Keys {
        static let whisperModelSize = "whisperModelSize"
        static let modelAvailablePrefix = "whisperModelAvailable_"
    }

    // MARK: - Init

    private init() {
        let savedRaw = UserDefaults.standard.string(forKey: Keys.whisperModelSize) ?? ""
        let size = WhisperModelSize(rawValue: savedRaw) ?? .small
        selectedSize = size
        isModelAvailable = modelDownloadedFlag(for: size)
    }

    // MARK: - Public API

    /// Re-check whether the selected model is available.
    func checkModelAvailability() async {
        isModelAvailable = modelDownloadedFlag(for: selectedSize)
    }

    /// Download the currently selected model via WhisperKit's built-in fetch mechanism.
    ///
    /// Progress updates are written to `downloadProgress`. Cancels any in-flight download first.
    func downloadModel() async throws {
        cancelDownload()
        isDownloading = true
        downloadProgress = 0.0
        defer {
            isDownloading = false
        }

        let modelName = selectedSize.whisperKitModelName
        let sizeAtStart = selectedSize
        logger.info("Starting download for model: \(modelName)")

        downloadTask = Task {
            try await downloadWhisperModel(modelName: modelName)
        }

        do {
            try await downloadTask?.value
            // Only set the flag if the selected size hasn't changed during download.
            if selectedSize == sizeAtStart {
                setModelDownloadedFlag(true, for: sizeAtStart)
                isModelAvailable = true
                downloadProgress = 1.0
                logger.info("Model download complete: \(modelName)")
            }
        } catch {
            logger.error("Model download failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Cancel any in-flight model download.
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if isDownloading {
            isDownloading = false
            downloadProgress = 0.0
        }
    }

    /// Remove the cached files for the currently selected model and clear the downloaded flag.
    func deleteModel() {
        WhisperKitLoader.shared.evict()
        setModelDownloadedFlag(false, for: selectedSize)
        isModelAvailable = false

        // Best-effort: remove model files from the HuggingFace hub cache.
        if let dir = huggingFaceCacheRoot() {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in contents {
                if url.lastPathComponent.contains(selectedSize.rawValue) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        logger.info("Deleted model: \(self.selectedSize.rawValue)")
    }

    // MARK: - Helpers

    private func modelDownloadedFlag(for size: WhisperModelSize) -> Bool {
        UserDefaults.standard.bool(forKey: Keys.modelAvailablePrefix + size.rawValue)
    }

    private func setModelDownloadedFlag(_ value: Bool, for size: WhisperModelSize) {
        UserDefaults.standard.set(value, forKey: Keys.modelAvailablePrefix + size.rawValue)
    }

    /// Root directory of the HuggingFace Hub model cache used by WhisperKit.
    private func huggingFaceCacheRoot() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "lol.mrl.app.Vapor"
        return caches
            .appendingPathComponent(bundleID)
            .appendingPathComponent("huggingface/hub")
    }

    /// Triggers WhisperKit's model download by constructing a temporary instance.
    private func downloadWhisperModel(modelName: String) async throws {
        // Animate progress while the download is in flight.
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(400))
                let current = self.downloadProgress
                if current < 0.9 {
                    self.downloadProgress = min(current + 0.015, 0.9)
                }
            }
        }
        defer { progressTask.cancel() }

        // WhisperKit's initialiser handles downloading and caching from HuggingFace.
        _ = try await WhisperKitLoader.shared.loadModel(named: modelName)
    }
}
