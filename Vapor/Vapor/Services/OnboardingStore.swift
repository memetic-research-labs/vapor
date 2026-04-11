import AVFoundation
import Speech
import SwiftUI

/// Observable state for the onboarding flow: tracks permission status and LLM download progress.
@MainActor
@Observable
final class OnboardingStore {

    // MARK: - Singleton

    static let shared = OnboardingStore()

    // MARK: - Permission state

    var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()

    var micGranted: Bool { micStatus == .authorized }
    var speechGranted: Bool { speechStatus == .authorized }
    var bothPermissionsGranted: Bool { micGranted && speechGranted }

    // MARK: - LLM download state (delegated to CompressionService)

    /// Dedicated CompressionService for the onboarding LLM download.
    private(set) var compressionService: CompressionService = CompressionService()

    var isDownloading: Bool { compressionService.isDownloading }
    var downloadProgress: Double { compressionService.modelDownloadProgress }
    var localLLMReady: Bool {
        compressionService.availableCompressors[.localLLM] ?? false
    }

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
        // Switch default compressor to Local LLM on successful download
        compressionService.saveSelectedCompressor(.localLLM)
        await compressionService.checkAvailability()
        // Notify any other services (e.g. main window) to reload the LLM
        NotificationCenter.default.post(name: .vaporLLMDownloadCompleted, object: nil)
    }

    // MARK: - System Settings

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
