import Foundation
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Compression")

@MainActor
private class OllamaPullDelegate: NSObject, URLSessionDataDelegate {
    var onStatus: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onDone: (() -> Void)?
    private var buffer = ""
    private var statusLineCount = 0
    private var finished = false

    private func markFinished() {
        guard !finished else { return }
        finished = true
        onStatus = nil
        onError = nil
        onDone = nil
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        logger.info("Ollama pull response: HTTP \(statusCode)")
        if statusCode != 200 {
            logger.error("Ollama pull unexpected status: HTTP \(statusCode)")
            let error = CompressionError.apiError("HTTP \(statusCode)")
            markFinished()
            onError?(error)
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard !finished else { return }
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk

        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
            buffer = String(buffer[newlineRange.upperBound...])

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }
            if let update = try? JSONDecoder().decode(OllamaPullResponse.self, from: lineData),
               let status = update.status {
                self.statusLineCount += 1
                if self.statusLineCount % 20 == 1 {
                    logger.info("Ollama pull status: \(status)")
                }
                onStatus?(status)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard !finished else { return }
        if let error = error {
            logger.error("Ollama pull completed with error: \(error.localizedDescription)")
            markFinished()
            onError?(error)
        } else {
            logger.info("Ollama pull completed successfully (\(self.statusLineCount) status lines)")
            markFinished()
            onDone?()
        }
    }
}

@MainActor
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
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
    var selectedCompressor: CompressorType = .foundationModels
    var availableCompressors: [CompressorType: Bool] = [:]
    var openRouterModel: String = "glm-5"
    var modelDownloadProgress: Double = 0
    var isDownloading: Bool = false
    var isModelLoading: Bool = false
    var ollamaModels: [OllamaTagsResponse.OllamaModel] = []
    var ollamaSelectedModel: String = "gemma4:e4b"
    var isOllamaPulling: Bool = false
    var ollamaPullProgress: String = ""
    var ollamaPullInProgress: String?
    var statusMessage: String = "Ready"

    private let defaultOllamaPort: UInt16 = 11434
    private let telemetry = CompressionTelemetry.shared
    private var resetTask: Task<Void, Never>?

    /// Whether the currently selected compressor is ready to compress.
    var isSelectedCompressorReady: Bool {
        switch selectedCompressor {
        case .ruleBased:
            return true
        case .foundationModels:
            return availableCompressors[.foundationModels] ?? false
        case .openRouter:
            return availableCompressors[.openRouter] ?? false
        case .localLLM:
            return availableCompressors[.localLLM] ?? false
        case .ollamaLLM:
            return availableCompressors[.ollamaLLM] ?? false
        }
    }

    private let ruleBasedCompressor = RuleBasedCompressor()
    #if canImport(FoundationModels)
    private var foundationModelsCompressor: FoundationModelsCompressor?
    #endif
    private var openRouterCompressor: OpenRouterCompressor?
    private var localLLMCompressor: LocalLLMCompressor?
    private var ollamaCompressor: OllamaCompressor?

    private let openRouterApiKeyKey = "openRouterApiKey"
    private let localLLMModelURLKey = "localLLMModelURL"
    private let ollamaSelectedModelKey = "ollamaSelectedModel"

