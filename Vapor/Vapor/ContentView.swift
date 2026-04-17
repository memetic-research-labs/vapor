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
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(ContextQueueService.self) private var contextQueue
    @Environment(StatusBarService.self) private var statusBar
    @State private var viewModel = EditorViewModel()
    @State private var historyService = PromptHistoryService()
    @State private var toastService = ToastService()
    @State private var dictationService = SpeechDictationService()
    @State private var showTestSidebar = false
    @State private var showContextTray = false
    @State private var isEditorFocused = false
    @State private var sidebarPrompt: String = ""
    @State private var speechAuthStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var micAuthStatus: AVAuthorizationStatus = .notDetermined
    @State private var permissionsGranted = false

    private var hasPermissionIssue: Bool {
        micAuthStatus == .denied || micAuthStatus == .restricted ||
        speechAuthStatus == .denied || speechAuthStatus == .restricted
    }

    var body: some View {
        contentGroup
            .background(windowManager.windowState == .expanded ? Color(nsColor: .windowBackgroundColor) : Color.clear)
            .sheet(
                isPresented: .init(
                    get: { browserBridge.isPresentingTabPicker },
                    set: { if !$0 { browserBridge.dismissTabPicker() } }
                ),
                onDismiss: {
                    refocusEditorAfterTransition()
                },
                content: {
                TabPickerView(
                    tabs: browserBridge.availableTabs,
                    selectedTarget: browserBridge.selectedTarget,
                    onSelect: { tab in
                        browserBridge.selectTab(tab)
                    },
                    onCancel: {
                        browserBridge.dismissTabPicker()
                    }
                )
                }
            )
            .onAppear { handleOnAppear() }
            .onChange(of: viewModel.content) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "lastEditorContent")
                TranscriptStore.shared.text = newValue
            }
            .onChange(of: viewModel.compressedContent) { _, newValue in
                sidebarPrompt = newValue
            }
            .onChange(of: viewModel.isDictating) { _, isDictating in
                guard !isDictating else { return }
                Task {
                    await Task.yield()
                    guard !viewModel.isDictating, !viewModel.content.isEmpty else { return }
                    if preferences.autoCompressEnabled {
                        await performAutoCompress()
                    } else if preferences.autoCopyOriginalEnabled {
                        viewModel.copyOriginalToClipboard()
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
                HStack(spacing: 0) {
                    Text(statusBar.statusMessage)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .alert("Browser Server Error", isPresented: .init(
            get: { browserBridge.portConflict },
            set: { if !$0 { browserBridge.portConflict = false } }
        )) {
            Button("Open Settings", role: nil) {
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
        Group {
            switch windowManager.windowState {
            case .minimized:
                minimizedView
            case .expanded:
                expandedView
            }
        }
        .onChange(of: windowManager.windowState) { _, newState in
            if newState == .expanded {
                windowManager.resizeForPanels(
                    showContextTray: showContextTray,
                    showTestSidebar: showTestSidebar
                )
                refocusEditorAfterTransition()
            }
        }
        .onChange(of: HistoryStore.shared.pendingRestore?.persistentModelID) { _, newID in
            if newID != nil, let record = HistoryStore.shared.pendingRestore {
                viewModel.restoreFromHistory(record)
                HistoryStore.shared.pendingRestore = nil
                toastService.showSuccess("Restored from history")
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .vaporLLMDownloadCompleted)) { _ in
            Task { await compressionService.reloadLocalLLMIfNeeded() }
        }
    }

    private var minimizedView: some View {
        MinimizedPillView(
            onExpand: {
                windowManager.expand(
                    showContextTray: showContextTray,
                    showTestSidebar: showTestSidebar
                )
                refocusEditorAfterTransition()
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
            windowManager.resizeForPanels(
                showContextTray: showContextTray,
                showTestSidebar: showTestSidebar
            )
        }
    }

    private func handleOnDisappear() {
        FnDictationMonitor.shared.stop()
        dictationService.stopDictation(commit: false)
        windowManager.savePosition()
    }

    private var expandedContent: some View {
        HStack(spacing: 0) {
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

            Divider()

            VStack(spacing: 0) {
                ToolbarView(
                    viewModel: viewModel,
                    preferences: preferences,
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
                    onToggleTest: {
                        let willShow = !showTestSidebar
                        windowManager.resizeForPanels(
                            showContextTray: showContextTray,
                            showTestSidebar: willShow
                        )
                        withAnimation {
                            showTestSidebar.toggle()
                        }
                        refocusEditorAfterTransition()
                    },
                    onToggleContextTray: {
                        let willShow = !showContextTray
                        windowManager.resizeForPanels(
                            showContextTray: willShow,
                            showTestSidebar: showTestSidebar
                        )
                        withAnimation {
                            showContextTray.toggle()
                        }
                        refocusEditorAfterTransition()
                    },
                    onMinimize: {
                        windowManager.minimize()
                    }
                )

                NativeTextEditor(text: $viewModel.content, isFocused: $isEditorFocused)
                    .editorGlow(
                        isFocused: isEditorFocused,
                        isDictating: viewModel.isDictating,
                        inputLevel: dictationService.inputLevel
                    )
                    .padding(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .frame(maxHeight: .infinity)

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
                        .background(Color.secondary.opacity(0.05))
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.compressedContent.isEmpty)
                }
            }
            .frame(width: 640)
            .frame(minHeight: 300)

            if showContextTray {
                Divider()
                ContextTrayView()
            }

            if showTestSidebar {
                Divider()
                OpenRouterTestSidebar(
                    prompt: $sidebarPrompt
                )
                .frame(width: 350)
            }
        }
        .focusable()
        .onKeyPress(.escape) {
            windowManager.minimize()
            return .handled
        }
        // Keyboard shortcuts (⌘K, ⇧⌘C, ⌘Y, ⌘/, ⌘↩) handled at app level via menu commands.
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
                if !hasCompressedBefore {
                    toastService.showInfo("Compressed prompt copied. Switch to your terminal or AI tool and press ⌘V.")
                    UserDefaults.standard.set(true, forKey: "hasCompressedBefore")
                } else {
                    toastService.showSuccess("Compressed & copied (\(String(format: "%.2f", viewModel.compressionRatio)) ratio)")
                }
                if preferences.autoMinimizeEnabled {
                    windowManager.minimize()
                }
            }
        } catch {
            toastService.showError("Compression failed: \(error.localizedDescription)")
        }
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
        viewModel.recordCurrentPromptInHistory()
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

    // Dictation is Fn-key only. No auto-start on expand.

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
                    dictationService.startDictation(onTextUpdate: { text, isFinal in
                        Task { @MainActor in
                            viewModel.applyDictationTranscript(text, isFinal: isFinal)
                            // Don't set isDictating = false here.
                            // Only the Fn release handler controls dictation state.
                        }
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

    // MARK: - Status Bar Indicators

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
}
