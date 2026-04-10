import SwiftUI

struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("⌘ /")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    shortcutSection("Dictation") {
                        shortcutRow("Fn (hold)", "Start dictating")
                        shortcutRow("Fn (release)", "Stop dictating, commit text")
                    }

                    shortcutSection("Compression") {
                        shortcutRow("⌘ ↩", "Compress & copy to clipboard")
                        shortcutRow("⇧ ⌘ C", "Copy original text to clipboard")
                        shortcutRow("⌘ K", "Copy original & clear")
                    }

                    shortcutSection("Window") {
                        shortcutRow("⌃ ⌥ Space", "Focus Vapor (global)")
                        shortcutRow("⌘ \\", "Toggle compact / full view")
                        shortcutRow("Escape", "Minimize to compact view")
                    }

                    shortcutSection("Editing") {
                        shortcutRow("⌘ A", "Select all text")
                        shortcutRow("⌘ Z", "Undo")
                        shortcutRow("⌘ ⇧ Z", "Redo")
                        shortcutRow("⌘ V", "Paste")
                    }

                    shortcutSection("Navigation") {
                        shortcutRow("⌘ Y", "Open prompt history")
                        shortcutRow("⌘ ,", "Open settings")
                        shortcutRow("⌘ /", "Show this help")
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 340, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func shortcutSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 110, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.85))
            Spacer()
        }
    }
}
