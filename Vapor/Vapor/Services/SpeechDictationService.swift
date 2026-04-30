import Foundation
import AVFoundation
import AppKit
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Dictation")

@MainActor
@Observable
final class SpeechDictationService {
    enum DictationState: Equatable {
        case idle
        case requestingPermission
        case ready
        case dictating
        case error(String)
    }

    private(set) var state: DictationState = .idle
    private(set) var isDictating: Bool = false
    private(set) var currentTranscript: String = ""
    private(set) var inputLevel: Float = 0.0

    private let audioEngine = AVAudioEngine()
    private var hasAudioTap: Bool = false
    private var isCancellationRequested: Bool = false

    var onTextUpdate: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Backend selection

    var preferences: UserPreferences?
    private var activeBackend: (any STTBackend)?

    /// Call once after creation to inject user preferences for backend selection.
    func configure(preferences: UserPreferences) {
        self.preferences = preferences
    }

    private func makeBackend() -> any STTBackend {
        switch preferences?.sttEngine ?? .whisperKit {
        case .whisperKit:
            return WhisperKitBackend()
        case .appleSpeech:
            return AppleSpeechBackend()
        }
    }

    // MARK: - Public API

    func toggleDictation(onTextUpdate: @escaping (String, Bool) -> Void) {
        switch isDictating {
        case true:
            logger.debug("Toggle OFF (stop dictation)")
            stopDictation(commit: true)
        case false:
            logger.debug("Toggle ON (start dictation)")
            startDictation(onTextUpdate: onTextUpdate)
        }
    }

    func startDictation(onTextUpdate: @escaping (String, Bool) -> Void) {
        startDictationInternal(onTextUpdate: onTextUpdate)
    }

    func pauseDictation() {
        logger.debug("Pausing dictation (Fn released), isDictating=\(self.isDictating)")
        if !currentTranscript.isEmpty {
            logger.debug("Committing partial transcript as final before pause")
            onTextUpdate?(currentTranscript, true)
        }
        isCancellationRequested = true
        Task { await teardownBackend(commit: false) }
        teardownAudioEngine(preserveErrorState: false)
        currentTranscript = ""
        onTextUpdate = nil
    }

    func stopDictation(commit: Bool) {
        if commit, !currentTranscript.isEmpty {
            onTextUpdate?(currentTranscript, true)
        }
        isCancellationRequested = true
        Task { await teardownBackend(commit: false) }
        teardownAudioEngine(preserveErrorState: false)
        onTextUpdate = nil
        currentTranscript = ""
    }

    func requestPermissionsIfNeeded() async {
        let backend = makeBackend()
        state = .requestingPermission
        let granted = await backend.requestPermissions()
        if granted {
            if case .requestingPermission = state { state = .ready }
            else if case .idle = state { state = .ready }
        } else {
            state = .error(permissionErrorMessage())
        }
    }

    // MARK: - Private

    private func permissionErrorMessage() -> String {
        switch preferences?.sttEngine ?? .whisperKit {
        case .whisperKit:
            return "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
        case .appleSpeech:
            return "Microphone or Speech Recognition access denied. Enable both in System Settings > Privacy & Security."
        }
    }

    private func startDictationInternal(onTextUpdate: @escaping (String, Bool) -> Void) {
        self.onTextUpdate = onTextUpdate
        currentTranscript = ""
        isCancellationRequested = false

        let backend = makeBackend()
        activeBackend = backend

        Task { @MainActor in
            let granted = await backend.requestPermissions()
            guard granted else {
                let msg = self.permissionErrorMessage()
                logger.error("Dictation blocked: \(msg)")
                self.state = .error(msg)
                self.onError?(msg)
                self.activeBackend = nil
                return
            }

            // For WhisperKit, verify that a model has been downloaded first.
            if backend is WhisperKitBackend,
               !WhisperModelManager.shared.isModelAvailable {
                let msg = "No Whisper model downloaded. Open Settings › Speech to download one."
                logger.error("Dictation blocked: \(msg)")
                self.state = .error(msg)
                self.onError?(msg)
                self.activeBackend = nil
                return
            }

            self.teardownAudioEngine(preserveErrorState: true)

            let inputNode = self.audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self else { return }

                // Input-level metering (RMS on channel 0).
                if let channelData = buffer.floatChannelData,
                   buffer.format.channelCount > 0,
                   buffer.frameLength > 0 {
                    let ptr = channelData[0]
                    let frameLength = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<frameLength { let s = ptr[i]; sum += s * s }
                    let rms = sqrtf(sum / Float(frameLength))
                    let minDb: Float = -60.0
                    let db = 20.0 * log10f(max(rms, 1e-5))
                    let normalized = (max(minDb, db) - minDb) / -minDb
                    Task { @MainActor in
                        let smoothing: Float = 0.2
                        self.inputLevel = self.inputLevel * (1 - smoothing) + normalized * smoothing
                    }
                }

                // Route buffer to the backend on the main actor to avoid data races.
                Task { @MainActor [weak self] in
                    self?.activeBackend?.processAudioBuffer(buffer)
                }
            }
            self.hasAudioTap = true

            self.audioEngine.prepare()
            do {
                try self.audioEngine.start()
                logger.info("Audio engine started")
            } catch {
                let msg = "Failed to start audio engine: \(error.localizedDescription)"
                logger.error("\(msg)")
                self.state = .error(msg)
                self.onError?(msg)
                self.teardownAudioEngine(preserveErrorState: true)
                self.activeBackend = nil
                return
            }

            do {
                try await backend.startRecognition(
                    onTextUpdate: { [weak self] text, isFinal in
                        guard let self else { return }
                        self.currentTranscript = text
                        self.onTextUpdate?(text, isFinal)
                        if isFinal {
                            self.teardownAudioEngine(preserveErrorState: false)
                            self.onTextUpdate = nil
                        }
                    },
                    onError: { [weak self] errorMsg in
                        guard let self else { return }
                        if !self.isCancellationRequested {
                            self.state = .error(errorMsg)
                            self.teardownAudioEngine(preserveErrorState: true)
                            self.onError?(errorMsg)
                        }
                        self.onTextUpdate = nil
                    }
                )
            } catch {
                let msg = error.localizedDescription
                logger.error("Backend startRecognition failed: \(msg)")
                self.state = .error(msg)
                self.onError?(msg)
                self.teardownAudioEngine(preserveErrorState: true)
                self.activeBackend = nil
                return
            }

            self.isDictating = true
            self.state = .dictating
            logger.debug("State = dictating (backend: \(String(describing: type(of: backend))))")
        }
    }

    private func teardownBackend(commit: Bool) async {
        guard let backend = activeBackend else { return }
        await backend.stopRecognition(commit: commit)
        activeBackend = nil
    }

    private func teardownAudioEngine(preserveErrorState: Bool) {
        audioEngine.stop()
        logger.debug("Audio engine stopped")
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }

        isDictating = false
        inputLevel = 0.0

        if !preserveErrorState {
            state = .ready
        }
    }
}