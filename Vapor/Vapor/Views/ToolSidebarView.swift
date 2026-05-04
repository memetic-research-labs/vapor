import SwiftUI

private enum ToolRailItem: CaseIterable {
    case target
    case post
    case dictation
}

struct ToolSidebarView: View {
    private let railWidth: CGFloat = 42
    private let buttonSize: CGFloat = 34

    @Bindable var viewModel: EditorViewModel
    let dictationService: SpeechDictationService
    let preferences: UserPreferences
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(MainWindowFocusStore.self) private var focusStore
    @Environment(CompressionService.self) private var compressionService
    let onChooseTarget: () -> Void
    let onPostToTarget: () -> Void
    let onToggleDictation: () -> Void

    @State private var selectedItem: ToolRailItem = .target
    @State private var showingOpenRouterConfig = false
    private let oauthService = OpenRouterOAuthService.shared
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            targetButton
            postButton
            dictationButton

            Spacer(minLength: 0)

            openRouterButton
        }
        .padding(.vertical, 6)
        .frame(width: railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showingOpenRouterConfig) {
            OpenRouterConfigView { newKey in
                compressionService.setOpenRouterApiKey(
                    newKey,
                    model: UserDefaults.standard.string(forKey: "openRouterModel") ?? compressionService.openRouterModel
                )
            }
        }
        .onAppear {
            startPulseIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporOpenRouterKeyChanged)) { _ in
            if oauthService.isConnected {
                withAnimation(.easeOut(duration: 0.3)) { pulseScale = 1.0 }
            } else {
                startPulseIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporFocusToolRail)) { _ in
            focusStore.focus(.toolRail)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporToolMoveUp)) { _ in
            guard focusStore.activeZone == .toolRail else { return }
            moveSelection(delta: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporToolMoveDown)) { _ in
            guard focusStore.activeZone == .toolRail else { return }
            moveSelection(delta: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporToolActivate)) { _ in
            guard focusStore.activeZone == .toolRail else { return }
            activateSelectedTool()
        }
    }

    private var targetButton: some View {
        Button(action: onChooseTarget) {
            sidebarIcon(symbol: "safari", tint: targetTint, isSelected: focusStore.activeZone == .toolRail && selectedItem == .target)
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .help(targetHelpText)
        .contextMenu {
            Button("Choose Browser Tab", action: onChooseTarget)

            if browserBridge.canReopenSelectedTarget,
               let target = browserBridge.selectedTarget {
                Button("Open \(target.displayLabel) again") {
                    browserBridge.openSelectedTarget()
                }
            }
        }
    }

    private var postButton: some View {
        Button(action: onPostToTarget) {
            sidebarIcon(symbol: browserBridge.canPostToSelectedTarget ? "paperplane.fill" : "paperplane", tint: postTint, isSelected: focusStore.activeZone == .toolRail && selectedItem == .post)
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .opacity((viewModel.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !browserBridge.isExtensionConnected) ? 0.45 : 1)
        .help(postHelpText)
        .contextMenu {
            if browserBridge.canReopenSelectedTarget,
               let target = browserBridge.selectedTarget {
                Button("Open \(target.displayLabel) again") {
                    browserBridge.openSelectedTarget()
                }
            }
        }
    }

    private var dictationButton: some View {
        Button(action: onToggleDictation) {
            ZStack {
                if viewModel.isDictating {
                    AudioLevelView(inputLevel: dictationService.inputLevel, isActive: true)
                        .frame(width: buttonSize, height: buttonSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke((focusStore.activeZone == .toolRail && selectedItem == .dictation) ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                        )
                        .editorGlow(isFocused: focusStore.activeZone == .toolRail && selectedItem == .dictation)
                } else {
                    sidebarIcon(symbol: "mic", tint: .secondary, isSelected: focusStore.activeZone == .toolRail && selectedItem == .dictation)
                }
            }
            .overlay(alignment: .topTrailing) {
                if preferences.autoCompressEnabled {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(2)
                }
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .help(dictationHelpText)
    }

    // MARK: - OpenRouter button

    private var openRouterButton: some View {
        Button {
            showingOpenRouterConfig = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                oauthService.isConnected
                                    ? Color.indigo.opacity(0.25)
                                    : Color.orange.opacity(0.6),
                                lineWidth: oauthService.isConnected ? 1 : 1.5
                            )
                    )
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: oauthService.isConnected ? "cloud.fill" : "cloud")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(oauthService.isConnected ? .indigo : .orange)
                    .scaleEffect(oauthService.isConnected ? 1.0 : pulseScale)
            }
            .overlay(alignment: .topTrailing) {
                if oauthService.isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -3)
                }
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .help(oauthService.isConnected ? "OpenRouter connected" : "Connect OpenRouter (required for cloud features)")
        .padding(.bottom, 4)
    }

    private func startPulseIfNeeded() {
        guard !oauthService.isConnected else { return }
        if reduceMotion {
            // Provide a static visual cue (slightly enlarged) without animation
            pulseScale = 1.08
        } else {
            withAnimation(
                .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.18
            }
        }
    }

    private func sidebarIcon(symbol: String, tint: Color, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor.opacity(0.3) : tint.opacity(0.25), lineWidth: isSelected ? 1.5 : 1)
                )
                .frame(width: buttonSize, height: buttonSize)

            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(tint)
        }
        .overlay(alignment: .topTrailing) {
            if symbol == "safari", let target = browserBridge.selectedTarget {
                Circle()
                    .fill(target.isConnected && browserBridge.isExtensionConnected ? .green : .orange)
                    .frame(width: 7, height: 7)
                    .offset(x: 3, y: -3)
            }
        }
        .editorGlow(isFocused: isSelected)
    }

    private func activateSelectedTool() {
        switch selectedItem {
        case .target: onChooseTarget()
        case .post: onPostToTarget()
        case .dictation: onToggleDictation()
        }
    }

    private func moveSelection(delta: Int) {
        let items = ToolRailItem.allCases
        guard let currentIndex = items.firstIndex(of: selectedItem) else {
            selectedItem = items.first ?? .target
            return
        }

        let nextIndex = min(max(0, currentIndex + delta), items.count - 1)
        selectedItem = items[nextIndex]
    }

    private var targetTint: Color {
        guard let target = browserBridge.selectedTarget else { return .secondary }
        return (target.isConnected && browserBridge.isExtensionConnected) ? .blue : .orange
    }

    private var postTint: Color {
        browserBridge.canPostToSelectedTarget ? .blue : .secondary
    }

    private var targetHelpText: String {
        guard let target = browserBridge.selectedTarget else { return "Choose browser tab target" }
        return target.isConnected && browserBridge.isExtensionConnected
            ? "Target: \(target.displayLabel)"
            : "Target unavailable: \(target.displayLabel)"
    }

    private var postHelpText: String {
        guard !viewModel.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter text to post"
        }
        guard browserBridge.isExtensionConnected else {
            return "Browser extension not connected"
        }
        guard let target = browserBridge.selectedTarget else {
            return "Choose a browser tab target first"
        }
        if browserBridge.canPostToSelectedTarget {
            return "Post to \(target.displayLabel) (⌘⇧P)"
        }
        return "Target unavailable: \(target.displayLabel)"
    }

    private var dictationHelpText: String {
        if viewModel.isDictating {
            return "Listening… (release Fn to stop)"
        }
        return "Hold Fn key to dictate"
    }
}
