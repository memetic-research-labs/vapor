import SwiftUI

struct ToolbarView: View {
    @Bindable var viewModel: EditorViewModel
    let preferences: UserPreferences
    let onCompressAndCopy: () async -> Void
    let onCopyOriginal: () -> Void
    let onShowHistory: () -> Void
    let onToggleTest: () -> Void
    let onToggleContextTray: () -> Void
    let onMinimize: () -> Void

    var body: some View {
        HStack(spacing: 8) {
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
            .help("Copy Original ( ⌘ ⇧ C )")

            Button {
                onShowHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Prompt History ( ⌘ Y )")

            Spacer()

            Button {
                onToggleContextTray()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Toggle context tray")

            SettingsLink {
                Image(systemName: "gearshape")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            if preferences.showExperimentsButton {
                Button {
                    onToggleTest()
                } label: {
                    Image(systemName: "flask")
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .help("OpenRouter Test")
            }

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
        .background(.bar)
    }
}
