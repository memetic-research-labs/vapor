import Foundation
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Compression")

struct LocalLLMModel: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let fileName: String
    let downloadURL: String
    let sizeGB: Double
    let isDefault: Bool

    static let curatedModels: [LocalLLMModel] = [
        LocalLLMModel(
            id: "phi-4-mini-q4",
            displayName: "Phi-4 Mini (3.8B)",
            fileName: "Phi-4-mini-instruct-Q4_K_M.gguf",
            downloadURL: "https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf",
            sizeGB: 2.3,
            isDefault: true
        ),
        LocalLLMModel(
            id: "qwen3-4b-2507-q4",
            displayName: "Qwen 3 4B (2507)",
            fileName: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
            downloadURL: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
            sizeGB: 2.4,
            isDefault: false
        ),
        LocalLLMModel(
            id: "qwen2.5-7b-q4",
            displayName: "Qwen 2.5 7B",
            fileName: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
            downloadURL: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
            sizeGB: 4.7,
            isDefault: false
        )
    ]

    static var defaultModel: LocalLLMModel {
        curatedModels.first { $0.isDefault } ?? curatedModels[0]
    }

    static func find(by id: String) -> LocalLLMModel? {
        curatedModels.first { $0.id == id }
    }

    static func find(byFileName fileName: String) -> LocalLLMModel? {
        curatedModels.first { $0.fileName == fileName }
    }

    static func infer(from modelURL: URL) -> LocalLLMModel? {
        find(byFileName: modelURL.lastPathComponent)
    }
}

@MainActor
private class DownloadDelegate: NSObject, @preconcurrency URLSessionDownloadDelegate {
    var destinationURL: URL?
    var didCopySuccessfully = false
    var error: Error?
    var isFinished = false
    var bytesWritten: Int64 = 0
    var totalBytesExpected: Int64?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination = destinationURL else {
            logger.error("No destination URL set for download")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: location, to: destination)
            didCopySuccessfully = true
            logger.info("Model copied to: \(destination.path)")
        } catch {
            logger.error("Failed to copy downloaded file: \(error)")
            self.error = error
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.bytesWritten = totalBytesWritten
        self.totalBytesExpected = totalBytesExpectedToWrite
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.error = error
        isFinished = true
    }
}

@MainActor
@Observable
final class CompressionService {
    var selectedCompressor: CompressorType = .localLLM
    var availableCompressors: [CompressorType: Bool] = [:]
    var openRouterModel: String = "glm-5"
    var modelDownloadProgress: Double = 0
    var isDownloading: Bool = false
    var isModelLoading: Bool = false
    var statusMessage: String = "Ready"
    var selectedLocalModel: LocalLLMModel = .defaultModel {
        didSet {
            guard oldValue.id != selectedLocalModel.id else { return }
            UserDefaults.standard.set(selectedLocalModel.id, forKey: localLLMModelIDKey)
            selectedModelAvailabilityTask?.cancel()
            selectedModelAvailabilityTask = Task {
                await checkAvailability()
            }
        }
    }
    var downloadedModelID: String?

    private let telemetry = CompressionTelemetry.shared
    private var resetTask: Task<Void, Never>?
    private var selectedModelAvailabilityTask: Task<Void, Never>?
    private let minimumValidModelSizeBytes: Int64 = 100_000_000

    var isSelectedCompressorReady: Bool {
        switch selectedCompressor {
        case .openRouter:
            return availableCompressors[.openRouter] ?? false
        case .localLLM:
            return availableCompressors[.localLLM] ?? false
        }
    }

    private var openRouterCompressor: OpenRouterCompressor?
    private var localLLMCompressor: LocalLLMCompressor?

    private let openRouterApiKeyKey = "openRouterApiKey"
    private let localLLMModelIDKey = "localLLMModelID"
    private let localLLMModelURLKey = "localLLMModelURL"

    var isSelectedLocalModelDownloaded: Bool {
        downloadedModelID == selectedLocalModel.id
    }

