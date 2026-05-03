import Foundation
import Speech
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

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasAudioTap: Bool = false
    private var hasDeliveredFinalResult: Bool = false
    private var isCancellationRequested: Bool = false

    var onTextUpdate: (@MainActor (String, Bool) -> Void)?
    var onError: (@MainActor (String) -> Void)?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
        if recognizer?.isAvailable == true {
            state = .ready
        }
        logger.debug("Initialized for locale: \(self.recognizer?.locale.identifier ?? "default"), available: \(self.recognizer?.isAvailable ?? false)")
    }

    // MARK: - Public API

    func toggleDictation(onTextUpdate: @escaping @MainActor (String, Bool) -> Void) {
        switch isDictating {
        case true:
            logger.debug("Toggle OFF (stop dictation)")
            stopDictation(commit: true)
        case false:
            logger.debug("Toggle ON (start dictation)")
            startDictation(onTextUpdate: onTextUpdate)
        }
    }

    func startDictation(onTextUpdate: @escaping @MainActor (String, Bool) -> Void) {
        startDictationInternal(onTextUpdate: onTextUpdate)
    }

    func pauseDictation() {
        logger.debug("Pausing dictation (Fn released), isDictating=\(self.isDictating)")
        if !currentTranscript.isEmpty {
            logger.debug("Committing partial transcript as final before pause")
            onTextUpdate?(currentTranscript, true)
        }
        isCancellationRequested = true
        teardownAudioSession(preserveErrorState: false)
        currentTranscript = ""
        onTextUpdate = nil
    }

    func stopDictation(commit: Bool) {
        if commit, !currentTranscript.isEmpty {
            onTextUpdate?(currentTranscript, true)
        }
        isCancellationRequested = true
        teardownAudioSession(preserveErrorState: false)
        onTextUpdate = nil
        currentTranscript = ""
    }

    func requestPermissionsIfNeeded() async {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        logger.debug("Speech auth status: \(speechStatus.rawValue)")

        switch speechStatus {
        case .notDetermined:
            state = .requestingPermission
            let requested = await requestSpeechAuthorization()
            logger.debug("Speech auth result: \(requested)")
            if !requested {
                state = .error("Speech recognition permission denied. Enable it in System Settings > Privacy & Security > Speech Recognition.")
                return
            }
        case .denied, .restricted:
            logger.warning("Speech auth denied or restricted")
            state = .error("Speech recognition permission denied. Enable it in System Settings > Privacy & Security > Speech Recognition.")
            return
        case .authorized:
            break
        @unknown default:
            state = .error("Speech recognition permission is in an unknown state.")
            return
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.debug("Mic auth status: \(micStatus.rawValue)")

        switch micStatus {
        case .notDetermined:
            let granted = await requestMicrophoneAuthorization()
            logger.debug("Mic auth result: \(granted)")
            if !granted {
                state = .error("Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone.")
                return
            }
        case .denied, .restricted:
            logger.warning("Mic auth denied or restricted")
            state = .error("Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone.")
            return
        case .authorized:
            break
        @unknown default:
            state = .error("Microphone permission is in an unknown state.")
            return
        }

        if case .requestingPermission = state {
            state = .ready
        } else if case .idle = state {
            state = .ready
        }
    }

    // MARK: - Private

    private func startDictationInternal(onTextUpdate: @escaping @MainActor (String, Bool) -> Void) {
        guard recognitionTask == nil else { return }

        state = .idle

        self.onTextUpdate = onTextUpdate
        currentTranscript = ""
        hasDeliveredFinalResult = false
        isCancellationRequested = false

        Task { @MainActor in
            await requestPermissionsIfNeeded()
            guard case .ready = state else {
                let msg = "Permissions not ready; state=\(String(describing: self.state))"
                logger.error("Dictation blocked: \(msg)")
                self.onError?(msg)
                return
            }

            guard let recognizer = self.recognizer, recognizer.isAvailable else {
                let msg = "Speech recognizer is not available on this Mac."
                logger.error("Dictation blocked: \(msg)")
                self.state = .error(msg)
                self.onError?(msg)
                return
            }

            self.teardownAudioSession(preserveErrorState: true)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Use on-device recognition when available: no network latency, better privacy.
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.recognitionRequest = request

            let inputNode = self.audioEngine.inputNode
            // 16 kHz mono Float32 — the sample rate speech models use internally.
            // This cuts tap callbacks from ~43/s (at 44 kHz) to ~15/s and halves
            // the buffer data, which directly reduces main-actor Task dispatches.
            let speechFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) ?? inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: speechFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                // RMS-based input level for the VU meter (mono, so always channel 0).
                let frameLength = Int(buffer.frameLength)
                if frameLength > 0, let floatChannelData = buffer.floatChannelData {
                    let ptr = floatChannelData[0]
                    var sum: Float = 0
                    for i in 0..<frameLength {
                        let sample = ptr[i]
                        sum += sample * sample
                    }
                    let rms = sqrtf(sum / Float(frameLength))

                    let minDb: Float = -60.0
                    let clampedRms = max(rms, 1e-5)
                    let db = 20.0 * log10f(clampedRms)
                    let clampedDb = max(minDb, db)
                    let normalized = (clampedDb - minDb) / -minDb

                    Task { @MainActor in
                        let smoothing: Float = 0.2
                        self.inputLevel = self.inputLevel * (1 - smoothing) + normalized * smoothing
                    }
                }

                self.recognitionRequest?.append(buffer)
            }
            self.hasAudioTap = true

            self.audioEngine.prepare()
            do {
                try self.audioEngine.start()
                logger.info("Audio engine started")
            } catch {
                let msg = "Failed to start audio engine: \(error.localizedDescription)"
                logger.error("Dictation blocked: \(msg)")
                self.state = .error(msg)
                self.onError?(msg)
                self.teardownAudioSession(preserveErrorState: true)
                return
            }

            self.isDictating = true
            self.state = .dictating
            logger.debug("State = dictating")

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.currentTranscript = transcript
                        self.onTextUpdate?(transcript, result.isFinal)
                        if result.isFinal {
                            self.hasDeliveredFinalResult = true
                            self.teardownAudioSession(preserveErrorState: false)
                            self.onTextUpdate = nil
                        }
                    }
                }

                if let error = error {
                    let errorMsg = error.localizedDescription
                    logger.error("Recognizer error: \(errorMsg)")
                    Task { @MainActor in
                        if self.isCancellationRequested || self.hasDeliveredFinalResult {
                            logger.debug("Ignoring error after normal termination")
                        } else {
                            let msg = "Speech recognition failed: \(errorMsg)"
                            logger.error("Dictation runtime error: \(msg)")
                            self.state = .error(msg)
                            self.teardownAudioSession(preserveErrorState: true)
                            self.onError?(msg)
                        }
                        self.onTextUpdate = nil
                    }
                }
            }
        }
    }

    private func teardownAudioSession(preserveErrorState: Bool) {
        audioEngine.stop()
        logger.debug("Audio engine stopped")
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        isDictating = false
        inputLevel = 0.0

        if !preserveErrorState {
            state = .ready
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                logger.debug("Speech auth callback: \(status.rawValue)")
                switch status {
                case .authorized:
                    continuation.resume(returning: true)
                default:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logger.debug("Mic auth callback: \(granted)")
                continuation.resume(returning: granted)
            }
        }
    }
}