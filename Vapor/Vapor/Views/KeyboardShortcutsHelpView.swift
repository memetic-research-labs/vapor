import SwiftUI

struct KeyboardShortcutsHelpView: View {
    private let sections = AppCommandRegistry.helpSections()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(AppCommandRegistry.command(.keyboardShortcuts).helpShortcutDisplay ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.title) { section in
                        shortcutSection(section.title, rows: section.rows)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 360, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func shortcutSection(_ title: String, rows: [(shortcut: String, description: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                shortcutRow(row.shortcut, row.description)
            }
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
