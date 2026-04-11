import AVFoundation
import Speech
import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @State private var store = OnboardingStore.shared
    @State private var currentStep: Int = 0
    @State private var slideDirection: SlideDirection = .forward
    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 8

    enum SlideDirection {
        case forward, backward
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step content with slide transition
            ZStack {
                stepView(for: currentStep)
                    .id(currentStep)
                    .transition(slideTransition)
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom navigation bar
            HStack(alignment: .center) {
                // Back button
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

                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0 ..< totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                            .animation(.easeInOut(duration: 0.2), value: currentStep)
                    }
                }

                Spacer()

                // Next / Finish / Skip button
                if currentStep == totalSteps - 1 {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Start Using Vapor")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                } else if currentStep == 1 {
                    // Permissions step: Next disabled until both granted
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
                    // LLM download step: can skip
                    Button {
                        withAnimation {
                            slideDirection = .forward
                            currentStep += 1
                        }
                    } label: {
                        Text("Next →")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
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
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 480, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.refreshPermissions()
            // Pause the main Fn monitor to avoid audio engine conflicts with the dictation demo
            FnDictationMonitor.shared.pauseForOnboarding()
        }
        .onDisappear {
            // Restart the main Fn monitor when the onboarding window closes
            FnDictationMonitor.shared.resumeAfterOnboarding()
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
        dismiss()
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
            CompressStepView()
        case 4:
            LLMDownloadStepView(store: store)
        case 5:
            CopyAndClearStepView()
        case 6:
            WindowManagementStepView()
        case 7:
            AllSetStepView()
        default:
            EmptyView()
        }
    }
}

// MARK: - Shared Components

/// A pill-shaped keyboard key badge.
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

/// A shortcut row: key badge + description label.
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

/// Standard step card with title, icon, description, and body content.
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
                        .frame(maxWidth: 380)
                }

                content
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStepView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 10) {
                Text("Welcome to Vapor")
                    .font(.system(size: 26, weight: .bold))

                Text("Voice-to-text dictation & AI prompt compression for macOS.\nVapor floats above all your windows so you can dictate prompts and paste them anywhere.")
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

// MARK: - Step 2: Permissions

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
                Text("The "Next" button will unlock once both permissions are granted.")
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

// MARK: - Step 3: Dictation

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
                    self.dictationService.startDictation { text, _ in
                        Task { @MainActor in self.demoText = text }
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

            // Live demo area
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

// MARK: - Step 4: Compress & Copy

private struct CompressStepView: View {
    var body: some View {
        StepCard(
            icon: "bolt.fill",
            iconColor: .yellow,
            title: "Compress & Copy",
            description: "Press ⌘ ↩ to compress your prompt and copy it to the clipboard. Vapor removes filler words and fuses related concepts for maximum token efficiency."
        ) {
            ShortcutRow(key: "⌘ ↩", label: "Compress & copy")

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

// MARK: - Step 5: Download Local LLM

private struct LLMDownloadStepView: View {
    var store: OnboardingStore
    @State private var downloadError: String? = nil

    var body: some View {
        StepCard(
            icon: "cpu.fill",
            iconColor: .purple,
            title: "Download the Local LLM",
            description: "The on-device LLM produces significantly better compression. It's free, runs locally, and your data never leaves your Mac."
        ) {
            // Feature pills
            HStack(spacing: 12) {
                featurePill(icon: "dollarsign.circle", label: "Free")
                featurePill(icon: "lock.shield", label: "Private")
                featurePill(icon: "sparkles", label: "Best Quality")
            }

            VStack(spacing: 10) {
                Text("Qwen2.5-7B-Instruct · 4.7 GB download")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if store.localLLMReady {
                    Label("Model ready!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14, weight: .semibold))
                } else if store.isDownloading {
                    VStack(spacing: 6) {
                        ProgressView(value: store.downloadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 300)

                        let pct = Int(store.downloadProgress * 100)
                        let downloaded = String(format: "%.1f", store.downloadProgress * 4.7)
                        Text("\(pct)% — \(downloaded) / 4.7 GB")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        startDownload()
                    } label: {
                        Label("Download Now", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if let error = downloadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func featurePill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .foregroundStyle(.accentColor)
        .cornerRadius(20)
    }

    private func startDownload() {
        downloadError = nil
        Task {
            do {
                try await store.downloadLocalLLM()
            } catch {
                downloadError = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Step 6: Copy & Clear

private struct CopyAndClearStepView: View {
    var body: some View {
        StepCard(
            icon: "trash.fill",
            iconColor: .orange,
            title: "Copy & Clear",
            description: "Press ⌘ K to copy your original text and clear the editor. Your text is never lost — it's automatically saved to prompt history."
        ) {
            ShortcutRow(key: "⌘ K", label: "Copy original & clear")
        }
    }
}

// MARK: - Step 7: Window Management

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

// MARK: - Step 8: All Set

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
                    ShortcutRow(key: "Fn (hold)", label: "Dictate")
                    ShortcutRow(key: "⌘ ↩", label: "Compress & copy")
                    ShortcutRow(key: "⌘ K", label: "Copy & clear")
                    ShortcutRow(key: "⌘ Y", label: "Prompt history")
                    ShortcutRow(key: "⌘ /", label: "All shortcuts")
                    ShortcutRow(key: "⌃ ⌥ Space", label: "Focus Vapor")
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


