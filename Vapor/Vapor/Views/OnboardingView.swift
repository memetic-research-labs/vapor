import AVFoundation
import Speech
import SwiftUI

struct OnboardingView: View {
    @State private var store = OnboardingStore.shared
    @State private var currentStep: Int = 0
    @State private var slideDirection: SlideDirection = .forward
    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 11

    enum SlideDirection {
        case forward, backward
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepView(for: currentStep)
                    .id(currentStep)
                    .transition(slideTransition)
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(alignment: .center) {
                Button {
                    withAnimation {
                        slideDirection = .backward
                        currentStep = max(0, currentStep - 1)
                    }
                } label: {
                    Text("← Back")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .opacity(currentStep > 0 ? 1 : 0)
                .disabled(currentStep == 0)

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0 ..< totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                            .animation(.easeInOut(duration: 0.2), value: currentStep)
                    }
                }

                Spacer()

                nextButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 520, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.refreshPermissions()
            FnDictationMonitor.shared.pauseForOnboarding()
        }
        .onDisappear {
            FnDictationMonitor.shared.resumeAfterOnboarding()
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if currentStep == totalSteps - 1 {
            Button {
                completeOnboarding()
            } label: {
                Text("Start Using Vapor")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
        } else if currentStep == 0 {
            Color.clear
                .frame(width: 1, height: 1)
        } else if currentStep == 1 {
            Button {
                withAnimation {
                    slideDirection = .forward
                    currentStep += 1
                }
            } label: {
                Text("Next →")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.bothPermissionsGranted)
        } else if currentStep == 4 {
            if store.selectedLLMPath == .localGGUF && !store.localLLMReady && !store.isDownloading {
                Button {
                    withAnimation {
                        slideDirection = .forward
                        currentStep += 1
                    }
                } label: {
                    Text("Set Up Later →")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .help("Compression won't work until you configure an LLM in Settings.")
            } else {
                Button {
                    withAnimation {
                        slideDirection = .forward
                        currentStep += 1
                    }
                } label: {
                    Text("Next →")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderedProminent)
            }
        } else if currentStep == 5 {
            Button {
                if !store.openRouterApiKey.isEmpty {
                    store.saveOpenRouterConfig()
                } else {
                    store.skipOpenRouter()
                }
                withAnimation {
                    slideDirection = .forward
                    currentStep += 1
                }
            } label: {
                Text("Next →")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                withAnimation {
                    slideDirection = .forward
                    currentStep += 1
                }
            } label: {
                Text("Next →")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private var slideTransition: AnyTransition {
        let insertion: AnyTransition = slideDirection == .forward
            ? .move(edge: .trailing).combined(with: .opacity)
            : .move(edge: .leading).combined(with: .opacity)
        let removal: AnyTransition = slideDirection == .forward
            ? .move(edge: .leading).combined(with: .opacity)
            : .move(edge: .trailing).combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        FnDictationMonitor.shared.resumeAfterOnboarding()
        NSApp.keyWindow?.close()
    }

    // MARK: - Step Router

    @ViewBuilder
    private func stepView(for step: Int) -> some View {
        switch step {
        case 0:
            WelcomeStepView(onGetStarted: {
                withAnimation { slideDirection = .forward; currentStep = 1 }
            })
        case 1:
            PermissionsStepView(store: store)
        case 2:
            DictationStepView()
        case 3:
            CompressAndCopyStepView()
        case 4:
            LLMSetupStepView(store: store)
        case 5:
            OpenRouterSetupStepView(store: store)
        case 6:
            WindowManagementStepView()
        case 7:
            ScreenshotShelfStepView()
        case 8:
            BrowserBridgeStepView()
        case 9:
            ContextAndResearchStepView()
        case 10:
            AllSetStepView()
        default:
            EmptyView()
        }
    }
}

// MARK: - Shared Components

private struct KeyBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct ShortcutRow: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            KeyBadge(label: key)
                .frame(width: 130, alignment: .leading)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StepCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 44))
                        .foregroundStyle(iconColor)
                        .symbolRenderingMode(.hierarchical)

                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(description)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 400)
                }

                content
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
    }
}

