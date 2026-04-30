import Foundation
import AVFoundation
import WhisperKit
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "WhisperKit")

/// A shared loader that holds the single `WhisperKit` inference pipeline instance
/// so that the model is loaded only once per session (model loading is expensive).
@MainActor
final class WhisperKitLoader {

    static let shared = WhisperKitLoader()
    private init() {}

    private var cachedModel: WhisperKit?
    private var cachedModelName: String?

    /// Return the cached pipeline if it matches `modelName`, otherwise load a new one.
    func loadModel(named modelName: String) async throws -> WhisperKit {
        if let existing = cachedModel, cachedModelName == modelName {
            return existing
        }
        logger.info("Loading WhisperKit model: \(modelName)")
        let pipeline = try await WhisperKit(model: modelName)
        cachedModel = pipeline
        cachedModelName = modelName
        logger.info("WhisperKit model ready: \(modelName)")
        return pipeline
    }

    /// Evict the cached pipeline (e.g. after a model size change).
    func evict() {
        cachedModel = nil
        cachedModelName = nil
    }
}

// MARK: -

/// `STTBackend` implementation powered by WhisperKit (on-device CoreML inference).
///
/// Audio flow:
///   1. `SpeechDictationService` feeds raw `AVAudioPCMBuffer` buffers via
///      `processAudioBuffer(_:)` at the hardware sample rate.
///   2. `WhisperKitBackend` converts each buffer to 16 kHz mono `[Float]` using
///      `AVAudioConverter`.
///   3. Samples accumulate in a ring buffer; a timer fires every `inferenceInterval`
///      seconds and runs incremental WhisperKit inference.
///   4. When `stopRecognition(commit:)` is called, a final inference pass is made
///      on all buffered audio and the result is delivered with `isFinal == true`.
@MainActor
final class WhisperKitBackend: STTBackend {

    // MARK: - Configuration

    /// How often (in seconds) partial inference is triggered while recording.
    private let inferenceInterval: TimeInterval = 2.0

    /// Maximum audio kept in the ring buffer (seconds). Older audio is dropped.
    private let maxBufferDuration: TimeInterval = 30.0

    // MARK: - State

    private var whisperKit: WhisperKit?

    /// Accumulated 16 kHz mono samples.
    private var audioBuffer: [Float] = []

    /// Timer that drives incremental inference.
    private var inferenceTimer: Timer?

    /// Callbacks set by `startRecognition`.
    private var onTextUpdateCallback: ((String, Bool) -> Void)?
    private var onErrorCallback: ((String) -> Void)?

    /// Most recently delivered partial transcript.
    private var latestPartialTranscript: String = ""

    /// Whether recognition is active.
    private var isRecognising: Bool = false

    // MARK: - Audio conversion

    private var audioConverter: AVAudioConverter?
    private static let targetSampleRate: Double = 16_000
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    // MARK: - STTBackend

    var isAvailable: Bool {
        whisperKit != nil || WhisperModelManager.shared.isModelAvailable
    }

    func requestPermissions() async -> Bool {
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
            return false
        @unknown default:
            return false
        }
    }

    func startRecognition(
        onTextUpdate: @escaping (String, Bool) -> Void,
        onError: @escaping (String) -> Void
    ) async throws {
        guard !isRecognising else { return }

        onTextUpdateCallback = onTextUpdate
        onErrorCallback = onError
        latestPartialTranscript = ""
        audioBuffer = []
        isRecognising = true

        // Load the model (returns from cache if already loaded).
        do {
            let modelName = WhisperModelManager.shared.selectedModelName
            whisperKit = try await WhisperKitLoader.shared.loadModel(named: modelName)
            logger.debug("WhisperKit model loaded, starting recognition")
        } catch {
            isRecognising = false
            let msg = "Failed to load Whisper model: \(error.localizedDescription)"
            logger.error("\(msg)")
            throw STTError.backendUnavailable(msg)
        }

        // Schedule periodic partial inference.
        inferenceTimer = Timer.scheduledTimer(withTimeInterval: inferenceInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.runPartialInference()
            }
        }
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecognising else { return }
        let samples = convertToWhisperFormat(buffer)
        audioBuffer.append(contentsOf: samples)

        // Trim old audio to stay within maxBufferDuration using replaceSubrange (O(n) copy avoided).
        let maxSamples = Int(Self.targetSampleRate * maxBufferDuration)
        if audioBuffer.count > maxSamples {
            audioBuffer.replaceSubrange(0..<(audioBuffer.count - maxSamples), with: [])
        }
    }

    func stopRecognition(commit: Bool) async {
        inferenceTimer?.invalidate()
        inferenceTimer = nil
        isRecognising = false

        if commit {
            await runFinalInference()
        }

        audioBuffer = []
        onTextUpdateCallback = nil
        onErrorCallback = nil
        logger.debug("WhisperKit recognition stopped (commit=\(commit))")
    }

    // MARK: - Inference

    private func runPartialInference() async {
        guard isRecognising, let pipe = whisperKit, !audioBuffer.isEmpty else { return }

        do {
            let results = try await pipe.transcribe(audioArray: audioBuffer)
            let text = (results.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, text != latestPartialTranscript {
                latestPartialTranscript = text
                onTextUpdateCallback?(text, false)
            }
        } catch {
            logger.debug("Partial inference skipped: \(error.localizedDescription)")
        }
    }

    private func runFinalInference() async {
        guard let pipe = whisperKit, !audioBuffer.isEmpty else {
            if !latestPartialTranscript.isEmpty {
                onTextUpdateCallback?(latestPartialTranscript, true)
            }
            return
        }

        do {
            let results = try await pipe.transcribe(audioArray: audioBuffer)
            let text = (results.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let finalText = text.isEmpty ? latestPartialTranscript : text
            onTextUpdateCallback?(finalText, true)
            logger.debug("Final transcript: \(finalText.prefix(80))")
        } catch {
            logger.error("Final inference failed: \(error.localizedDescription)")
            // Deliver the best partial result we have rather than nothing.
            onTextUpdateCallback?(latestPartialTranscript, true)
        }
    }

    // MARK: - Audio format conversion

    /// Convert a hardware-format `AVAudioPCMBuffer` to 16 kHz mono `[Float]`.
    private func convertToWhisperFormat(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let inputFormat = buffer.format
        let targetFormat = Self.targetFormat

        // Rebuild converter if input format changed (e.g. after audio route change).
        if audioConverter?.inputFormat != inputFormat {
            audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
            if audioConverter == nil {
                logger.warning("Could not create AVAudioConverter; using raw channel 0")
                return extractChannel0(from: buffer)
            }
        }

        guard let converter = audioConverter else {
            return extractChannel0(from: buffer)
        }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio))

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            return extractChannel0(from: buffer)
        }

        var convertError: NSError?
        var inputConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: outputBuffer, error: &convertError, withInputFrom: inputBlock)

        if let err = convertError {
            logger.debug("Audio conversion error (non-fatal): \(err.localizedDescription)")
            return extractChannel0(from: buffer)
        }

        return extractChannel0(from: outputBuffer)
    }

    /// Extract channel 0 as a `[Float]` array, clamping to ±1.0.
    private func extractChannel0(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        var samples = [Float]()
        samples.reserveCapacity(frameLength)
        let ch = channelData[0]
        for i in 0..<frameLength {
            samples.append(max(-1.0, min(ch[i], 1.0)))
        }
        return samples
    }
}
