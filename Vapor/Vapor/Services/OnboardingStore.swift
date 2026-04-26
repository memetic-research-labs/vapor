import AVFoundation
import Speech
import SwiftUI

struct CompressionModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let priceLabel: String

    static let curatedModels: [CompressionModelOption] = [
        CompressionModelOption(id: "z-ai/glm-5", displayName: "GLM-5", priceLabel: "$0.00/M"),
        CompressionModelOption(id: "deepseek/deepseek-chat-v3-0324:free", displayName: "DeepSeek V3 (Free)", priceLabel: "Free"),
        CompressionModelOption(id: "google/gemma-3n-e4b-it", displayName: "Gemma 3N E4B", priceLabel: "$0.02/M"),
        CompressionModelOption(id: "meta-llama/llama-3.1-8b-instruct", displayName: "Llama 3.1 8B", priceLabel: "$0.02/M"),
        CompressionModelOption(id: "google/gemma-3-4b-it", displayName: "Gemma 3 4B", priceLabel: "$0.04/M"),
        CompressionModelOption(id: "qwen/qwen3-8b", displayName: "Qwen 3 8B", priceLabel: "$0.05/M"),
        CompressionModelOption(id: "anthropic/claude-sonnet-4", displayName: "Claude Sonnet 4", priceLabel: "$3.00/M"),
        CompressionModelOption(id: "openai/gpt-4.1-mini", displayName: "GPT-4.1 Mini", priceLabel: "$0.40/M"),
    ]
}

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

    var selectedLocalModel: LocalLLMModel {
        get { compressionService.selectedLocalModel }
        set { compressionService.selectLocalModel(newValue) }
    }

    var isDownloading: Bool { compressionService.isDownloading }
    var downloadProgress: Double { compressionService.modelDownloadProgress }
    var localLLMReady: Bool {
        compressionService.availableCompressors[.localLLM] ?? false
    }

    // MARK: - LLM path selection

    var selectedLLMPath: LLMPath = .localGGUF

    enum LLMPath: String, CaseIterable {
        case localGGUF

        var displayName: String {
            switch self {
            case .localGGUF: "Download Local Model"
            }
        }

        var subtitle: String {
            switch self {
            case .localGGUF: "Free, runs entirely on your Mac"
            }
        }

        var icon: String {
            switch self {
            case .localGGUF: "cube.box"
            }
        }
    }

    // MARK: - OpenRouter state

    var openRouterApiKey: String = ""
    var openRouterCompressionModel: String = "glm-5"
    var selectedCompressionModel: CompressionModelOption = CompressionModelOption.curatedModels[0]
    var useCustomCompressionModel: Bool = false
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

    func downloadLocalLLM(_ model: LocalLLMModel? = nil) async throws {
        try await compressionService.downloadLocalLLMModel(model)
        compressionService.saveSelectedCompressor(.localLLM)
        NotificationCenter.default.post(name: .vaporLLMDownloadCompleted, object: nil)
    }

    // MARK: - OpenRouter

    func saveOpenRouterConfig() {
        UserDefaults.standard.set(openRouterApiKey, forKey: "openRouterApiKey")
        let compressionModel = useCustomCompressionModel ? openRouterCompressionModel : selectedCompressionModel.id
        compressionService.setOpenRouterApiKey(openRouterApiKey, model: compressionModel)
        compressionService.saveSelectedCompressor(.openRouter)

        let nerModel = useCustomNERModel ? customNERModel : selectedNERModel.id
        UserDefaults.standard.set(nerModel, forKey: "entityExtractionModel")
        UserDefaults.standard.set(EntityExtractionBackend.openRouter.rawValue, forKey: "entityExtractionBackend")
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

    func skipOpenRouter() {}

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
