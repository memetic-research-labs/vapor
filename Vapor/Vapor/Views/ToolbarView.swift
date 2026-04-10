import SwiftUI

struct ToolbarView: View {
    @Bindable var viewModel: EditorViewModel
    let dictationService: SpeechDictationService
    let preferences: UserPreferences
    let onCompressAndCopy: () async -> Void
    let onCopyOriginal: () -> Void
    let onClear: () -> Void
    let onToggleSettings: () -> Void
    let onToggleDictation: () -> Void
    let onToggleTest: () -> Void
    let onMinimize: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            dictationButton

            Button {
                Task { await onCompressAndCopy() }
            } label: {
                HStack(spacing: 4) {
                    if viewModel.isCompressing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "bolt.horizontal")
                    }
                    Text("Compress & Copy")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.content.isEmpty || viewModel.isCompressing)

            Button {
                onCopyOriginal()
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.content.isEmpty)
            .help("Copy Original ( ⌘ C )")

            Spacer()

            Button {
                onClear()
            } label: {
                Text("Clear")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.content.isEmpty)

            Button {
                onToggleSettings()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Button {
                onToggleTest()
            } label: {
                Image(systemName: "flask")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("OpenRouter Test")

            Button {
                onMinimize()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Minimize to compact view ( Escape )")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 44)
    }

    private var dictationButton: some View {
        Button {
            onToggleDictation()
        } label: {
            HStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    if viewModel.isDictating {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.red)
                    } else {
                        Image(systemName: "mic")
                            .foregroundColor(.secondary)
                    }

                    if preferences.autoCompressEnabled {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                            .offset(x: 6, y: -4)
                    }
                }

                if viewModel.isDictating {
                    AudioLevelView(
                        inputLevel: dictationService.inputLevel,
                        isActive: true
                    )
                }
            }
        }
        .buttonStyle(.bordered)
        .help(dictationHelpText)
    }

    private var dictationHelpText: String {
        if viewModel.isDictating {
            return "Listening… (release Fn to stop)"
        }
        return "Hold Fn key to dictate"
    }
}