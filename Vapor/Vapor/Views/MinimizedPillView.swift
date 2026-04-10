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

    // State
    var text: String = ""
    var isDictating: Bool = false
    var isCompressing: Bool = false
    var isModelReady: Bool = true
    var isModelLoading: Bool = false
    var inputLevel: Float = 0

    @State private var glowPulse = false
    @State private var showCopied = false

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
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: glowColor.opacity(glowPulse ? 0.45 : 0.2), radius: glowPulse ? 10 : 5, x: 0, y: 0)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .onChange(of: isCompressing) { wasCompressing, isNowCompressing in
            if wasCompressing && !isNowCompressing {
                withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeInOut(duration: 0.3)) { showCopied = false }
                }
            }
        }
        // Hidden buttons for keyboard shortcuts
        .background {
            Group {
                Button("") {
                    if hasContent && isModelReady { onCompressAndCopy() }
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("") {
                    onClear()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("") {
                    if hasContent { onCopyOriginal() }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("") {
                    onShowHistory()
                }
                .keyboardShortcut("y", modifiers: .command)
            }
            .hidden()
        }
    }

    // MARK: - Text Area

    private var textArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if hasContent {
                    Text(text)
                        .font(.system(size: 13, design: .default))
                        .foregroundColor(.primary.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("textBottom")
                } else {
                    Text("Hold Fn to dictate…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("textBottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            statusIcon

            statusLabel

            Spacer()

            if hasContent {
                Text("\(wordCount) words")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
        switch status {
        case .idle:
            Text("Vapor")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.8))
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

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 6) {
            // Compress & Copy
            Button(action: { if hasContent && isModelReady { onCompressAndCopy() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Compress")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!hasContent || !isModelReady)
            .help("Compress & Copy (⌘↩)")

            // Copy Original
            Button(action: { if hasContent { onCopyOriginal() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                    Text("Copy")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasContent)
            .help("Copy Original (⌘⇧C)")

            // Clear (copy + clear)
            Button(action: onClear) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                    Text("Clear")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasContent)
            .help("Copy & Clear (⌘K)")

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