    init() {
        loadSavedSettings()
        Task {
            await checkAvailability()
        }
    }

    private func loadSavedSettings() {
        if let savedModel = UserDefaults.standard.string(forKey: "openRouterModel"),
           !savedModel.isEmpty {
            openRouterModel = savedModel
        }

        if let savedApiKey = UserDefaults.standard.string(forKey: openRouterApiKeyKey),
           !savedApiKey.isEmpty {
            openRouterCompressor = OpenRouterCompressor(apiKey: savedApiKey, model: openRouterModel)
        }

        if let savedCompressor = UserDefaults.standard.string(forKey: "selectedCompressor"),
           let type = CompressorType(rawValue: savedCompressor) {
            selectedCompressor = type
        }

        if let savedModelPath = UserDefaults.standard.url(forKey: localLLMModelURLKey),
           FileManager.default.fileExists(atPath: savedModelPath.path) {
            let resolvedModel = resolveSavedLocalModel(for: savedModelPath)
            selectedLocalModel = resolvedModel
            downloadedModelID = resolvedModel.id
            localLLMCompressor = LocalLLMCompressor(modelURL: savedModelPath)
            Task {
                isModelLoading = true
                try? await localLLMCompressor?.loadModel()
                isModelLoading = false
            }
        } else if let savedModelID = UserDefaults.standard.string(forKey: localLLMModelIDKey),
                  let model = LocalLLMModel.find(by: savedModelID) {
            selectedLocalModel = model
        }
    }

    private func resolveSavedLocalModel(for savedModelPath: URL) -> LocalLLMModel {
        if let inferredModel = LocalLLMModel.infer(from: savedModelPath) {
            UserDefaults.standard.set(inferredModel.id, forKey: localLLMModelIDKey)
            return inferredModel
        }

        if let savedModelID = UserDefaults.standard.string(forKey: localLLMModelIDKey),
           let savedModel = LocalLLMModel.find(by: savedModelID) {
            return savedModel
        }

        return .defaultModel
    }

    func checkAvailability() async {
        if let openRouter = openRouterCompressor {
            availableCompressors[.openRouter] = await openRouter.isAvailable
        } else {
            availableCompressors[.openRouter] = false
        }

        if let localLLM = localLLMCompressor {
            let localLLMAvailable = await localLLM.isAvailable
            availableCompressors[.localLLM] = isSelectedLocalModelDownloaded && localLLMAvailable
        } else {
            availableCompressors[.localLLM] = false
        }
    }

    func setOpenRouterApiKey(_ apiKey: String, model: String = "glm-5") {
        UserDefaults.standard.set(apiKey, forKey: openRouterApiKeyKey)

        openRouterModel = model
        UserDefaults.standard.set(model, forKey: "openRouterModel")

        openRouterCompressor = OpenRouterCompressor(apiKey: apiKey, model: model)
        Task {
            await checkAvailability()
        }
    }

    func saveSelectedCompressor(_ type: CompressorType) {
        selectedCompressor = type
        UserDefaults.standard.set(type.rawValue, forKey: "selectedCompressor")
    }

    /// Sets `selectedLocalModel`, which triggers the `didSet` observer to persist the
    /// selection to UserDefaults and re-evaluate availability. Public so that
    /// `OnboardingStore` can delegate model selection through this service.
    func selectLocalModel(_ model: LocalLLMModel) {
        selectedLocalModel = model
    }

