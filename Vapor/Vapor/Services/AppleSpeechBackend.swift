import Foundation
import AVFoundation
import Speech
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "AppleSpeech")

/// STTBackend implementation that wraps `SFSpeechRecognizer` (Apple's built-in
/// speech recognition). Kept as a selectable fallback; users should prefer
/// `WhisperKitBackend` for guaranteed on-device processing.
@MainActor
final class AppleSpeechBackend: STTBackend {

    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasDeliveredFinalResult = false
    private var isCancellationRequested = false
    private var onTextUpdateCallback: ((String, Bool) -> Void)?

    var isAvailable: Bool {
        guard let r = recognizer else { return false }
        return r.isAvailable
    }

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
        logger.debug("Initialized for locale: \(self.recognizer?.locale.identifier ?? "default"), available: \(self.recognizer?.isAvailable ?? false)")
    }

    // MARK: - STTBackend

    func requestPermissions() async -> Bool {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        switch speechStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else {
                logger.warning("Speech recognition permission denied")
                return false
            }
        case .denied, .restricted:
            logger.warning("Speech recognition permission denied/restricted")
            return false
        @unknown default:
            return false
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            logger.warning("Microphone permission denied/restricted")
            return false
        @unknown default:
            return false
        }
    }

    func startRecognition(
        onTextUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (String) -> Void
    ) async throws {
        guard let recognizer, recognizer.isAvailable else {
            let msg = "Apple Speech recognizer is not available on this device."
            logger.error("\(msg)")
            throw STTError.backendUnavailable(msg)
        }

        hasDeliveredFinalResult = false
        isCancellationRequested = false
        onTextUpdateCallback = onTextUpdate

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.onTextUpdateCallback?(transcript, result.isFinal)
                    if result.isFinal {
                        self.hasDeliveredFinalResult = true
                    }
                }
            }

            if let error {
                let errorMsg = error.localizedDescription
                logger.error("Apple Speech error: \(errorMsg)")
                Task { @MainActor in
                    if !self.isCancellationRequested && !self.hasDeliveredFinalResult {
                        onError("Speech recognition failed: \(errorMsg)")
                    }
                }
            }
        }
        logger.debug("Apple Speech recognition started")
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stopRecognition(commit: Bool) async {
        isCancellationRequested = true
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        onTextUpdateCallback = nil
        logger.debug("Apple Speech recognition stopped (commit=\(commit))")
    }
}

/// Errors that STT backends can surface.
enum STTError: LocalizedError {
    case backendUnavailable(String)
    case permissionDenied(String)
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .backendUnavailable(let msg): return msg
        case .permissionDenied(let msg): return msg
        case .audioConversionFailed: return "Failed to convert audio to the required format."
        }
    }
}
