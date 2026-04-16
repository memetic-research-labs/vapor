import Foundation
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "BrowserBridge")

struct InjectionResult {
    var success: Bool
    var platform: String
    var tabURL: String
    var tabID: Int?
    var timestamp: Date
    var submitMethod: String?
    var submitConfidence: String?
    var autoSubmitted: Bool?
}

private struct PendingPromptRequest {
    let text: String
    let original: String?
    let autoSubmit: Bool
}

final class ContextStatusCache: @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func get(_ jobId: String) -> String? {
        lock.withLock { storage[jobId] }
    }

    func set(_ jobId: String, _ status: String) {
        lock.withLock { storage[jobId] = status }
    }
}

@MainActor
@Observable
final class BrowserBridge {
    var isExtensionConnected: Bool = false
    var connectedClientCount: Int = 0
    var lastInjectionResult: InjectionResult?
    var lastError: String?
    var isRunning: Bool = false
    var portConflict: Bool = false
    var availableTabs: [BrowserTab] = []
    var isPresentingTabPicker: Bool = false
    var selectedTarget: BrowserTarget?

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
    private static let selectedTargetKey = "browserBridgeSelectedTarget"
    private var contextQueueService: ContextQueueService?
    let contextStatusCache = ContextStatusCache()
    private var pendingPromptRequest: PendingPromptRequest?

    init() {
        selectedTarget = Self.loadSelectedTarget()
    }

    func setContextQueueService(_ service: ContextQueueService) {
        self.contextQueueService = service
    }

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
        portConflict = false

        startTask = Task { [weak self] in
            guard let self else { return }
            let maxRetries = 2
            let retryDelay: UInt64 = 1_000_000_000

            for attempt in 0...maxRetries {
                guard !Task.isCancelled else { return }
                let srv = VaporEmbeddedServer(port: self.serverPort)

                srv.sseHub.onClientCountChange { [weak self] count in
                    Task { @MainActor [weak self] in
                        let wasConnected = self?.isExtensionConnected ?? false
                        self?.connectedClientCount = count
                        self?.isExtensionConnected = count > 0
                        if count > 0 {
                            StatusBarService.shared.updateBrowserIndicator(connected: true)
                            StatusBarService.shared.setTransient("Browser extension connected")
                            if wasConnected == false {
                                self?.verifySelectedTarget()
                            }
                        } else {
                            StatusBarService.shared.updateBrowserIndicator(connected: false)
                        }
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
                        },
                        onContextCapture: { [weak self] json in
                            Task { @MainActor [weak self] in
                                self?.handleContextCapture(json)
                            }
                        },
                        contextItemStatusProvider: { [weak cache = self.contextStatusCache] jobId in
                            cache?.get(jobId)
                        }
                    )
                    guard !Task.isCancelled else {
                        try? await srv.stop()
                        return
                    }
                    self.server = srv
                    logger.info("Browser bridge started on port \(self.serverPort)")
                    return
                } catch {
                    let nsError = error as NSError
                    let isPortConflict = nsError.domain == "NIOCore.IOError" && nsError.code == 1
                    if isPortConflict && attempt < maxRetries {
                        logger.warning("Port \(self.serverPort) busy, retrying in 1s (attempt \(attempt + 1))")
                        try? await srv.stop()
                        try? await Task.sleep(nanoseconds: retryDelay)
                        continue
                    }
                    self.isRunning = false
                    self.lastError = error.localizedDescription
                    self.portConflict = isPortConflict
                    logger.error("Failed to start embedded server: \(error.localizedDescription)")
                    return
                }
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
        StatusBarService.shared.updateBrowserIndicator(connected: false)
        logger.info("Browser bridge stopped")
    }

    private func restartAfterTokenReset() async {
        guard isRunning else { return }
        await stop()
        await start()
    }

    @discardableResult
    func sendPrompt(_ text: String, original: String? = nil, autoSubmit: Bool = false) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let request = PendingPromptRequest(text: text, original: original, autoSubmit: autoSubmit)
        guard canPostToSelectedTarget else {
            pendingPromptRequest = request
            queryTabs()
            return false
        }

