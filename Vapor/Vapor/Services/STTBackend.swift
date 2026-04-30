import Foundation
import AVFoundation
import OSLog

/// Identifies the available speech-to-text engine choices.
enum STTEngineChoice: String, CaseIterable, Identifiable {
    case whisperKit = "whisperKit"
    case appleSpeech = "appleSpeech"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperKit: return "Whisper (On-Device)"
        case .appleSpeech: return "Apple Speech"
        }
    }

    var description: String {
        switch self {
        case .whisperKit:
            return "100% on-device via WhisperKit. Requires one-time model download. Apple Silicon only."
        case .appleSpeech:
            return "Built-in macOS speech recognition. May contact Apple servers on Intel Macs."
        }
    }
}

/// Protocol that both the WhisperKit and Apple Speech backends conform to.
/// `SpeechDictationService` owns the `AVAudioEngine` and metering; the backend
/// handles only recognition.
@MainActor
protocol STTBackend: AnyObject {

    /// Whether this backend is ready to transcribe right now
    /// (model downloaded, recognizer available, etc.).
    var isAvailable: Bool { get }

    /// Request all permissions this backend needs (mic, speech auth, etc.).
    /// Returns `true` if the session can proceed.
    func requestPermissions() async -> Bool

    /// Start a new recognition session.
    /// The backend must return quickly; long-running work should happen
    /// asynchronously via the callbacks.
    ///
    /// - Parameters:
    ///   - onTextUpdate: Invoked on `@MainActor` with `(text, isFinal)`.
    ///   - onError:      Invoked on `@MainActor` with a human-readable message.
    func startRecognition(
        onTextUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (String) -> Void
    ) async throws

    /// Feed a raw PCM buffer captured from `AVAudioEngine`.
    /// Implementations should be non-blocking; heavy work runs asynchronously.
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer)

    /// End the current recognition session.
    ///
    /// - Parameter commit: When `true`, deliver any pending transcript as final
    ///   before tearing down.
    func stopRecognition(commit: Bool) async
}
