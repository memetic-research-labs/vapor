import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(WindowManager.self) private var windowManager
    @Environment(UserPreferences.self) private var preferences
    @Environment(CompressionService.self) private var compressionService
    @Environment(SpeechDictationService.self) private var dictationService
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(MainWindowFocusStore.self) private var focusStore
    @Environment(StatusBarService.self) private var statusBar

    @State private var viewModel = EditorViewModel()
    @State private var historyService = PromptHistoryService()
    @State private var toastService = ToastService()
    @State private var workspace: AppWorkspace = .compose
    @State private var showContextTray = false
    @State private var isEditorFocused = false
    @State private var speechAuthStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var micAuthStatus: AVAuthorizationStatus = .notDetermined
    @State private var permissionsGranted = false

    private var hasPermissionIssue: Bool {
        micAuthStatus == .denied || micAuthStatus == .restricted ||
        speechAuthStatus == .denied || speechAuthStatus == .restricted
    }

    private var activeWorkspace: AppWorkspace {
        preferences.researchToolsEnabled ? workspace : .compose
    }

    private var shouldShowContextTray: Bool {
        activeWorkspace == .compose && showContextTray
    }

    var body: some View {
        contentGroup
            .background(windowManager.windowState == .expanded ? Color(nsColor: .windowBackgroundColor) : Color.clear)
            .sheet(
                isPresented: .init(
                    get: { browserBridge.isPresentingTabPicker },
                    set: { if !$0 { browserBridge.dismissTabPicker() } }
                ),
                onDismiss: { refocusEditorAfterTransition() }
            ) {
                TabPickerView(
                    tabs: browserBridge.availableTabs,
                    selectedTarget: browserBridge.selectedTarget,
                    onSelect: { tab in browserBridge.selectTab(tab) },
                    onCancel: { browserBridge.dismissTabPicker() }
                )
            }
            .onAppear { handleOnAppear() }
            .onChange(of: viewModel.content) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "lastEditorContent")
                TranscriptStore.shared.text = newValue
            }
            .onChange(of: viewModel.isDictating) { _, isDictating in
                guard !isDictating else { return }
                Task {
                    await Task.yield()
                    guard !viewModel.isDictating, !viewModel.content.isEmpty else { return }
                    if preferences.autoCompressEnabled {
                        await performAutoCompress()
                    } else if preferences.autoCopyOriginalEnabled {
                        viewModel.copyOriginalToClipboard(recordInHistory: false)
                        toastService.showSuccess("Original copied to clipboard")
                    }
                }
            }
            .onDisappear { handleOnDisappear() }
            .overlay(alignment: .top) {
                if toastService.isShowing {
                    ToastView(message: toastService.message, isError: toastService.isError, isInfo: toastService.isInfo)
                        .padding(.top, 40)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if windowManager.windowState == .expanded {
                    Button(action: { openWindow(id: "activity-log") }) {
                        HStack(spacing: 6) {
                            if compressionService.statusMessage != "Ready" && !compressionService.statusMessage.hasPrefix("Done") && !compressionService.statusMessage.isEmpty {
                                VaporActivitySpinner(size: 10)
                            }

                            Text(compressionService.statusMessage != "Ready" && !compressionService.statusMessage.isEmpty
                                 ? compressionService.statusMessage
                                 : statusBar.statusMessage)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            HStack(spacing: 8) {
                                ForEach(Array(statusBar.indicators.enumerated()), id: \.offset) { _, indicator in
                                    statusIndicatorView(indicator)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Show activity log")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .onChange(of: compressionService.statusMessage) { _, newValue in
                guard !newValue.isEmpty, newValue != "Ready" else { return }
                if newValue.hasPrefix("Done") || newValue.localizedCaseInsensitiveContains("failed") {
                    statusBar.setCompressionStatus(newValue)
                }
            }
            .alert("Browser Server Error", isPresented: .init(
                get: { browserBridge.portConflict },
                set: { if !$0 { browserBridge.portConflict = false } }
            )) {
                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    browserBridge.portConflict = false
                }
                Button("Dismiss", role: .cancel) {
                    browserBridge.portConflict = false
                }
            } message: {
                Text("Port \(browserBridge.serverPort) is already in use. Another app may be running, or a previous Vapor instance didn't shut down cleanly.\n\nChange the port in Settings > Browser or quit the conflicting process.")
            }
            .onChange(of: browserBridge.portConflict) { _, isConflict in
                if isConflict {
                    toastService.showError("Port \(browserBridge.serverPort) unavailable")
                }
            }
    }

    private var contentGroup: some View {
        let baseContent = AnyView(Group {
            switch windowManager.windowState {
            case .minimized:
                minimizedView
            case .expanded:
                expandedView
            }
        })

        let layoutAwareContent = AnyView(
            baseContent
                .onChange(of: windowManager.windowState) { _, newState in
                    if newState == .expanded {
                        resizeMainWindow()
                        if activeWorkspace == .compose {
                            refocusEditorAfterTransition()
                        }
                    }
                }
                .onChange(of: HistoryStore.shared.pendingRestore?.persistentModelID) { _, newID in
                    if newID != nil, let record = HistoryStore.shared.pendingRestore {
                        viewModel.restoreFromHistory(record)
                        HistoryStore.shared.pendingRestore = nil
                        toastService.showSuccess("Restored from history")
                    }
                }
                .onChange(of: isEditorFocused) { _, focused in
                    if focused {
                        focusStore.focus(.editor)
                    }
                }
                .onChange(of: workspace) { _, newWorkspace in
                    resizeMainWindow()
                    if newWorkspace == .compose {
                        refocusEditorAfterTransition()
                    }
                }
                .onChange(of: preferences.researchToolsEnabled) { _, isEnabled in
                    if !isEnabled {
                        workspace = .compose
                    }
                    resizeMainWindow()
                }
        )

        return AnyView(
            layoutAwareContent
                .onReceive(NotificationCenter.default.publisher(for: .vaporCopyOriginal)) { _ in
                    viewModel.copyOriginalToClipboard()
                    toastService.showSuccess("Original copied to clipboard")
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporCompressAndCopy)) { _ in
                    Task { await performCompressAndCopy() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporCopyAndClear)) { _ in
                    viewModel.copyAndClear()
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporShowHistory)) { _ in
                    openWindow(id: "prompt-history")
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporShowHelp)) { _ in
                    openWindow(id: "keyboard-shortcuts")
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporSendToBrowser)) { _ in
                    sendToBrowser()
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporChooseBrowserTarget)) { _ in
                    chooseBrowserTarget()
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporInsertContextItem)) { notification in
                    if let text = notification.object as? String {
                        viewModel.content += (viewModel.content.isEmpty ? "" : "\n\n") + text
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporScreenshotReadyForSidebar)) { notification in
                    if let item = notification.object as? SidebarScreenshotItem {
                        browserBridge.sendSidebarScreenshot(item)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporScreenshotDismissedFromSidebar)) { notification in
                    if let item = notification.object as? SidebarScreenshotItem {
                        browserBridge.removeSidebarScreenshot(item.shaPrefix)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporFocusEditor)) { _ in
                    workspace = .compose
                    focusStore.focus(.editor)
                    EditorTextViewRegistry.refocus()
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporFocusContextTray)) { _ in
                    workspace = .compose
                    if !showContextTray {
                        showContextTray = true
                        resizeMainWindow()
                    }
                    focusStore.focus(.contextTray)
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporFocusToolRail)) { _ in
                    workspace = .compose
                    focusStore.focus(.toolRail)
                }
                .onReceive(NotificationCenter.default.publisher(for: .vaporLLMDownloadCompleted)) { _ in
                    Task { await compressionService.reloadLocalLLMIfNeeded() }
                }
        )
    }

    private var minimizedView: some View {
        MinimizedPillView(
            onExpand: {
                windowManager.expand(workspace: activeWorkspace, showContextTray: shouldShowContextTray)
                if activeWorkspace == .compose {
                    refocusEditorAfterTransition()
                }
            },
            onCompressAndCopy: { Task { await performCompressAndCopy() } },
            onCopyOriginal: {
                viewModel.copyOriginalToClipboard()
                toastService.showSuccess("Original copied to clipboard")
            },
            onClear: { viewModel.copyAndClear() },
            onShowHistory: { openWindow(id: "prompt-history") },
            onShowHelp: { openWindow(id: "keyboard-shortcuts") },
            onSendToBrowser: { sendToBrowser() },
            text: $viewModel.content,
            statusMessage: compressionService.statusMessage,
            isDictating: viewModel.isDictating,
            isCompressing: viewModel.isCompressing,
            isModelReady: compressionService.isSelectedCompressorReady,
            isModelLoading: compressionService.isModelLoading,
            isBrowserConnected: browserBridge.isExtensionConnected,
            inputLevel: dictationService.inputLevel
        )
    }

    @ViewBuilder
    private var expandedView: some View {
        if hasPermissionIssue {
            PermissionsOverlayView(
                speechStatus: speechAuthStatus,
                micStatus: micAuthStatus,
                onRetry: checkPermissions
            )
        } else {
            expandedContent
        }
    }

    private var mainToolbar: some View {
        ToolbarView(
            viewModel: viewModel,
            preferences: preferences,
            workspace: activeWorkspace,
            isContextTrayVisible: showContextTray,
            onCompressAndCopy: {
                Task { await performCompressAndCopy() }
            },
            onCopyOriginal: {
                viewModel.copyOriginalToClipboard()
                toastService.showSuccess("Original copied to clipboard")
            },
            onShowHistory: {
                openWindow(id: "prompt-history")
            },
            onSelectWorkspace: { newWorkspace in
                workspace = preferences.researchToolsEnabled ? newWorkspace : .compose
            },
            onOpenExperiments: {
                openWindow(id: "openrouter-test")
                NSApp.activate(ignoringOtherApps: true)
            },
            onToggleContextTray: {
                guard activeWorkspace == .compose else { return }
                showContextTray.toggle()
                resizeMainWindow()
                refocusEditorAfterTransition()
            },
            onMinimize: {
                windowManager.minimize()
            }
        )
    }

    private var expandedContent: some View {
        GeometryReader { proxy in
            Group {
                switch activeWorkspace {
                case .compose:
                    ComposeWorkspaceView(
                        totalSize: proxy.size,
                        showContextTray: showContextTray,
                        toolRail: AnyView(composeToolRail),
                        editorWorkspace: AnyView(defaultEditorWorkspace),
                        contextTray: AnyView(ContextTrayView())
                    )
                case .research:
                    ResearchWorkspaceView(
                        totalSize: proxy.size,
                        explorer: AnyView(researchExplorerView),
                        interrogationSidebar: AnyView(ResearchInterrogationView())
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                mainToolbar
                Divider()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            switch focusStore.activeZone {
            case .promptHistory:
                NotificationCenter.default.post(name: .vaporPromptHistoryMoveLeft, object: nil)
                return .handled
            case .screenshots:
                NotificationCenter.default.post(name: .vaporScreenshotMoveLeft, object: nil)
                return .handled
            case .editor, .contextTray, .toolRail:
                return .ignored
            }
        }
        .onKeyPress(.rightArrow) {
            switch focusStore.activeZone {
            case .promptHistory:
                NotificationCenter.default.post(name: .vaporPromptHistoryMoveRight, object: nil)
                return .handled
            case .screenshots:
                NotificationCenter.default.post(name: .vaporScreenshotMoveRight, object: nil)
                return .handled
            case .editor, .contextTray, .toolRail:
                return .ignored
            }
        }
        .onKeyPress(.upArrow) {
            switch focusStore.activeZone {
            case .contextTray:
                NotificationCenter.default.post(name: .vaporContextMoveUp, object: nil)
                return .handled
            case .toolRail:
                NotificationCenter.default.post(name: .vaporToolMoveUp, object: nil)
                return .handled
            case .editor, .promptHistory, .screenshots:
                return .ignored
            }
        }
        .onKeyPress(.downArrow) {
            switch focusStore.activeZone {
            case .contextTray:
                NotificationCenter.default.post(name: .vaporContextMoveDown, object: nil)
                return .handled
            case .toolRail:
                NotificationCenter.default.post(name: .vaporToolMoveDown, object: nil)
                return .handled
            case .editor, .promptHistory, .screenshots:
                return .ignored
            }
        }
        .onKeyPress(.space) {
            switch focusStore.activeZone {
            case .promptHistory:
                return .ignored
            case .screenshots:
                NotificationCenter.default.post(name: .vaporScreenshotInsertSelected, object: nil)
                return .handled
            case .contextTray:
                NotificationCenter.default.post(name: .vaporContextActivateSecondary, object: nil)
                return .handled
            case .toolRail:
                NotificationCenter.default.post(name: .vaporToolActivate, object: nil)
                return .handled
            case .editor:
                return .ignored
            }
        }
        .onKeyPress(.return) {
            switch focusStore.activeZone {
            case .promptHistory:
                NotificationCenter.default.post(name: .vaporPromptHistoryRestoreSelected, object: nil)
                return .handled
            case .screenshots:
                NotificationCenter.default.post(name: .vaporScreenshotInsertSelected, object: nil)
                return .handled
            case .contextTray:
                NotificationCenter.default.post(name: .vaporContextActivatePrimary, object: nil)
                return .handled
            case .toolRail:
                NotificationCenter.default.post(name: .vaporToolActivate, object: nil)
                return .handled
            case .editor:
                return .ignored
            }
        }
        .onKeyPress(.escape) {
            if activeWorkspace == .compose && focusStore.activeZone != .editor {
                focusStore.focus(.editor)
                EditorTextViewRegistry.refocus()
                return .handled
            }
            windowManager.minimize()
            return .handled
        }
    }

    private var composeToolRail: some View {
        ToolSidebarView(
            viewModel: viewModel,
            dictationService: dictationService,
            preferences: preferences,
            onChooseTarget: {
                chooseBrowserTarget()
            },
            onPostToTarget: {
                sendToBrowser()
            },
            onToggleDictation: {
                toggleDictation()
            }
        )
    }

    private var defaultEditorWorkspace: some View {
        VStack(spacing: 0) {
            editorSection

            if viewModel.originalTokenCount > 0 {
                Divider()
                StatsBarView(
                    originalTokens: viewModel.originalTokenCount,
                    compressedTokens: viewModel.compressedTokenCount,
                    ratio: viewModel.compressionRatio
                )
            }

            if !viewModel.compressedContent.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compressed Preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)

                    ScrollView {
                        Text(viewModel.compressedContent)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                    .background(Color(nsColor: .underPageBackgroundColor))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: viewModel.compressedContent.isEmpty)
            }

            if windowManager.windowState == .expanded {
                PromptHistoryShelfView { record in
                    viewModel.restoreFromHistory(record)
                    toastService.showSuccess("Restored from history")
                    refocusEditorAfterTransition()
                }
                ScreenshotShelfView()
            }
        }
    }

    private var researchExplorerView: some View {
        BrowserSourceExplorerView(
            source: browserBridge.selectedInterrogationSource,
            preview: browserBridge.activePreview,
            isLoadingPreview: browserBridge.isLoadingPreview,
            onClearSelection: {
                browserBridge.clearInterrogationSourceSelection()
            }
        )
    }

    private func handleOnAppear() {
        historyService.setModelContext(modelContext)
        viewModel.setServices(compression: compressionService, history: historyService)
        viewModel.setBrowserBridge(browserBridge)
        viewModel.setPreferences(preferences)
        if let saved = UserDefaults.standard.string(forKey: "lastEditorContent") {
            viewModel.content = saved
        }
        TranscriptStore.shared.text = viewModel.content
        setupDictation()
        checkPermissions()
        windowManager.setupWindowOnAppear()
        DispatchQueue.main.async {
            resizeMainWindow()
        }
    }

    private func handleOnDisappear() {
        FnDictationMonitor.shared.stop()
        dictationService.stopDictation(commit: false)
        windowManager.savePosition()
    }

    private func resizeMainWindow() {
        windowManager.resizeForLayout(workspace: activeWorkspace, showContextTray: shouldShowContextTray)
    }

    private func checkPermissions() {
        speechAuthStatus = SFSpeechRecognizer.authorizationStatus()
        micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        permissionsGranted = !hasPermissionIssue

        if permissionsGranted {
            Task { await dictationService.requestPermissionsIfNeeded() }
        }
    }

    private func performCompressAndCopy() async {
        do {
            try await viewModel.compressAndCopy()
            if !viewModel.compressedContent.isEmpty {
                let hasCompressedBefore = UserDefaults.standard.bool(forKey: "hasCompressedBefore")
                if viewModel.contentChangedDuringCompression {
                    toastService.showInfo("Compressed earlier snapshot copied — current draft has changes")
                } else if !hasCompressedBefore {
                    toastService.showInfo("Compressed prompt copied. Switch to your terminal or AI tool and press ⌘V.")
                    UserDefaults.standard.set(true, forKey: "hasCompressedBefore")
                } else {
                    toastService.showSuccess("Compressed & copied (\(String(format: "%.2f", viewModel.compressionRatio)) ratio)")
                }
                if preferences.autoMinimizeEnabled && !viewModel.contentChangedDuringCompression {
                    windowManager.minimize()
                }
            }
        } catch {
            toastService.showError("Compression failed: \(error.localizedDescription)")
        }
    }

    private var editorSection: some View {
        NativeTextEditor(text: $viewModel.content, isFocused: $isEditorFocused, isDictating: viewModel.isDictating)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .editorGlow(
                isFocused: isEditorFocused,
                isDictating: viewModel.isDictating,
                inputLevel: dictationService.inputLevel
            )
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 10, trailing: 10))
            .frame(maxHeight: .infinity)
    }

    private func performAutoCompress() async {
        do {
            try await viewModel.compressAndCopy()
            if !viewModel.compressedContent.isEmpty {
                toastService.showSuccess("Compressed & copied (\(String(format: "%.2f", viewModel.compressionRatio)) ratio)")
                if preferences.autoMinimizeEnabled {
                    windowManager.minimize()
                }
            }
        } catch {
            toastService.showError("Compression failed: \(error.localizedDescription)")
        }
    }

    private func toggleDictation() {
        toastService.showInfo("Hold the Fn key to dictate, release to stop")
    }

    private func sendToBrowser() {
        guard browserBridge.isExtensionConnected else {
            toastService.showError("No browser extension connected")
            return
        }
        guard !viewModel.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.recordCurrentPromptInHistory(reason: .sentToBrowser)
        let text = viewModel.compressedContent.isEmpty ? viewModel.content : viewModel.compressedContent
        let autoSubmit = preferences.autoSubmitToAI
        let posted = browserBridge.sendPrompt(text, original: viewModel.content, autoSubmit: autoSubmit)
        if posted, let target = browserBridge.selectedTarget {
            if autoSubmit {
                toastService.showSuccess("Sent to \(target.displayLabel)")
            } else {
                toastService.showSuccess("Injected into \(target.displayLabel) — press Enter to send")
            }
        } else if browserBridge.selectedTarget != nil {
            toastService.showInfo("Refreshing browser tab target")
        } else {
            toastService.showInfo("Choose a browser tab target")
        }
    }

    private func chooseBrowserTarget() {
        guard browserBridge.isExtensionConnected else {
            toastService.showError("No browser extension connected")
            return
        }
        browserBridge.queryTabs()
    }

    private func setupDictation() {
        FnDictationMonitor.shared.start { [weak viewModel, weak dictationService] isFnDown in
            Task { @MainActor in
                guard let viewModel, let dictationService else { return }

                let micDenied = AVCaptureDevice.authorizationStatus(for: .audio) == .denied
                    || AVCaptureDevice.authorizationStatus(for: .audio) == .restricted
                let speechDenied = SFSpeechRecognizer.authorizationStatus() == .denied
                    || SFSpeechRecognizer.authorizationStatus() == .restricted

                if micDenied || speechDenied {
                    if isFnDown {
                        toastService.showError("Microphone or Speech Recognition access required — open System Settings to grant access")
                    }
                    return
                }

                if isFnDown {
                    if dictationService.isDictating { return }
                    viewModel.isDictating = true
                    dictationService.onError = { msg in
                        viewModel.isDictating = false
                        toastService.showError(msg)
                    }
                    dictationService.startDictation(onTextUpdate: { text, isFinal in
                        viewModel.applyDictationTranscript(text, isFinal: isFinal)
                    })
                } else {
                    dictationService.pauseDictation()
                    viewModel.isDictating = false
                    EditorTextViewRegistry.refocus()
                }
            }
        }
    }

    private func refocusEditorAfterTransition() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            EditorTextViewRegistry.refocusAtEnd()
        }
    }

    @ViewBuilder
    func statusIndicatorView(_ indicator: StatusBarIndicator) -> some View {
        switch indicator {
        case .context(let count, let hasProcessing):
            HStack(spacing: 3) {
                Circle()
                    .fill(hasProcessing ? .orange : .green)
                    .frame(width: 6, height: 6)
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
        case .browser(let connected):
            Image(systemName: connected ? "link" : "link.slash")
                .font(.system(size: 10))
                .foregroundColor(connected ? .blue : .secondary.opacity(0.5))
        case .llm(let available):
            Image(systemName: available ? "cpu" : "cpu.badge.xmark")
                .font(.system(size: 10))
                .foregroundColor(available ? .green : .secondary.opacity(0.5))
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PromptRecord.self, inMemory: true)
        .environment(WindowManager.shared)
        .environment(UserPreferences())
        .environment(SpeechDictationService())
}
