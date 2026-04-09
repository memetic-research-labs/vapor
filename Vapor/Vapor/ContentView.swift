import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = EditorViewModel()
    @State private var compressionService = CompressionService()
    @State private var historyService = PromptHistoryService()
    @State private var toastService = ToastService()
    @State private var dictationService = SpeechDictationService()
    @State private var showSettings = false
    @State private var showTestSidebar = false
    @State private var sidebarPrompt: String = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ToolbarView(
                    viewModel: viewModel,
                    onCompressAndCopy: {
                        do {
                            try await viewModel.compressAndCopy()
                            if !viewModel.compressedContent.isEmpty {
                                toastService.showSuccess("Compressed & copied (\(String(format: "%.2f", viewModel.compressionRatio)) ratio)")
                            }
                        } catch {
                            toastService.showError("Compression failed: \(error.localizedDescription)")
                        }
                    },
                    onCopyOriginal: {
                        viewModel.copyOriginalToClipboard()
                        toastService.showSuccess("Original copied to clipboard")
                    },
                    onClear: {
                        viewModel.clear()
                    },
                    onToggleSettings: {
                        showSettings.toggle()
                    },
                    onToggleDictation: {
                        viewModel.isDictating.toggle()
                        dictationService.toggleDictation { text, isFinal in
                            Task { @MainActor in
                                viewModel.applyDictationTranscript(text, isFinal: isFinal)
                                if isFinal {
                                    viewModel.isDictating = false
                                }
                            }
                        }
                    },
                    onToggleTest: {
                        withAnimation {
                            showTestSidebar.toggle()
                        }
                    }
                )

                Divider()

                NativeTextEditor(text: $viewModel.content)
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
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 100)
                        .background(Color.secondary.opacity(0.05))
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 300)
            .frame(maxWidth: showTestSidebar ? 600 : 800, maxHeight: 800)

            if showTestSidebar {
                Divider()
                OpenRouterTestSidebar(
                    prompt: $sidebarPrompt
                )
                    .frame(width: 350)
            }
        }
        .onAppear {
            historyService.setModelContext(modelContext)
            viewModel.setServices(compression: compressionService, history: historyService)
            if let saved = UserDefaults.standard.string(forKey: "lastEditorContent") {
                viewModel.content = saved
            }
            setupDictation()
        }
        .onChange(of: viewModel.content) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "lastEditorContent")
        }
        .onChange(of: viewModel.compressedContent) { _, newValue in
            sidebarPrompt = newValue
        }
        .onDisappear {
            FnDictationMonitor.shared.stop()
            dictationService.stopDictation(commit: false)
        }
        .overlay(alignment: .top) {
            if toastService.isShowing {
                ToastView(message: toastService.message, isError: toastService.isError)
                    .padding(.top, 40)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                compressionService: compressionService,
                selectedCompressor: $viewModel.selectedCompressor
            )
        }
    }

    private func setupDictation() {
        FnDictationMonitor.shared.start { [weak viewModel, weak dictationService] isFnDown in
            Task { @MainActor in
                guard let viewModel, let dictationService else { return }

                if isFnDown && !viewModel.isDictating {
                    viewModel.isDictating = true
                    dictationService.toggleDictation { text, isFinal in
                        Task { @MainActor in
                            viewModel.applyDictationTranscript(text, isFinal: isFinal)
                            if isFinal {
                                viewModel.isDictating = false
                                EditorTextViewRegistry.refocus()
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PromptRecord.self, inMemory: true)
}
