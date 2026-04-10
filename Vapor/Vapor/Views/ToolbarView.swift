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

    var body: some View {
        HStack(spacing: 10) {
            dictationButton

            Button {
                Task { await onCompressAndCopy() }
            } label: {
                if viewModel.isCompressing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "bolt.horizontal")
                }
                Text("Compress & Copy")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.content.isEmpty || viewModel.isCompressing)

            Button {
                onCopyOriginal()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.content.isEmpty)
            .help("Copy Original ( ⌘ C )")

            Spacer()

            Button("Clear") {
                onClear()
            }
            .disabled(viewModel.content.isEmpty)

            Button {
                onToggleSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)

            Button {
                onToggleTest()
            } label: {
                Image(systemName: "flask")
            }
            .buttonStyle(.borderless)
            .help("OpenRouter Test")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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