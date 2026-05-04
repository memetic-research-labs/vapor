import Foundation
import OSLog

nonisolated private let captureLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "SessionCapture")

@MainActor
@Observable
final class SessionCaptureFacade {
    static let shared = SessionCaptureFacade()

    private var adapters: [String: any SessionCaptureAdapter] = [:]

    private(set) var isCapturing = false
    var isPaused = false

    private init() {}

    func registerAdapter(_ adapter: any SessionCaptureAdapter) {
        adapters[adapter.toolName] = adapter
    }

    func unregisterAdapter(toolName: String) {
        adapters.removeValue(forKey: toolName)
    }

    func startAll() async {
        guard !isCapturing else { return }

        for (toolName, adapter) in adapters {
            guard await adapter.isAvailable() else {
                captureLogger.debug("Adapter \(toolName) not available, skipping")
                continue
            }
            do {
                try await adapter.startCapture()
                captureLogger.info("Started capture adapter: \(toolName)")
            } catch {
                captureLogger.error("Failed to start adapter \(toolName): \(error.localizedDescription, privacy: .public)")
                StatusBarService.shared.log(
                    "Failed to start \(toolName) capture",
                    domain: .system,
                    level: .error,
                    metadata: ["error": error.localizedDescription]
                )
            }
        }

        let runningCount = adapters.values.filter { $0.isRunning }.count
        isCapturing = runningCount > 0

        if isCapturing {
            StatusBarService.shared.log("Session capture started (\(runningCount) adapter(s))", domain: .system, level: .success)
        }
    }

    func stopAll() async {
        for (toolName, adapter) in adapters {
            guard adapter.isRunning else { continue }
            await adapter.stopCapture()
            captureLogger.info("Stopped capture adapter: \(toolName)")
        }

        isCapturing = false
        StatusBarService.shared.log("Session capture stopped", domain: .system, level: .info)
    }

    func stopAdapter(for toolName: String) async {
        guard let adapter = adapters[toolName] else { return }
        await adapter.stopCapture()
        isCapturing = adapters.values.contains { $0.isRunning }
        StatusBarService.shared.log("Stopped \(toolName) capture", domain: .system, level: .info)
    }

    func handleCapturedTurn(_ turn: CapturedTurn) {
        guard !isPaused else { return }
        Task { @MainActor in
            await AISessionService.shared.handleTurn(turn)
        }
    }
}
