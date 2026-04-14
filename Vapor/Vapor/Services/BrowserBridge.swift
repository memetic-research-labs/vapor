import Foundation
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "BrowserBridge")

struct InjectionResult {
    var success: Bool
    var platform: String
    var tabURL: String
    var timestamp: Date
}

@MainActor
@Observable
final class BrowserBridge {
    var isExtensionConnected: Bool = false
    var connectedClientCount: Int = 0
    var lastInjectionResult: InjectionResult?
    var lastError: String?
    var isRunning: Bool = false

    var serverPort: Int {
        get {
            UserDefaults.standard.object(forKey: UserPreferences.Keys.embeddedServerPort) as? Int ?? 8766
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserPreferences.Keys.embeddedServerPort)
        }
    }

    private var server: VaporEmbeddedServer?
    private var startTask: Task<Void, Never>?
    private static let tokenKey = "browserBridgeAuthToken"

    init() {}

    nonisolated func authToken() -> String {
        if let token = UserDefaults.standard.string(forKey: Self.tokenKey), !token.isEmpty {
            return token
        }
        let token = UUID().uuidString
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        return token
    }

    nonisolated func resetAuthToken() -> String {
        let token = UUID().uuidString
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        Task { @MainActor [weak self] in
            await self?.restartAfterTokenReset()
        }
        return token
    }

    func start() async {
        guard !isRunning, startTask == nil else { return }
        isRunning = true
        lastError = nil

        startTask = Task { [weak self] in
            guard let self else { return }
            let srv = VaporEmbeddedServer(port: self.serverPort)

            srv.sseHub.onClientCountChange { [weak self] count in
                Task { @MainActor [weak self] in
                    self?.connectedClientCount = count
                    self?.isExtensionConnected = count > 0
                }
            }

            do {
                try await srv.start(
                    authTokenProvider: { [weak self] in
                        guard let self else { return "" }
                        return self.authToken()
                    },
                    onResponse: { [weak self] json in
                        Task { @MainActor [weak self] in
                            self?.handleExtensionResponse(json)
                        }
                    }
                )
                guard !Task.isCancelled else {
                    try? await srv.stop()
                    return
                }
                self.server = srv
                logger.info("Browser bridge started on port \(self.serverPort)")
            } catch {
                self.isRunning = false
                self.lastError = error.localizedDescription
                logger.error("Failed to start embedded server: \(error.localizedDescription)")
            }
            self.startTask = nil
        }
    }

    func stop() async {
        startTask?.cancel()
        startTask = nil
        await server?.stop()
        server = nil
        isRunning = false
        isExtensionConnected = false
        connectedClientCount = 0
        logger.info("Browser bridge stopped")
    }

    private func restartAfterTokenReset() async {
        guard isRunning else { return }
        await stop()
        await start()
    }

    func sendPrompt(_ text: String, original: String? = nil, autoSubmit: Bool = false) {
        var payload: [String: Any] = [
            "type": "PROMPT_INJECT",
            "text": text,
            "autoSubmit": autoSubmit
        ]
        if let original {
            payload["original"] = original
        }
        server?.broadcast(event: "prompt", json: payload)
    }

    func sendCompressedPrompt(_ compressed: String, original: String, autoSubmit: Bool) {
        sendPrompt(compressed, original: original, autoSubmit: autoSubmit)
    }

    func activatePicker() {
        server?.broadcast(event: "prompt", json: [
            "type": "ACTIVATE_PICKER"
        ])
    }

    func handleExtensionResponse(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }

        switch type {
        case "PROMPT_INJECTED":
            let success = json["success"] as? Bool ?? false
            let platform = json["platform"] as? String ?? "unknown"
            let tabURL = json["tabUrl"] as? String ?? ""
            lastInjectionResult = InjectionResult(
                success: success,
                platform: platform,
                tabURL: tabURL,
                timestamp: Date()
            )
            logger.info("Prompt injected: \(success) on \(platform)")

        case "TARGET_SELECTED":
            let domain = json["domain"] as? String ?? ""
            let selector = json["selector"] as? String ?? ""
            logger.info("Pinned target: \(domain) -> \(selector)")

        case "PICKER_CANCELLED":
            logger.info("Picker cancelled")

        default:
            logger.debug("Unknown extension response type: \(type)")
        }
    }
}