    func downloadLocalLLMModel(_ model: LocalLLMModel? = nil) async throws {
        let model = model ?? selectedLocalModel
        logger.info("Starting model download: \(model.displayName)...")
        isDownloading = true
        modelDownloadProgress = 0

        var downloadSuccess = false
        defer {
            isDownloading = false
            if !downloadSuccess {
                modelDownloadProgress = 0
            }
        }

        let appContainer = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appContainer.appendingPathComponent("Vapor/Models", isDirectory: true)

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let modelURL = modelsDir.appendingPathComponent(model.fileName)
        let temporaryModelURL = modelURL.appendingPathExtension("download")

        guard let url = URL(string: model.downloadURL) else {
            logger.error("Invalid download URL: \(model.downloadURL)")
            throw CompressionError.unavailable
        }

        logger.info("Downloading from: \(url.absoluteString)")

        if FileManager.default.fileExists(atPath: temporaryModelURL.path) {
            try? FileManager.default.removeItem(at: temporaryModelURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Vapor/1.0", forHTTPHeaderField: "User-Agent")

        let delegate = DownloadDelegate()
        delegate.destinationURL = temporaryModelURL
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: OperationQueue.main)

        let task = session.downloadTask(with: request)
        task.resume()

        while !delegate.isFinished {
            if let total = delegate.totalBytesExpected, total > 0 {
                modelDownloadProgress = Double(delegate.bytesWritten) / Double(total)
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        if let error = delegate.error {
            try? FileManager.default.removeItem(at: temporaryModelURL)
            throw error
        }

        guard delegate.didCopySuccessfully else {
            logger.error("Download completed but file was not copied to destination")
            try? FileManager.default.removeItem(at: temporaryModelURL)
            throw CompressionError.unavailable
        }

        if let response = task.response as? HTTPURLResponse {
            logger.info("Model download completed with HTTP status: \(response.statusCode)")
        }

        do {
            let fileSize = try validateDownloadedModel(at: temporaryModelURL)
            logger.info("Validated GGUF download at \(temporaryModelURL.path) (\(fileSize) bytes)")
        } catch {
            try? FileManager.default.removeItem(at: temporaryModelURL)
            throw error
        }

        if FileManager.default.fileExists(atPath: modelURL.path) {
            _ = try FileManager.default.replaceItemAt(modelURL, withItemAt: temporaryModelURL)
        } else {
            try FileManager.default.moveItem(at: temporaryModelURL, to: modelURL)
        }

        logger.info("Model saved to: \(modelURL.path)")

        UserDefaults.standard.set(modelURL, forKey: localLLMModelURLKey)
        UserDefaults.standard.set(model.id, forKey: localLLMModelIDKey)
        selectedLocalModel = model
        downloadedModelID = model.id

        localLLMCompressor = LocalLLMCompressor(modelURL: modelURL)
        logger.info("Loading model...")
        try await localLLMCompressor?.loadModel()
        logger.info("Model loaded successfully!")

        downloadSuccess = true
        modelDownloadProgress = 1.0

        await checkAvailability()
    }

    private func validateDownloadedModel(at modelURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize >= minimumValidModelSizeBytes else {
            logger.error("Downloaded file too small to be a GGUF model: \(fileSize) bytes at \(modelURL.path)")
            throw CompressionError.apiError("Downloaded file was too small to be a valid GGUF model.")
        }

        let fileHandle = try FileHandle(forReadingFrom: modelURL)
        defer { try? fileHandle.close() }

        let magicData = try fileHandle.read(upToCount: 4) ?? Data()
        let magic = String(data: magicData, encoding: .ascii) ?? magicData.map { String(format: "%02X", $0) }.joined()

        logger.info("Downloaded model magic bytes: \(magic)")

        guard magic == "GGUF" else {
            logger.error("Invalid GGUF magic bytes: \(magic) at \(modelURL.path)")
            throw CompressionError.apiError("Downloaded file is not a valid GGUF model.")
        }

        return fileSize
    }

    func reloadLocalLLMIfNeeded() async {
        guard let savedModelPath = UserDefaults.standard.url(forKey: localLLMModelURLKey),
              FileManager.default.fileExists(atPath: savedModelPath.path) else { return }
        let resolvedModel = resolveSavedLocalModel(for: savedModelPath)
        selectedLocalModel = resolvedModel
        downloadedModelID = resolvedModel.id
        localLLMCompressor = LocalLLMCompressor(modelURL: savedModelPath)
        isModelLoading = true
        defer { isModelLoading = false }

        do {
            try await localLLMCompressor?.loadModel()
        } catch {
            logger.error("Failed to load local LLM model at \(savedModelPath.path): \(error.localizedDescription)")
        }

        await checkAvailability()

        if let saved = UserDefaults.standard.string(forKey: "selectedCompressor"),
           let type = CompressorType(rawValue: saved) {
            selectedCompressor = type
        }
    }

    func deleteLocalLLMModel() {
        if let savedModelPath = UserDefaults.standard.url(forKey: localLLMModelURLKey) {
            try? FileManager.default.removeItem(at: savedModelPath)
            logger.info("Deleted model at: \(savedModelPath.path)")
        }
        UserDefaults.standard.removeObject(forKey: localLLMModelURLKey)
        localLLMCompressor = nil
        availableCompressors[.localLLM] = false
        modelDownloadProgress = 0
        downloadedModelID = nil
    }

    private func activeModelName() -> String {
        switch selectedCompressor {
        case .openRouter: return openRouterModel
        case .localLLM: return selectedLocalModel.displayName
        }
    }

    private func modelName(for backend: CompressorType) -> String {
        switch backend {
        case .openRouter: return openRouterModel
        case .localLLM: return selectedLocalModel.displayName
        }
    }

    func compress(_ text: String) async throws -> CompressedResult {
        let backendName = "\(selectedCompressor.rawValue)"
        statusMessage = "Checking \(backendName)..."

        func runCompression() async throws -> (result: CompressedResult, backend: CompressorType, isFirstInference: Bool) {
            switch selectedCompressor {
            case .localLLM:
                guard isSelectedLocalModelDownloaded,
                      let localLLM = localLLMCompressor, await localLLM.isAvailable else {
                    throw CompressionError.unavailable
                }
                let key = "Local LLM (On-Device):\(selectedLocalModel.displayName)"
                let isFirst = telemetry.isFirstInference(for: key)
                statusMessage = isFirst ? "Cold loading \(selectedLocalModel.displayName)..." : "Compressing with \(selectedLocalModel.displayName)..."
                return (try await localLLM.compress(text), .localLLM, isFirst)
            case .openRouter:
                guard let openRouter = openRouterCompressor, await openRouter.isAvailable else {
                    throw CompressionError.unavailable
                }
                let key = "OpenRouter:\(openRouterModel)"
                let isFirst = telemetry.isFirstInference(for: key)
                statusMessage = "Compressing with OpenRouter (\(openRouterModel))..."
                return (try await openRouter.compress(text), .openRouter, isFirst)
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (result, actualBackend, isFirst) = try await runCompression()
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            telemetry.record(CompressionTiming(
                timestamp: Date(),
                backend: actualBackend,
                modelName: modelName(for: actualBackend),
                inputTokens: result.originalTokens,
                outputTokens: result.compressedTokens,
                ratio: result.ratio,
                duration: elapsed,
                isFirstInference: isFirst,
                success: true,
                errorMessage: nil
            ))

            statusMessage = "Done — \(result.originalTokens) → \(result.compressedTokens) tokens (\(Int((1 - result.ratio) * 100))%) in \(String(format: "%.1f", elapsed))s"
            scheduleReset()

            return result
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            telemetry.record(CompressionTiming(
                timestamp: Date(),
                backend: selectedCompressor,
                modelName: modelName(for: selectedCompressor),
                inputTokens: 0,
                outputTokens: 0,
                ratio: 0,
                duration: elapsed,
                isFirstInference: false,
                success: false,
                errorMessage: error.localizedDescription
            ))

            statusMessage = "Compression failed: \(error.localizedDescription)"
            throw error
        }
    }

    private func scheduleReset() {
        resetTask?.cancel()
        let currentMessage = statusMessage
        resetTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if statusMessage == currentMessage {
                statusMessage = "Ready"
            }
        }
    }
}
