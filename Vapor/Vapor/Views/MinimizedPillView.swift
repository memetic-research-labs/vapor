import SwiftUI

enum PillStatus {
    case idle
    case modelLoading
    case dictating
    case compressing
    case copied
}

struct MinimizedPillView: View {
    // Callbacks
    let onExpand: () -> Void
    let onCompressAndCopy: () -> Void
    let onCopyOriginal: () -> Void
    let onClear: () -> Void
    let onShowHistory: () -> Void
    let onShowHelp: () -> Void
    let onSendToBrowser: () -> Void

    // State
    @Binding var text: String
    var statusMessage: String = "Ready"
    var isDictating: Bool = false
    var isCompressing: Bool = false
    var isModelReady: Bool = true
    var isModelLoading: Bool = false
    var isBrowserConnected: Bool = false
    var inputLevel: Float = 0

    @State private var glowPulse = false
    @State private var showCopied = false
    @State private var isEditorFocused = false

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private var status: PillStatus {
        if showCopied { return .copied }
        if isCompressing { return .compressing }
        if isDictating { return .dictating }
        if isModelLoading { return .modelLoading }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Text Area (top, scrolling)
            textArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // MARK: - Status Bar (mic + state)
            statusBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            // MARK: - Controls Bar (bottom)
            controlsBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0)
                        .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: glowColor.opacity(glowPulse ? 0.45 : 0.2), radius: glowPulse ? 10 : 5, x: 0, y: 0)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .onChange(of: isCompressing) { wasCompressing, isNowCompressing in
            // Only show "Copied" if compression finished AND there's still content
            // (if compression failed, the toast shows the error and content remains)
            if wasCompressing && !isNowCompressing && hasContent {
                withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeInOut(duration: 0.3)) { showCopied = false }
                }
            }
        }
        // Keyboard shortcuts are handled at app level via menu commands (VaporApp.swift)
        // This ensures they work even when TextEditor has focus.
    }

    // MARK: - Text Area

    private var textArea: some View {
        PillTextEditor(text: $text, isFocused: $isEditorFocused, isDictating: isDictating)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .editorGlow(
                isFocused: isEditorFocused,
                isDictating: isDictating,
                inputLevel: inputLevel
            )
            .padding(6)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            statusIcon

            browserStatusIcon

            statusLabel

            Spacer()

            if hasContent {
                Text("\(wordCount) words")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var browserStatusIcon: some View {
        Group {
            if isBrowserConnected {
                Image(systemName: "safari.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .idle:
            Circle()
                .fill(Color.green.opacity(0.85))
                .frame(width: 10, height: 10)

        case .modelLoading:
            ProgressView()
                .controlSize(.mini)

        case .dictating:
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                    .symbolEffect(.bounce, options: .repeating.speed(2), value: isDictating)

                AudioLevelView(inputLevel: inputLevel, isActive: true)
                    .frame(height: 12)
            }

        case .compressing:
            ProgressView()
                .controlSize(.mini)

        case .copied:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        let isStatusBusy = statusMessage != "Ready" && !statusMessage.isEmpty && !statusMessage.hasPrefix("Done")
        if isStatusBusy {
            Text(statusMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else {
            switch status {
            case .idle:
                Text("Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            case .modelLoading:
                Text("Loading model…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            case .dictating:
                Text("Listening")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red.opacity(0.9))
            case .compressing:
                Text("Compressing…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            case .copied:
                Text("Copied to clipboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 4) {
            // Compress & Copy
            Button(action: { if hasContent && isModelReady { onCompressAndCopy() } }, label: {
                Image(systemName: "bolt.horizontal")
                    .font(.system(size: 12, weight: .semibold))
            })
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!hasContent || !isModelReady)
            .help("Compress & Copy ( ⌘ ↩ )")

            // Copy Original
            Button(action: { if hasContent { onCopyOriginal() } }, label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            })
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasContent)
            .help("Copy Original ( ⌘ ⇧ C )")

            // Send to Browser
            if isBrowserConnected {
                Button(action: { if hasContent { onSendToBrowser() } }, label: {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                })
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasContent)
                .help("Send to Browser ( ⌘ ⇧ ↩ )")
            }

            // Clear (copy + clear)
            Button(action: onClear) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasContent)
            .help("Copy & Clear ( ⌘ K )")

            // Help
            Button(action: onShowHelp) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Keyboard Shortcuts ( ⌘ / )")

            Spacer()

            // Expand to full UI
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open full editor")
        }
    }

    // MARK: - Glow

    private var glowColor: Color {
        switch status {
        case .dictating: return .red
        case .copied: return .green
        default: return .accentColor
        }
    }
}
