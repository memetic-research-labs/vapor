import Foundation
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Compression")

@MainActor
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var localURL: URL?
    var error: Error?
    var isFinished = false
    var bytesWritten: Int64 = 0
    var totalBytesExpected: Int64?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        localURL = location
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
    var selectedCompressor: CompressorType = .ruleBased
    var availableCompressors: [CompressorType: Bool] = [:]
    var openRouterModel: String = "glm-5"
    var modelDownloadProgress: Double = 0
    var isDownloading: Bool = false

    private let ruleBasedCompressor = RuleBasedCompressor()
    #if canImport(FoundationModels)
    private var foundationModelsCompressor: FoundationModelsCompressor?
    #endif
    private var openRouterCompressor: OpenRouterCompressor?
    private var localLLMCompressor: LocalLLMCompressor?

    private let openRouterApiKeyKey = "openRouterApiKey"
    private let localLLMModelURLKey = "localLLMModelURL"

    private let defaultModelURL = "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf"

    init() {
        loadSavedSettings()
        Task {
            await checkAvailability()
        }
    }

    private func loadSavedSettings() {
        // Load model name first so the compressor is created with the correct model.
        if let savedModel = UserDefaults.standard.string(forKey: "openRouterModel"),
           !savedModel.isEmpty {
            openRouterModel = savedModel
        }

        if let savedApiKey = KeychainService.load(key: openRouterApiKeyKey),
           !savedApiKey.isEmpty {
            openRouterCompressor = OpenRouterCompressor(apiKey: savedApiKey, model: openRouterModel)
        }

        if let savedCompressor = UserDefaults.standard.string(forKey: "selectedCompressor"),
           let type = CompressorType(rawValue: savedCompressor) {
            selectedCompressor = type
        }

        if let savedModelPath = UserDefaults.standard.url(forKey: localLLMModelURLKey),
           FileManager.default.fileExists(atPath: savedModelPath.path) {
            localLLMCompressor = LocalLLMCompressor(modelURL: savedModelPath)
            Task {
                try? await localLLMCompressor?.loadModel()
            }
        }
    }

    func checkAvailability() async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let fm = FoundationModelsCompressor()
            let fmAvailable = await fm.isAvailable
            availableCompressors[.foundationModels] = fmAvailable
            if fmAvailable {
                foundationModelsCompressor = fm
            }
        } else {
            availableCompressors[.foundationModels] = false
        }
        #else
        availableCompressors[.foundationModels] = false
        #endif

        availableCompressors[.ruleBased] = await ruleBasedCompressor.isAvailable

        if let openRouter = openRouterCompressor {
            availableCompressors[.openRouter] = await openRouter.isAvailable
        } else {
            availableCompressors[.openRouter] = false
        }

        if let localLLM = localLLMCompressor {
            availableCompressors[.localLLM] = await localLLM.isAvailable
        } else {
            availableCompressors[.localLLM] = false
        }
    }

    func setOpenRouterApiKey(_ apiKey: String, model: String = "glm-5") {
        do {
            try KeychainService.save(key: openRouterApiKeyKey, value: apiKey)
        } catch {
            logger.error("Failed to save API key: \(error)")
        }

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

    func downloadLocalLLMModel() async throws {
        logger.info("Starting model download...")
        isDownloading = true
        modelDownloadProgress = 0

        var downloadSuccess = false
        defer {
            isDownloading = false
            if !downloadSuccess {
                modelDownloadProgress = 0
            }
        }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = documentsDir.appendingPathComponent("Models", isDirectory: true)

        logger.debug("Models directory: \(modelsDir.path)")

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let modelURL = modelsDir.appendingPathComponent("Qwen2.5-3B-Instruct-Q4_K_M.gguf")

        logger.debug("Model will be saved to: \(modelURL.path)")

        guard let url = URL(string: defaultModelURL) else {
            logger.error("Invalid download URL: \(self.defaultModelURL)")
            throw CompressionError.unavailable
        }

        logger.info("Downloading from: \(url.absoluteString)")

        let delegate = DownloadDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: OperationQueue.main)

        let task = session.downloadTask(with: url)
        task.resume()

        while !delegate.isFinished {
            if let total = delegate.totalBytesExpected, total > 0 {
                modelDownloadProgress = Double(delegate.bytesWritten) / Double(total)
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        if let error = delegate.error {
            throw error
        }

        guard let localURL = delegate.localURL else {
            throw CompressionError.unavailable
        }

        logger.info("Download completed. Temporary file: \(localURL.path)")

        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }

        try FileManager.default.moveItem(at: localURL, to: modelURL)

        logger.info("Model saved to: \(modelURL.path)")

        UserDefaults.standard.set(modelURL, forKey: localLLMModelURLKey)

        localLLMCompressor = LocalLLMCompressor(modelURL: modelURL)
        logger.info("Loading model...")
        try await localLLMCompressor?.loadModel()
        logger.info("Model loaded successfully!")

        downloadSuccess = true
        modelDownloadProgress = 1.0

        await checkAvailability()
    }

    func compress(_ text: String) async throws -> CompressedResult {
        switch selectedCompressor {
        case .foundationModels:
            #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                if let fm = foundationModelsCompressor, await fm.isAvailable {
                    return try await fm.compress(text)
                }
            }
            #endif
            return try await ruleBasedCompressor.compress(text)
        case .localLLM:
            if let localLLM = localLLMCompressor, await localLLM.isAvailable {
                return try await localLLM.compress(text)
            }
            return try await ruleBasedCompressor.compress(text)
        case .openRouter:
            if let openRouter = openRouterCompressor, await openRouter.isAvailable {
                return try await openRouter.compress(text)
            }
            return try await ruleBasedCompressor.compress(text)
        case .ruleBased:
            return try await ruleBasedCompressor.compress(text)
        }
    }
}