        return post(request)
    }

    @discardableResult
    func sendCompressedPrompt(_ compressed: String, original: String, autoSubmit: Bool) -> Bool {
        sendPrompt(compressed, original: original, autoSubmit: autoSubmit)
    }

    func queryTabs() {
        guard isExtensionConnected else {
            lastError = "No browser extension connected"
            return
        }
        StatusBarService.shared.setTransient("Fetching browser tabs")
        server?.broadcast(event: "prompt", json: [
            "type": "QUERY_TABS"
        ])
    }

    func selectTab(_ tab: BrowserTab) {
        selectedTarget = BrowserTarget(tab: tab)
        persistSelectedTarget()
        isPresentingTabPicker = false
        availableTabs = []
        StatusBarService.shared.setTransient("Target set to \(tab.displayHost)")

        if let pendingPromptRequest {
            self.pendingPromptRequest = nil
            _ = post(pendingPromptRequest)
        }
    }

    func dismissTabPicker() {
        isPresentingTabPicker = false
        availableTabs = []
        pendingPromptRequest = nil
    }

    func verifySelectedTarget() {
        guard isExtensionConnected, let selectedTarget else { return }
        server?.broadcast(event: "prompt", json: [
            "type": "VERIFY_TARGET",
            "host": selectedTarget.host,
            "url": selectedTarget.url
        ])
    }

    func openSelectedTarget() {
        guard isExtensionConnected, let selectedTarget else { return }
        let reopenURL = selectedTarget.reopenURL
        guard !reopenURL.isEmpty else { return }
        StatusBarService.shared.setTransient("Opening \(selectedTarget.displayLabel)")
        var payload: [String: Any] = [
            "type": "OPEN_TAB",
            "url": reopenURL
        ]
        if !selectedTarget.host.isEmpty {
            payload["host"] = selectedTarget.host
        }
        server?.broadcast(event: "prompt", json: payload)
    }

    var canPostToSelectedTarget: Bool {
        isExtensionConnected && selectedTarget?.isConnected == true && selectedTarget?.tabID != nil
    }

    var canReopenSelectedTarget: Bool {
        isExtensionConnected && selectedTarget != nil && selectedTarget?.isConnected == false
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
            let tabID = json["tabId"] as? Int
            let submitMethod = json["submitMethod"] as? String
            let submitConfidence = json["submitConfidence"] as? String
            let autoSubmitted = json["autoSubmitted"] as? Bool
            lastInjectionResult = InjectionResult(
                success: success,
                platform: platform,
                tabURL: tabURL,
                tabID: tabID,
                timestamp: Date(),
                submitMethod: submitMethod,
                submitConfidence: submitConfidence,
                autoSubmitted: autoSubmitted
            )
            if success, let tabID, var selectedTarget {
                selectedTarget.tabID = tabID
                selectedTarget.isConnected = true
                if !tabURL.isEmpty { selectedTarget.url = tabURL }
                if platform != "unknown" { selectedTarget.platform = platform }
                self.selectedTarget = selectedTarget
                persistSelectedTarget()
            } else if success == false,
                      let error = json["error"] as? String,
                      error.localizedCaseInsensitiveContains("tab") {
                markSelectedTargetDisconnected()
            }
            logger.info("Prompt injected: \(success) on \(platform)")

        case "TABS_RESULT":
            handleTabsResult(json)

        case "TARGET_VERIFY_RESULT":
            handleTargetVerifyResult(json)

        case "TAB_OPENED":
            handleTabOpened(json)

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

    private func handleTabsResult(_ json: [String: Any]) {
        guard let rawTabs = json["tabs"] as? [[String: Any]] else { return }
        let tabs = rawTabs.compactMap(Self.parseBrowserTab).sorted(by: Self.sortTabs)
        availableTabs = tabs

        if let pendingPromptRequest,
           let selectedTarget,
           let matching = tabs.first(where: { $0.displayHost == selectedTarget.displayLabel }) {
            self.pendingPromptRequest = nil
            selectedTargetForTab(matching, pendingPromptRequest)
            return
        }

        isPresentingTabPicker = true
    }

    private func handleTargetVerifyResult(_ json: [String: Any]) {
        guard var selectedTarget else { return }
        let found = json["found"] as? Bool ?? false

        if found,
           let tab = Self.parseBrowserTab(json) {
            selectedTarget = BrowserTarget(tab: tab)
            self.selectedTarget = selectedTarget
            persistSelectedTarget()
            StatusBarService.shared.setTransient("Target ready: \(selectedTarget.displayLabel)")
            if let pendingPromptRequest {
                self.pendingPromptRequest = nil
                _ = post(pendingPromptRequest)
            }
            return
        }

        selectedTarget.tabID = nil
        selectedTarget.isConnected = false
        self.selectedTarget = selectedTarget
        persistSelectedTarget()
    }

    private func handleTabOpened(_ json: [String: Any]) {
        guard let tab = Self.parseBrowserTab(json) else { return }
        selectedTarget = BrowserTarget(tab: tab)
        persistSelectedTarget()
        StatusBarService.shared.setTransient("Opened \(tab.displayHost)")
        if let pendingPromptRequest {
            self.pendingPromptRequest = nil
            _ = post(pendingPromptRequest)
        }
    }

    private func selectedTargetForTab(_ tab: BrowserTab, _ request: PendingPromptRequest) {
        selectedTarget = BrowserTarget(tab: tab)
        persistSelectedTarget()
        isPresentingTabPicker = false
        availableTabs = []
        _ = post(request)
    }

    private func post(_ request: PendingPromptRequest) -> Bool {
        guard var selectedTarget,
              let tabID = selectedTarget.tabID,
              isExtensionConnected,
              selectedTarget.isConnected else {
            return false
        }

        var payload: [String: Any] = [
            "type": "PROMPT_INJECT",
            "tab_id": tabID,
            "text": request.text,
            "autoSubmit": request.autoSubmit
        ]
        if let original = request.original {
            payload["original"] = original
        }
        server?.broadcast(event: "prompt", json: payload)
        selectedTarget.isConnected = true
        self.selectedTarget = selectedTarget
        persistSelectedTarget()
        StatusBarService.shared.setTransient("Posting to \(selectedTarget.displayLabel)")
        return true
    }

    private func markSelectedTargetDisconnected() {
        guard var selectedTarget else { return }
        selectedTarget.tabID = nil
        selectedTarget.isConnected = false
        self.selectedTarget = selectedTarget
        persistSelectedTarget()
    }

    private func persistSelectedTarget() {
        guard let selectedTarget,
              let data = try? JSONEncoder().encode(selectedTarget) else {
            UserDefaults.standard.removeObject(forKey: Self.selectedTargetKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.selectedTargetKey)
    }

    private static func loadSelectedTarget() -> BrowserTarget? {
        guard let data = UserDefaults.standard.data(forKey: selectedTargetKey),
              let selectedTarget = try? JSONDecoder().decode(BrowserTarget.self, from: data) else {
            return nil
        }
        return selectedTarget
    }

    private static func parseBrowserTab(_ json: [String: Any]) -> BrowserTab? {
        guard let tabID = json["tab_id"] as? Int ?? json["tabId"] as? Int else { return nil }
        let title = json["title"] as? String ?? ""
        let url = json["url"] as? String ?? json["tabUrl"] as? String ?? ""
        let platform = json["platform"] as? String ?? "browser"
        return BrowserTab(id: tabID, platform: platform, title: title, url: url)
    }

    private static func sortTabs(lhs: BrowserTab, rhs: BrowserTab) -> Bool {
        if lhs.matchesKnownAIHost != rhs.matchesKnownAIHost {
            return lhs.matchesKnownAIHost && !rhs.matchesKnownAIHost
        }
        return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }

    func handleContextCapture(_ json: [String: Any]) {
        guard let kind = json["kind"] as? String,
              let jobId = json["jobId"] as? String else {
            logger.warning("Context capture missing kind or jobId")
            return
        }

        contextStatusCache.set(jobId, "pending")

        let payload = BrowserContextPayload(
            kind: kind,
            jobId: jobId,
            url: json["url"] as? String ?? "",
            title: json["title"] as? String ?? "",
            textContent: json["textContent"] as? String,
            markdownContent: json["markdownContent"] as? String,
            mimeType: json["mimeType"] as? String,
            dataURL: json["dataURL"] as? String,
            author: json["author"] as? String,
            publishedDate: json["publishedDate"] as? String,
            siteName: json["siteName"] as? String,
            capturedAt: json["capturedAt"] as? String
        )

        Task {
            do {
                let item = try await contextQueueService?.ingest(payload)
                let itemId = item?.id.uuidString ?? jobId
                contextStatusCache.set(itemId, "ready")
                logger.info("Context item ingested: \(itemId)")
            } catch {
                contextStatusCache.set(jobId, "failed")
                logger.error("Context ingestion failed: \(error.localizedDescription)")
            }
        }
    }
}
