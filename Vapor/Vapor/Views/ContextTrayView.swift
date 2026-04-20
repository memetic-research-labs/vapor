import SwiftUI

struct ContextTrayView: View {
    @Environment(ContextQueueService.self) private var contextQueue
    @Environment(MainWindowFocusStore.self) private var focusStore
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""
    @State private var showReadyOnly = false
    @State private var selectedItemID: UUID?

    private var filteredItems: [ContextItem] {
        var items = showReadyOnly ? contextQueue.ready : contextQueue.ready + contextQueue.queue + contextQueue.processing + contextQueue.failed
        items.sort { $0.capturedAt > $1.capturedAt }
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredItems) { item in
                                Button {
                                    focusStore.focus(.contextTray)
                                    selectedItemID = item.id
                                    openDetail(item: item)
                                } label: {
                                    ContextItemRow(item: item, isSelected: focusStore.activeZone == .contextTray && selectedItemID == item.id)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .id(item.id)
                                .contextMenu {
                                    Button("Open") {
                                        openDetail(item: item)
                                    }
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
                    .onChange(of: selectedItemID) { _, id in
                        guard focusStore.activeZone == .contextTray, let id else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            footerBar
        }
        .frame(width: 248)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .vaporFocusContextTray)) { _ in
            focusStore.focus(.contextTray)
            if selectedItemID == nil {
                selectedItemID = filteredItems.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporContextMoveUp)) { _ in
            guard focusStore.activeZone == .contextTray,
                  let current = selectedItemID else {
                selectedItemID = filteredItems.first?.id
                return
            }
            moveSelection(from: current, delta: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporContextMoveDown)) { _ in
            guard focusStore.activeZone == .contextTray,
                  let current = selectedItemID else {
                selectedItemID = filteredItems.first?.id
                return
            }
            moveSelection(from: current, delta: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporContextActivatePrimary)) { _ in
            guard focusStore.activeZone == .contextTray,
                  let item = selectedItem else { return }
            openDetail(item: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporContextActivateSecondary)) { _ in
            guard focusStore.activeZone == .contextTray,
                  let item = selectedItem else { return }
            insertItem(item)
        }
        .onChange(of: filteredItems.map(\.id)) { _, ids in
            guard let selectedItemID else {
                self.selectedItemID = ids.first
                return
            }

            if !ids.contains(selectedItemID) {
                self.selectedItemID = ids.first
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Context")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text("\(contextQueue.ready.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(height: 44)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
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
                Text("Ready")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(filteredItems.count)")
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 36)
        .background(.bar)
    }

    private func openDetail(item: ContextItem) {
        openWindow(value: ContextItemDetailPayload(itemID: item.id))
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

    private var selectedItem: ContextItem? {
        guard let selectedItemID else { return nil }
        return filteredItems.first(where: { $0.id == selectedItemID })
    }

    private func moveSelection(from itemID: UUID, delta: Int) {
        let ids = filteredItems.map(\.id)
        guard let currentIndex = ids.firstIndex(of: itemID) else {
            selectedItemID = ids.first
            return
        }

        let nextIndex = min(max(0, currentIndex + delta), ids.count - 1)
        selectedItemID = ids[nextIndex]
    }
}

struct ContextItemRow: View {
    let item: ContextItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(item.sourceTitle.isEmpty ? "Untitled" : item.sourceTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let summary = item.summary, !summary.abstract.isEmpty {
                    Text(summary.abstract)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else if let text = item.textContent, !text.isEmpty {
                    Text(String(text.prefix(100)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(item.kind.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                    if !item.sourceURL.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(hostFromURL(item.sourceURL))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
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
