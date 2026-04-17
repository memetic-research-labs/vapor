import AVFoundation
import Speech
import SwiftUI

@MainActor
@Observable
final class OnboardingStore {

    static let shared = OnboardingStore()

    // MARK: - Permission state

    var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()

    var micGranted: Bool { micStatus == .authorized }
    var speechGranted: Bool { speechStatus == .authorized }
    var bothPermissionsGranted: Bool { micGranted && speechGranted }

    // MARK: - LLM download state (delegated to CompressionService)

    private(set) var compressionService: CompressionService = CompressionService()

    var isDownloading: Bool { compressionService.isDownloading }
    var downloadProgress: Double { compressionService.modelDownloadProgress }
    var localLLMReady: Bool {
        compressionService.availableCompressors[.localLLM] ?? false
    }

    // MARK: - Ollama state

    var isOllamaRunning = false
    var ollamaModels: [String] = []
    var selectedOllamaModel: String? = nil
    private var isCheckingOllama = false

    // MARK: - LLM path selection

    var selectedLLMPath: LLMPath = .ollama

    enum LLMPath: String, CaseIterable {
        case ollama = "ollama"
        case localGGUF = "localGGUF"

        var displayName: String {
            switch self {
            case .ollama: "Ollama (Recommended)"
            case .localGGUF: "Local GGUF (Offline)"
            }
        }

        var subtitle: String {
            switch self {
            case .ollama: "Free, fast, uses your Mac's GPU"
            case .localGGUF: "No daemon needed, but slower startup"
            }
        }

        var icon: String {
            switch self {
            case .ollama: "desktopcomputer"
            case .localGGUF: "cube.box"
            }
        }
    }

    // MARK: - OpenRouter state

    var openRouterApiKey: String = ""
    var openRouterCompressionModel: String = "glm-5"
    var selectedNERModel: NERModel = NERModel.curatedModels.first ?? NERModel(id: NERModel.defaultModel, displayName: NERModel.defaultModel, priceLabel: "")
    var useCustomNERModel: Bool = false
    var customNERModel: String = ""
    var isTestingOpenRouter = false
    var openRouterTestResult: String? = nil

    // MARK: - Init

    private init() {}

    // MARK: - Permission request helpers

    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    func requestSpeechRecognitionAccess() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    func requestAllPermissions() {
        requestMicrophoneAccess()
        requestSpeechRecognitionAccess()
    }

    func refreshPermissions() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - LLM download

    func downloadLocalLLM() async throws {
        try await compressionService.downloadLocalLLMModel()
        compressionService.saveSelectedCompressor(.localLLM)
        NotificationCenter.default.post(name: .vaporLLMDownloadCompleted, object: nil)
    }

    // MARK: - Ollama detection

    func checkOllama() {
        guard !isCheckingOllama else { return }
        isCheckingOllama = true
        Task {
            defer { isCheckingOllama = false }
            do {
                let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:11434/api/tags")!)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    await MainActor.run { isOllamaRunning = false }
                    return
                }
                let result = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data)
                await MainActor.run {
                    isOllamaRunning = true
                    ollamaModels = result?.models.map(\.name) ?? []
                    if let qwen = ollamaModels.first(where: { $0.contains("qwen2.5") || $0.contains("qwen3") }) {
                        selectedOllamaModel = qwen
                    } else if let first = ollamaModels.first {
                        selectedOllamaModel = first
                    }
                }
            } catch {
                await MainActor.run { isOllamaRunning = false }
            }
        }
    }

    func saveOllamaSelection() {
        if let model = selectedOllamaModel {
            compressionService.saveSelectedCompressor(.ollamaLLM)
            UserDefaults.standard.set(model, forKey: "ollamaSelectedModel")
        }
    }

    // MARK: - OpenRouter

    func saveOpenRouterConfig() {
        UserDefaults.standard.set(openRouterApiKey, forKey: "openRouterApiKey")
        compressionService.setOpenRouterApiKey(openRouterApiKey, model: openRouterCompressionModel)

        let nerModel = useCustomNERModel ? customNERModel : selectedNERModel.id
        UserDefaults.standard.set(nerModel, forKey: "entityExtractionModel")
        UserDefaults.standard.set(EntityExtractionBackend.openRouter.rawValue, forKey: "entityExtractionBackend")
    }

    func saveExtractionBackendAsOllama() {
        UserDefaults.standard.set(EntityExtractionBackend.ollama.rawValue, forKey: "entityExtractionBackend")
    }

    func testOpenRouterAPIKey() {
        guard !openRouterApiKey.isEmpty else {
            openRouterTestResult = "Enter an API key first"
            return
        }
        isTestingOpenRouter = true
        openRouterTestResult = nil
        let key = openRouterApiKey
        Task {
            defer { isTestingOpenRouter = false }
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    openRouterTestResult = "Connection failed"
                    return
                }
                if httpResponse.statusCode == 200 {
                    let result = try? JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
                    let count = result?.data?.count ?? 0
                    openRouterTestResult = "Valid — \(count) models available"
                } else if httpResponse.statusCode == 401 {
                    openRouterTestResult = "Invalid API key"
                } else {
                    openRouterTestResult = "Error \(httpResponse.statusCode)"
                }
            } catch {
                openRouterTestResult = "Failed: \(error.localizedDescription)"
            }
        }
    }

    func skipOpenRouter() {
        if selectedLLMPath == .ollama && isOllamaRunning {
            saveExtractionBackendAsOllama()
        }
    }

    // MARK: - System Settings

    func openSystemSettings() {
        refreshPermissions()

        let urlStrings: [String]

        if !speechGranted && micGranted {
            urlStrings = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            ]
        } else if !micGranted && speechGranted {
            urlStrings = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
            ]
        } else {
            urlStrings = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
            ]
        }

        for urlString in urlStrings {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

private struct OpenRouterModelsResponse: Codable {
    let data: [OpenRouterModel]?

    struct OpenRouterModel: Codable {
        let id: String
    }
}
