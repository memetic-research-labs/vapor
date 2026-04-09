import Foundation

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
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
        if let savedApiKey = KeychainService.load(key: openRouterApiKeyKey),
           !savedApiKey.isEmpty {
            openRouterCompressor = OpenRouterCompressor(apiKey: savedApiKey, model: openRouterModel)
        }
        
        if let savedModel = UserDefaults.standard.string(forKey: "openRouterModel"),
           !savedModel.isEmpty {
            openRouterModel = savedModel
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
            availableCompressors[.foundationModels] = await fm.isAvailable
            if await fm.isAvailable {
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
            print("Failed to save API key: \(error)")
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
        print("[CompressionService] Starting model download...")
        isDownloading = true
        modelDownloadProgress = 0
        defer { 
            isDownloading = false
        }
        
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = documentsDir.appendingPathComponent("Models", isDirectory: true)
        
        print("[CompressionService] Models directory: \(modelsDir.path)")
        
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        
        let modelURL = modelsDir.appendingPathComponent("Qwen2.5-3B-Instruct-Q4_K_M.gguf")
        
        print("[CompressionService] Model will be saved to: \(modelURL.path)")
        
        guard let url = URL(string: defaultModelURL) else {
            print("[CompressionService] Invalid URL: \(defaultModelURL)")
            throw CompressionError.unavailable
        }
        
        print("[CompressionService] Downloading from: \(url.absoluteString)")
        
        // Use delegate-based download for progress tracking
        let delegate = DownloadDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        
        let task = session.downloadTask(with: url)
        task.resume()
        
        // Wait for download with progress updates
        while !delegate.isFinished {
            if let total = delegate.totalBytesExpected, total > 0 {
                await MainActor.run {
                    modelDownloadProgress = Double(delegate.bytesWritten) / Double(total)
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        
        if let error = delegate.error {
            throw error
        }
        
        guard let localURL = delegate.localURL else {
            throw CompressionError.unavailable
        }
        
        print("[CompressionService] Download completed!")
        print("[CompressionService] Temporary file: \(localURL.path)")
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
        
        try FileManager.default.moveItem(at: localURL, to: modelURL)
        
        print("[CompressionService] Model saved to: \(modelURL.path)")
        
        UserDefaults.standard.set(modelURL, forKey: localLLMModelURLKey)
        
        await MainActor.run {
            modelDownloadProgress = 1.0
        }
        
        localLLMCompressor = LocalLLMCompressor(modelURL: modelURL)
        print("[CompressionService] Loading model...")
        try await localLLMCompressor?.loadModel()
        print("[CompressionService] Model loaded successfully!")
        
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
        case .localLLM:
            if let localLLM = localLLMCompressor, await localLLM.isAvailable {
                return try await localLLM.compress(text)
            }
        case .openRouter:
            if let openRouter = openRouterCompressor, await openRouter.isAvailable {
                return try await openRouter.compress(text)
            }
        case .ruleBased:
            return try await ruleBasedCompressor.compress(text)
        }
        
        return try await ruleBasedCompressor.compress(text)
    }
}