private struct SelectionCard<Content: View>: View {
    let selected: Bool
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1)
        )
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStepView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            VStack(spacing: 10) {
                Text("Welcome to Vapor")
                    .font(.system(size: 26, weight: .bold))

                Text("Vapor is your AI workflow companion.\nDictate, capture context from screenshots and websites, compress prompts, and send them to any AI — all from a floating window.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            Button {
                onGetStarted()
            } label: {
                Text("Get Started →")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Step 1: Permissions

private struct PermissionsStepView: View {
    var store: OnboardingStore

    var body: some View {
        StepCard(
            icon: "lock.shield.fill",
            iconColor: .blue,
            title: "Grant Permissions",
            description: "Vapor needs microphone access to hear you and speech recognition to transcribe your words. Both are processed on-device — no audio leaves your Mac."
        ) {
            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    label: "Microphone",
                    granted: store.micGranted,
                    status: store.micStatus == .notDetermined ? "Not requested" : (store.micGranted ? "Granted" : "Denied")
                )
                permissionRow(
                    icon: "waveform",
                    label: "Speech Recognition",
                    granted: store.speechGranted,
                    status: store.speechStatus == .notDetermined ? "Not requested" : (store.speechGranted ? "Granted" : "Denied")
                )
            }
            .padding(.horizontal, 8)

            VStack(spacing: 10) {
                if !store.bothPermissionsGranted {
                    Button {
                        store.requestAllPermissions()
                    } label: {
                        Label("Grant Access", systemImage: "hand.raised.fill")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if store.micStatus == .denied || store.speechStatus == .denied {
                        Button {
                            store.openSystemSettings()
                        } label: {
                            Label("Open System Settings", systemImage: "gear")
                                .frame(maxWidth: 240)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                } else {
                    Label("All permissions granted!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            if !store.bothPermissionsGranted {
                Text("The \"Next\" button will unlock once both permissions are granted.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear { store.refreshPermissions() }
    }

    private func permissionRow(icon: String, label: String, granted: Bool, status: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Label(status, systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(granted ? .green : .orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(8)
    }
}

// MARK: - Step 2: Dictation

@MainActor
@Observable
private final class DictationDemoController {
    var demoText: String = ""
    var isListening: Bool = false

    private var dictationService = SpeechDictationService()
    private var localMonitor: Any?

    func start() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isFnDown = event.modifierFlags.contains(.function)
                if isFnDown, !self.isListening {
                    self.isListening = true
                    self.dictationService.onError = { msg in
                        self.isListening = false
                        self.demoText = "Error: \(msg)"
                    }
                    self.dictationService.startDictation { text, _ in
                        self.demoText = text
                    }
                } else if !isFnDown, self.isListening {
                    self.isListening = false
                    self.dictationService.pauseDictation()
                }
            }
            return event
        }
    }

    func stop() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        dictationService.stopDictation(commit: false)
        isListening = false
    }
}

private struct DictationStepView: View {
    @State private var demo = DictationDemoController()

    var body: some View {
        StepCard(
            icon: "mic.fill",
            iconColor: .red,
            title: "Dictate with the Fn Key",
            description: "Hold the Fn key to start dictating. Release to stop. Your speech appears in real-time."
        ) {
            ShortcutRow(key: "Fn (hold)", label: "Start recording")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(demo.isListening ? Color.red : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .animation(
                            demo.isListening
                                ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                                : .default,
                            value: demo.isListening
                        )
                    Text(demo.isListening ? "Listening…" : "Hold Fn to try dictation here")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !demo.demoText.isEmpty {
                        Button("Clear") { demo.demoText = "" }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.07))
                        .frame(minHeight: 60)

                    if demo.demoText.isEmpty {
                        Text("Your dictated words will appear here…")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .padding(10)
                    } else {
                        Text(demo.demoText)
                            .font(.system(size: 13))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .onAppear { demo.start() }
        .onDisappear { demo.stop() }
    }
}

// MARK: - Step 3: Compress & Copy (merged)

private struct CompressAndCopyStepView: View {
    var body: some View {
        StepCard(
            icon: "bolt.fill",
            iconColor: .yellow,
            title: "Compress & Copy",
            description: "Press ⌘ ↩ to compress your prompt and copy it to the clipboard. Vapor uses an LLM to remove filler words and fuse related concepts — saving tokens when it matters. You'll set up an LLM on the next step."
        ) {
            ShortcutRow(key: "⌘ ↩", label: "Compress & copy")
            ShortcutRow(key: "⌘ ⇧ C", label: "Copy original (no compression)")
            ShortcutRow(key: "⌘ K", label: "Copy original & clear editor")

            VStack(alignment: .leading, spacing: 8) {
                exampleRow(
                    label: "Before",
                    text: "write a python script that uses pandas to query real estate data",
                    color: .primary
                )
                Image(systemName: "arrow.down")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                exampleRow(
                    label: "After",
                    text: "writepythonscript usespandas queryrealestatedata",
                    color: .accentColor
                )
            }
            .padding(.horizontal, 8)
        }
    }

    private func exampleRow(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(color)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07))
                .cornerRadius(8)
        }
    }
}

// MARK: - Step 4: LLM Setup (two-card)

private struct LLMSetupStepView: View {
    @Bindable var store: OnboardingStore
    @State private var downloadError: String?

    var body: some View {
        StepCard(
            icon: "cpu.fill",
            iconColor: .purple,
            title: "Choose an LLM",
            description: "Vapor needs at least one LLM backend to compress prompts. Download a local model here, or set up OpenRouter (cloud) in the next step."
        ) {
            VStack(spacing: 12) {
                SelectionCard(
                    selected: store.selectedLLMPath == .localGGUF,
                    icon: "cube.box",
                    title: "Download a Local Model",
                    subtitle: "Free, runs entirely on your Mac"
                ) {
                    if store.localLLMReady {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text("\(store.compressionService.selectedLocalModel.displayName) ready")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        }
                    } else if store.compressionService.downloadedModelID != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 12))
                            Text("Selected model is not downloaded yet")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    } else if store.isDownloading {
                        VStack(spacing: 6) {
                            ProgressView(value: store.downloadProgress, total: 1.0)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: 280)

                            let model = store.selectedLocalModel
                            let pct = Int(store.downloadProgress * 100)
                            let downloaded = String(format: "%.1f", store.downloadProgress * model.sizeGB)
                            Text("\(pct)% — \(downloaded) / \(String(format: "%.1f", model.sizeGB)) GB")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Picker("Model", selection: $store.selectedLocalModel) {
                                ForEach(LocalLLMModel.curatedModels) { model in
                                    HStack {
                                        Text(model.displayName)
                                        Spacer()
                                        Text(String(format: "%.1f GB", model.sizeGB))
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(model)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 280, alignment: .leading)

                            Button {
                                startDownload()
                            } label: {
                                Label("Download Now", systemImage: "arrow.down.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Text("Requires ~\(String(format: "%.0f", store.selectedLocalModel.sizeGB + 0.5))GB storage")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = downloadError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
                .onTapGesture {
                    store.selectedLLMPath = .localGGUF
                }
            }
        }
    }

    private func startDownload() {
        downloadError = nil
        Task { @MainActor in
            do {
                try await store.downloadLocalLLM()
            } catch {
                downloadError = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Step 5: OpenRouter Setup (skippable)

private struct OpenRouterSetupStepView: View {
    @Bindable var store: OnboardingStore

    var body: some View {
        StepCard(
            icon: "cloud.fill",
            iconColor: .indigo,
            title: "OpenRouter (Cloud)",
            description: "Use a cloud LLM for compression and entity extraction. Works on any Mac — no GPU or local model needed. This is a fully standalone option."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    SecureField("Enter your OpenRouter API key", text: $store.openRouterApiKey)
                        .frame(maxWidth: 320)
                    Button {
                        store.testOpenRouterAPIKey()
                    } label: {
                        if store.isTestingOpenRouter {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            Text("Test")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.openRouterApiKey.isEmpty || store.isTestingOpenRouter)
                }

                if let result = store.openRouterTestResult {
                    Label(result, systemImage: result.contains("Valid") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(result.contains("Valid") ? .green : .red)
                }

                Text("Get a free API key at openrouter.ai → Settings → API Keys")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Divider()

                Text("Entity Extraction Model")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("NER Model", selection: $store.selectedNERModel) {
                    ForEach(NERModel.curatedModels) { model in
                        HStack {
                            Text(model.displayName)
                            Spacer()
                            Text(model.priceLabel)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320, alignment: .leading)

                Toggle("Use custom model", isOn: $store.useCustomNERModel)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                if store.useCustomNERModel {
                    TextField("Custom model ID (e.g. google/gemma-4-31b-it)", text: $store.customNERModel)
                        .frame(maxWidth: 320)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                Text("Compression Model")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker("Compression Model", selection: $store.selectedCompressionModel) {
                    ForEach(CompressionModelOption.curatedModels) { model in
                        HStack {
                            Text(model.displayName)
                            Spacer()
                            Text(model.priceLabel)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320, alignment: .leading)

                Toggle("Use custom model", isOn: $store.useCustomCompressionModel)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                if store.useCustomCompressionModel {
                    TextField("Custom model ID (e.g. anthropic/claude-sonnet-4)", text: $store.openRouterCompressionModel)
                        .frame(maxWidth: 320)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Step 6: Window Management

private struct WindowManagementStepView: View {
    var body: some View {
        StepCard(
            icon: "macwindow.on.rectangle",
            iconColor: .teal,
            title: "Focus from Anywhere",
            description: "Vapor floats above all apps. Summon it instantly with a global shortcut or toggle between compact and full views."
        ) {
            VStack(spacing: 12) {
                ShortcutRow(key: "⌃ ⌥ Space", label: "Focus Vapor from any app")
                ShortcutRow(key: "⌘ \\", label: "Toggle compact / full view")
            }
        }
    }
}

// MARK: - Step 7: Screenshot Shelf

private struct ScreenshotShelfStepView: View {
    var body: some View {
        StepCard(
            icon: "photo.on.rectangle.angled",
            iconColor: .orange,
            title: "Screenshot Shelf",
            description: "Vapor automatically detects screenshots on your Desktop. They appear in the screenshot panel where you can add them to your prompt context."
        ) {
            VStack(spacing: 12) {
                ShortcutRow(key: "⌘ ⇧ S", label: "Focus screenshot shelf")

                VStack(alignment: .leading, spacing: 6) {
                    Text("How it works:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("1. Take a screenshot (⌘ ⇧ 4 or ⌘ ⇧ 5)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("2. It appears in the shelf within ~10 seconds")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("3. Select it and press Enter to add to context")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07))
                .cornerRadius(8)
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Step 8: Browser Bridge

private struct BrowserBridgeStepView: View {
    var body: some View {
        StepCard(
            icon: "safari.fill",
            iconColor: .blue,
            title: "Browser Integration",
            description: "Send compressed prompts directly into AI chat tabs in Chrome. No copy-paste needed."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ShortcutRow(key: "⌘ ⇧ P", label: "Send to browser tab")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("1. Load the Browser Extension from the DMG")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("   (Help menu → Show Onboarding → reinstall from DMG)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("2. Open chrome://extensions → Enable Developer mode")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("3. Click \"Load unpacked\" → select the Browser Extension folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("4. Enable browser integration in Settings → Browser")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("5. Copy the auth token from Settings → Browser → Authentication")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("6. Open the extension popup → Settings → Paste the token → Save")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07))
                .cornerRadius(8)

                Text("The token is required — without it the extension cannot connect to Vapor.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Step 9: Context & Research

private struct ContextAndResearchStepView: View {
    var body: some View {
        StepCard(
            icon: "text.magnifyingglass",
            iconColor: .mint,
            title: "Context & Research",
            description: "Vapor builds a searchable index of everything you capture — web pages, screenshots, entities, and more."
        ) {
            VStack(spacing: 12) {
                ShortcutRow(key: "⌘ ⇧ E", label: "Context explorer")
                ShortcutRow(key: "⌘ ⇧ L", label: "Activity log")
                ShortcutRow(key: "⌘ ⌥ C", label: "Focus context tray")
                ShortcutRow(key: "⌘ ⇧ T", label: "Focus tool rail")

                VStack(alignment: .leading, spacing: 6) {
                    Text("What's inside:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("• Full-text search powered by on-device embeddings")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("• Entity extraction (people, orgs, products, locations)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("• Automatic summarization of captured content")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("• Vector-based similarity search across all items")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07))
                .cornerRadius(8)
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Step 10: All Set

private struct AllSetStepView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)

                    Text("You're All Set!")
                        .font(.system(size: 24, weight: .bold))

                    Text("Here's a quick reference to get you started:")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Dictation & Editing")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ShortcutRow(key: "Fn (hold)", label: "Dictate")
                    ShortcutRow(key: "⌘ ↩", label: "Compress & copy")
                    ShortcutRow(key: "⌘ ⇧ C", label: "Copy original")
                    ShortcutRow(key: "⌘ K", label: "Copy & clear")
                }
                .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Panels & Windows")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ShortcutRow(key: "⌘ ⇧ S", label: "Screenshot shelf")
                    ShortcutRow(key: "⌘ ⌥ C", label: "Context tray")
                    ShortcutRow(key: "⌘ ⇧ E", label: "Context explorer")
                    ShortcutRow(key: "⌘ Y", label: "Prompt history")
                    ShortcutRow(key: "⌘ ⇧ L", label: "Activity log")
                }
                .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Window & Navigation")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ShortcutRow(key: "⌃ ⌥ Space", label: "Focus Vapor from any app")
                    ShortcutRow(key: "⌘ \\", label: "Toggle compact / full")
                    ShortcutRow(key: "⌘ /", label: "All shortcuts help")
                }
                .padding(.horizontal, 32)

                Text("Press ⌘ / anytime to see all keyboard shortcuts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
    }
}
