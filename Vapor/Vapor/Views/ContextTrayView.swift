import SwiftUI

struct ContextTrayView: View {
    @Environment(ContextQueueService.self) private var contextQueue

    @State private var searchText = ""
    @State private var showReadyOnly = false

    private var filteredItems: [ContextItem] {
        let items = showReadyOnly ? contextQueue.ready : contextQueue.ready + contextQueue.queue + contextQueue.processing + contextQueue.failed
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter {
            $0.sourceTitle.lowercased().contains(query) ||
            $0.sourceURL.lowercased().contains(query) ||
            $0.textContent?.lowercased().contains(query) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            searchBar

            Divider()

            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredItems) { item in
                            ContextItemRow(item: item)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .contextMenu {
                                    Button("Insert into editor") {
                                        insertItem(item)
                                    }
                                    Button("Copy text") {
                                        copyItemText(item)
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) {
                                        contextQueue.remove(item)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            footerBar
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerBar: some View {
        HStack {
            Text("Context")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text("\(contextQueue.ready.count) ready")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            TextField("Filter…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No context items yet")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Use the browser extension to capture articles and text")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footerBar: some View {
        HStack(spacing: 6) {
            Button {
                showReadyOnly.toggle()
            } label: {
                Image(systemName: showReadyOnly ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(showReadyOnly ? .green : .secondary)
                Text("Ready only")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(filteredItems.count) items")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Button {
                contextQueue.clearCompleted()
            } label: {
                Text("Clear")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(contextQueue.ready.isEmpty && contextQueue.failed.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func insertItem(_ item: ContextItem) {
        guard let text = item.textContent, !text.isEmpty else { return }
        let snippet = text.prefix(2000)
        NotificationCenter.default.post(name: .vaporInsertContextItem, object: snippet)
    }

    private func copyItemText(_ item: ContextItem) {
        guard let text = item.textContent, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ContextItemRow: View {
    let item: ContextItem

    var body: some View {
        HStack(spacing: 8) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(item.sourceTitle.isEmpty ? "Untitled" : item.sourceTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(item.kind.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    if !item.sourceURL.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(hostFromURL(item.sourceURL))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            if item.textContent != nil {
                Text("\(item.textContent!.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private var statusDot: some View {
        switch item.status {
        case .pending:
            Circle()
                .fill(Color.gray)
                .frame(width: 6, height: 6)
        case .processing:
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 6, height: 6)
        case .ready:
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
        case .failed:
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
        }
    }

    private func hostFromURL(_ url: String) -> String {
        guard let components = URL(string: url)?.host else { return "" }
        return components
    }
}
