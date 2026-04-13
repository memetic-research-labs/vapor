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
    @State private var viewModel = EditorViewModel()
    @State private var historyService = PromptHistoryService()
    @State private var toastService = ToastService()
    @State private var dictationService = SpeechDictationService()
    @State private var showTestSidebar = false
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
                Text(compressionService.statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
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
        .onReceive(NotificationCenter.default.publisher(for: .vaporLLMDownloadCompleted)) { _ in
            Task { await compressionService.reloadLocalLLMIfNeeded() }
        }
    }

    private var minimizedView: some View {
        MinimizedPillView(
            onExpand: { windowManager.expand() },
            onCompressAndCopy: { Task { await performCompressAndCopy() } },
            onCopyOriginal: {
                viewModel.copyOriginalToClipboard()
                toastService.showSuccess("Original copied to clipboard")
            },
            onClear: { viewModel.copyAndClear() },
            onShowHistory: { openWindow(id: "prompt-history") },
            onShowHelp: { openWindow(id: "keyboard-shortcuts") },
            text: $viewModel.content,
            statusMessage: compressionService.statusMessage,
            isDictating: viewModel.isDictating,
            isCompressing: viewModel.isCompressing,
            isModelReady: compressionService.isSelectedCompressorReady,
            isModelLoading: compressionService.isModelLoading,
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
        if let saved = UserDefaults.standard.string(forKey: "lastEditorContent") {
            viewModel.content = saved
        }
        TranscriptStore.shared.text = viewModel.content
        setupDictation()
        checkPermissions()
        windowManager.setupWindowOnAppear()
    }

    private func handleOnDisappear() {
        FnDictationMonitor.shared.stop()
        dictationService.stopDictation(commit: false)
        windowManager.savePosition()
    }

    private var expandedContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ToolbarView(
                    viewModel: viewModel,
                    dictationService: dictationService,
                    preferences: preferences,
                    onCompressAndCopy: {
                        Task { await performCompressAndCopy() }
                    },
                    onCopyOriginal: {
                        viewModel.copyOriginalToClipboard()
                        toastService.showSuccess("Original copied to clipboard")
                    },
                    onClear: {
                        viewModel.clear()
                    },
                    onToggleDictation: {
                        toggleDictation()
                    },
                    onToggleTest: {
                        withAnimation {
                            showTestSidebar.toggle()
                        }
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
                    .padding(EdgeInsets(top: 6, leading: 6, bottom: 12, trailing: 6))
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
            .frame(minWidth: 400, minHeight: 300)

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
}

#Preview {
    ContentView()
        .modelContainer(for: PromptRecord.self, inMemory: true)
        .environment(WindowManager.shared)
        .environment(UserPreferences())
}