    private let defaultModelURL = "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf"

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
            localLLMCompressor = LocalLLMCompressor(modelURL: savedModelPath)
            Task {
                isModelLoading = true
                try? await localLLMCompressor?.loadModel()
                isModelLoading = false
            }
        }

        if let savedOllamaModel = UserDefaults.standard.string(forKey: ollamaSelectedModelKey),
           !savedOllamaModel.isEmpty {
            ollamaSelectedModel = savedOllamaModel
            ollamaCompressor = OllamaCompressor(model: savedOllamaModel, port: defaultOllamaPort)
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

        availableCompressors[.ruleBased] = ruleBasedCompressor.isAvailable

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

        if let ollama = ollamaCompressor {
            availableCompressors[.ollamaLLM] = await ollama.isAvailable
        } else {
            availableCompressors[.ollamaLLM] = false
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

        let appContainer = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appContainer.appendingPathComponent("Vapor/Models", isDirectory: true)

        logger.debug("Models directory: \(modelsDir.path)")

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let modelURL = modelsDir.appendingPathComponent("Qwen2.5-7B-Instruct-Q4_K_M.gguf")

        logger.debug("Model will be saved to: \(modelURL.path)")

        guard let url = URL(string: defaultModelURL) else {
            logger.error("Invalid download URL: \(self.defaultModelURL)")
            throw CompressionError.unavailable
        }

        logger.info("Downloading from: \(url.absoluteString)")

        let delegate = DownloadDelegate()
        delegate.destinationURL = modelURL
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

        guard delegate.didCopySuccessfully else {
            logger.error("Download completed but file was not copied to destination")
            throw CompressionError.unavailable
        }

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

    /// Reload the local LLM compressor from UserDefaults (e.g., after an external download).
    func reloadLocalLLMIfNeeded() async {
        guard let savedModelPath = UserDefaults.standard.url(forKey: localLLMModelURLKey),
              FileManager.default.fileExists(atPath: savedModelPath.path) else { return }
        localLLMCompressor = LocalLLMCompressor(modelURL: savedModelPath)
        isModelLoading = true
        defer { isModelLoading = false }

        do {
            try await localLLMCompressor?.loadModel()
        } catch {
            logger.error("Failed to load local LLM model at \(savedModelPath.path): \(error.localizedDescription)")
        }

        await checkAvailability()

        // Also sync the selected compressor in case onboarding changed it
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
    }

    private func activeModelName() -> String {
        switch selectedCompressor {
        case .ollamaLLM: return ollamaSelectedModel
        case .openRouter: return openRouterModel
        case .localLLM: return "Qwen2.5-7B"
        case .foundationModels: return "System Default"
        case .ruleBased: return "Rule-Based"
        }
    }

    private func modelName(for backend: CompressorType) -> String {
        switch backend {
        case .ollamaLLM: return ollamaSelectedModel
        case .openRouter: return openRouterModel
        case .localLLM: return "Qwen2.5-7B"
        case .foundationModels: return "System Default"
        case .ruleBased: return "Rule-Based"
        }
    }

    func compress(_ text: String) async throws -> CompressedResult {
        let backendName = "\(selectedCompressor.rawValue)"
        statusMessage = "Checking \(backendName)..."

        func runCompression() async throws -> (result: CompressedResult, backend: CompressorType, isFirstInference: Bool) {
            switch selectedCompressor {
            case .foundationModels:
                #if canImport(FoundationModels)
                if #available(macOS 26, *) {
                    if let fm = foundationModelsCompressor, await fm.isAvailable {
                        let key = "Apple Foundation Models:System Default"
                        let isFirst = telemetry.isFirstInference(for: key)
                        statusMessage = isFirst ? "Cold loading Foundation Models..." : "Compressing with Foundation Models..."
                        return (try await fm.compress(text), .foundationModels, isFirst)
                    }
                }
                #endif
                statusMessage = "Foundation Models unavailable — using Rule-Based"
                return (try await ruleBasedCompressor.compress(text), .ruleBased, false)
            case .localLLM:
                if let localLLM = localLLMCompressor, await localLLM.isAvailable {
                    let key = "Local LLM (On-Device):Qwen2.5-7B"
                    let isFirst = telemetry.isFirstInference(for: key)
                    statusMessage = isFirst ? "Cold loading Local LLM..." : "Compressing with Local LLM..."
                    return (try await localLLM.compress(text), .localLLM, isFirst)
                }
                statusMessage = "Local LLM unavailable — using Rule-Based"
                return (try await ruleBasedCompressor.compress(text), .ruleBased, false)
            case .ollamaLLM:
                if let ollama = ollamaCompressor, await ollama.isAvailable {
                    let key = "Ollama (Local):\(ollamaSelectedModel)"
                    let isFirst = telemetry.isFirstInference(for: key)
                    statusMessage = isFirst ? "Cold loading \(ollamaSelectedModel)..." : "Compressing with Ollama (\(ollamaSelectedModel))..."
                    return (try await ollama.compress(text), .ollamaLLM, isFirst)
                }
                statusMessage = "Ollama unavailable — using Rule-Based"
                return (try await ruleBasedCompressor.compress(text), .ruleBased, false)
            case .openRouter:
                if let openRouter = openRouterCompressor, await openRouter.isAvailable {
                    let key = "OpenRouter:\(openRouterModel)"
                    let isFirst = telemetry.isFirstInference(for: key)
                    statusMessage = "Compressing with OpenRouter (\(openRouterModel))..."
                    return (try await openRouter.compress(text), .openRouter, isFirst)
                }
                statusMessage = "OpenRouter unavailable — using Rule-Based"
                return (try await ruleBasedCompressor.compress(text), .ruleBased, false)
            case .ruleBased:
                statusMessage = "Compressing with Rule-Based..."
                return (try await ruleBasedCompressor.compress(text), .ruleBased, false)
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

    // MARK: - Ollama Model Management

    func refreshOllamaModels() async {
        guard let url = URL(string: "http://127.0.0.1:\(defaultOllamaPort)/api/tags") else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            ollamaModels = tags.models
        } catch {
            ollamaModels = []
        }
        await checkAvailability()
    }

    func setOllamaModel(_ model: String) {
        ollamaSelectedModel = model
        UserDefaults.standard.set(model, forKey: ollamaSelectedModelKey)
        ollamaCompressor = OllamaCompressor(model: model, port: defaultOllamaPort)
        Task { await checkAvailability() }
    }

    private var activePullSession: URLSession?

    func pullOllamaModel(_ modelName: String) async throws {
        guard let url = URL(string: "http://127.0.0.1:\(defaultOllamaPort)/api/pull") else {
            throw CompressionError.unavailable
        }

        isOllamaPulling = true
        ollamaPullInProgress = modelName
        ollamaPullProgress = "Requesting..."
        logger.info("Starting Ollama model pull: \(modelName)")

        let body: [String: Any] = ["name": modelName, "stream": true]
        var request = URLRequest(url: url, timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: CompressionError.unavailable)
                return
            }
            let delegate = OllamaPullDelegate()
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: OperationQueue.main)
            self.activePullSession = session

            delegate.onStatus = { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.ollamaPullProgress = status
                }
            }
            delegate.onDone = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isOllamaPulling = false
                    self?.ollamaPullInProgress = nil
                    self?.ollamaPullProgress = ""
                    self?.activePullSession = nil
                    await self?.refreshOllamaModels()
                    continuation.resume()
                }
            }
            delegate.onError = { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.isOllamaPulling = false
                    self?.ollamaPullInProgress = nil
                    self?.ollamaPullProgress = ""
                    self?.activePullSession = nil
                    continuation.resume(throwing: error)
                }
            }

            logger.info("Ollama pull dataTask resumed")
            session.dataTask(with: request).resume()
        }
    }

    func deleteOllamaModel(_ modelName: String) async throws {
        guard let url = URL(string: "http://127.0.0.1:\(defaultOllamaPort)/api/delete") else {
            throw CompressionError.unavailable
        }

        let body: [String: Any] = ["name": modelName]
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CompressionError.apiError("Failed to delete model (HTTP \(statusCode))")
        }

        await refreshOllamaModels()
    }
}

struct OllamaPullResponse: Codable {
    let status: String?
}
