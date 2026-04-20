import SwiftUI

struct ToolSidebarView: View {
    private let railWidth: CGFloat = 42
    private let buttonSize: CGFloat = 34

    @Bindable var viewModel: EditorViewModel
    let dictationService: SpeechDictationService
    let preferences: UserPreferences
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(MainWindowFocusStore.self) private var focusStore
    let onChooseTarget: () -> Void
    let onPostToTarget: () -> Void
    let onToggleDictation: () -> Void

    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 8) {
            targetButton
            postButton
            dictationButton

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .vaporFocusToolRail)) { _ in
            focusStore.focus(.toolRail)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporToolMoveUp)) { _ in
            guard focusStore.activeZone == .toolRail else { return }
            selectedIndex = max(0, selectedIndex - 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporToolMoveDown)) { _ in
            guard focusStore.activeZone == .toolRail else { return }
            selectedIndex = min(2, selectedIndex + 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporToolActivate)) { _ in
            guard focusStore.activeZone == .toolRail else { return }
            activateSelectedTool()
        }
    }

    private var targetButton: some View {
        Button(action: onChooseTarget) {
            sidebarIcon(symbol: "safari", tint: targetTint, isSelected: focusStore.activeZone == .toolRail && selectedIndex == 0)
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
            sidebarIcon(symbol: browserBridge.canPostToSelectedTarget ? "paperplane.fill" : "paperplane", tint: postTint, isSelected: focusStore.activeZone == .toolRail && selectedIndex == 1)
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
                                .stroke((focusStore.activeZone == .toolRail && selectedIndex == 2) ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1.5)
                        )
                        .editorGlow(isFocused: focusStore.activeZone == .toolRail && selectedIndex == 2)
                } else {
                    sidebarIcon(symbol: "mic", tint: .secondary, isSelected: focusStore.activeZone == .toolRail && selectedIndex == 2)
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
        switch selectedIndex {
        case 0: onChooseTarget()
        case 1: onPostToTarget()
        case 2: onToggleDictation()
        default: break
        }
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
