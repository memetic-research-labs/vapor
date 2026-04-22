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

    var interrogationAvailableTabs: [BrowserTab] = []
    var isLoadingInterrogationTabs: Bool = false
    var interrogationTabID: Int?
    var interrogationTabURL: String?
    var interrogationTabTitle: String?
    var discoveredSources: [DiscoveredSource] = []
    var selectedInterrogationSourceID: String?
    var isInterrogating: Bool = false
    var interrogationError: String?
    var activePreview: SourcePreview?
    var isLoadingPreview: Bool = false
    private var isQueryingForInterrogation = false

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
            defer { self?.startTask = nil }
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
                            StatusBarService.shared.setTransient("Browser extension connected", domain: .browser)
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

    func queryTabs(forInterrogation: Bool = false) {
        guard isExtensionConnected else {
            lastError = "No browser extension connected"
            return
        }
        if forInterrogation {
            isQueryingForInterrogation = true
            isLoadingInterrogationTabs = true
        }
        StatusBarService.shared.setTransient("Fetching browser tabs", domain: .browser)
        server?.broadcast(event: "prompt", json: [
            "type": "QUERY_TABS"
        ])
    }

    func selectTab(_ tab: BrowserTab) {
        selectedTarget = BrowserTarget(tab: tab)
        persistSelectedTarget()
        isPresentingTabPicker = false
        availableTabs = []
        StatusBarService.shared.setTransient("Target set to \(tab.displayHost)", domain: .browser)

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

    func dismissInterrogationPicker() {
        interrogationAvailableTabs = []
        isLoadingInterrogationTabs = false
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
        StatusBarService.shared.setTransient("Opening \(selectedTarget.displayLabel)", domain: .browser)
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

    var selectedInterrogationSource: DiscoveredSource? {
        guard let selectedInterrogationSourceID else { return nil }
        return discoveredSources.first(where: { $0.id == selectedInterrogationSourceID })
    }

    func activatePicker() {
        server?.broadcast(event: "prompt", json: [
            "type": "ACTIVATE_PICKER"
        ])
    }

    func interrogateTab(_ tab: BrowserTab) {
        guard isExtensionConnected else {
            interrogationError = "No browser extension connected"
            return
        }
        interrogationAvailableTabs = []
        isLoadingInterrogationTabs = false
        interrogationTabID = tab.id
        interrogationTabURL = tab.url
        interrogationTabTitle = tab.title
        discoveredSources = []
        selectedInterrogationSourceID = nil
        activePreview = nil
        interrogationError = nil
        isInterrogating = true
        isLoadingPreview = false
        StatusBarService.shared.setTransient("Interrogating \(tab.displayHost)", domain: .browser)
        server?.broadcast(event: "prompt", json: [
            "type": "INTERROGATE_TAB",
            "tab_id": tab.id
        ])
    }

    func selectInterrogationSource(_ source: DiscoveredSource) {
        selectedInterrogationSourceID = source.id
        interrogationError = nil

        if activePreview?.sourceId == source.id {
            return
        }

        activePreview = nil
        previewSource(source.id)
    }

    func clearInterrogationSourceSelection() {
        selectedInterrogationSourceID = nil
        activePreview = nil
        isLoadingPreview = false
    }

    func previewSource(_ sourceId: String) {
        guard isExtensionConnected, let tabID = interrogationTabID else {
            interrogationError = "Not interrogating any tab"
            return
        }
        isLoadingPreview = true
        server?.broadcast(event: "prompt", json: [
            "type": "PREVIEW_SOURCE",
            "tab_id": tabID,
            "source_id": sourceId
        ])
    }

    func refreshXHRSources() {
        guard isExtensionConnected, let tabID = interrogationTabID else { return }
        server?.broadcast(event: "prompt", json: [
            "type": "REFRESH_XHR_SOURCES",
            "tab_id": tabID
        ])
    }

    func endInterrogation() {
        interrogationAvailableTabs = []
        isLoadingInterrogationTabs = false
        interrogationTabID = nil
        interrogationTabURL = nil
        interrogationTabTitle = nil
        discoveredSources = []
        selectedInterrogationSourceID = nil
        activePreview = nil
        interrogationError = nil
        isInterrogating = false
        isLoadingPreview = false
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

        case "RESEARCH_SOURCES_DISCOVERED":
            handleSourcesDiscovered(json)

        case "RESEARCH_SOURCE_PREVIEW":
            handleSourcePreview(json)

        case "XHR_SOURCES_REFRESHED":
            handleXHRRefreshed(json)

        default:
            logger.debug("Unknown extension response type: \(type)")
        }
    }

    private func handleSourcesDiscovered(_ json: [String: Any]) {
        isInterrogating = false
        if let error = json["error"] as? String {
            interrogationError = error
            logger.error("Interrogation failed: \(error)")
            return
        }
        interrogationTabURL = json["tabUrl"] as? String ?? interrogationTabURL
        interrogationTabTitle = json["tabTitle"] as? String ?? interrogationTabTitle
        if let rawSources = json["sources"] as? [[String: Any]] {
            discoveredSources = rawSources.compactMap(Self.parseDiscoveredSource)
            if let selectedInterrogationSourceID,
               discoveredSources.contains(where: { $0.id == selectedInterrogationSourceID }) == false {
                self.selectedInterrogationSourceID = nil
                activePreview = nil
            }
        }
        StatusBarService.shared.setTransient("Found \(self.discoveredSources.count) sources", domain: .browser)
        logger.info("Discovered \(self.discoveredSources.count) research sources")
    }

    private func handleSourcePreview(_ json: [String: Any]) {
        isLoadingPreview = false
        if let error = json["error"] as? String {
            interrogationError = error
            logger.error("Source preview failed: \(error)")
            return
        }
        guard let rawPreview = json["preview"] as? [String: Any] else {
            interrogationError = "Missing preview data"
            return
        }
        activePreview = SourcePreview(
            sourceId: rawPreview["sourceId"] as? String ?? "",
            content: rawPreview["content"] as? String ?? "",
            mimeType: rawPreview["mimeType"] as? String ?? "text/plain",
            truncated: rawPreview["truncated"] as? Bool ?? false,
            sizeBytes: rawPreview["sizeBytes"] as? Int
        )
    }

    private func handleXHRRefreshed(_ json: [String: Any]) {
        if let error = json["error"] as? String {
            logger.error("XHR refresh failed: \(error)")
            return
        }
        if let rawSources = json["sources"] as? [[String: Any]] {
            let newXHRSources = rawSources.compactMap(Self.parseDiscoveredSource)
            let existingNonXHR = self.discoveredSources.filter { $0.sourceKind != .xhrFeed }
            self.discoveredSources = existingNonXHR + newXHRSources
            if let selectedInterrogationSourceID,
               self.discoveredSources.contains(where: { $0.id == selectedInterrogationSourceID }) == false {
                self.selectedInterrogationSourceID = nil
                self.activePreview = nil
            }
        }
    }

    private func handleTabsResult(_ json: [String: Any]) {
        guard let rawTabs = json["tabs"] as? [[String: Any]] else { return }
        let tabs = rawTabs.compactMap(Self.parseBrowserTab).sorted(by: Self.sortTabs)

        if isQueryingForInterrogation {
            isQueryingForInterrogation = false
            isLoadingInterrogationTabs = false
            interrogationAvailableTabs = tabs
            return
        }

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
            StatusBarService.shared.setTransient("Target ready: \(selectedTarget.displayLabel)", domain: .browser)
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
        StatusBarService.shared.setTransient("Opened \(tab.displayHost)", domain: .browser)
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
        StatusBarService.shared.setTransient("Posting to \(selectedTarget.displayLabel)", domain: .browser)
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

    private static func parseDiscoveredSource(_ json: [String: Any]) -> DiscoveredSource? {
        guard let id = json["id"] as? String,
              let kindRaw = json["sourceKind"] as? String,
              let sourceKind = ResearchSourceKind(rawValue: kindRaw) else {
            return nil
        }
        return DiscoveredSource(
            id: id,
            sourceKind: sourceKind,
            label: json["label"] as? String ?? "",
            detail: json["detail"] as? String ?? "",
            recordEstimate: json["recordEstimate"] as? Int,
            sizeHint: json["sizeHint"] as? String
        )
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

        contextStatusCache.set(jobId, "processing")

        Task {
            do {
                let item = try await contextQueueService?.ingest(payload)
                contextStatusCache.set(jobId, "ready")
                if let itemId = item?.id.uuidString {
                    logger.info("Context item ingested for job \(jobId): \(itemId)")
                } else {
                    logger.info("Context item ingested for job \(jobId)")
                }
            } catch {
                contextStatusCache.set(jobId, "failed")
                logger.error("Context ingestion failed: \(error.localizedDescription)")
            }
        }
    }
}
