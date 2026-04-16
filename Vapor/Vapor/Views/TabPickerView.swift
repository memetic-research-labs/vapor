import SwiftUI

struct TabPickerView: View {
    let tabs: [BrowserTab]
    let selectedTarget: BrowserTarget?
    let onSelect: (BrowserTab) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            TextField("Filter tabs", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(16)

            List(filteredTabs) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    tabRow(tab)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 520, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose Browser Tab")
                    .font(.system(size: 14, weight: .semibold))

                if let selectedTarget {
                    Text("Current target: \(selectedTarget.displayLabel)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Pick where Vapor should post the current prompt")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var filteredTabs: [BrowserTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tabs }
        return tabs.filter {
            $0.displayTitle.lowercased().contains(query)
                || $0.displayHost.lowercased().contains(query)
                || $0.url.lowercased().contains(query)
                || $0.platform.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private func tabRow(_ tab: BrowserTab) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tab.matchesKnownAIHost ? .accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tab.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if selectedTarget?.displayLabel == tab.displayHost {
                        Text("Current")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text(tab.displayHost)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(tab.url)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
