import SwiftUI
import SwiftData

struct ContextTrayView: View {
    @Environment(ContextQueueService.self) private var contextQueue
    @Environment(MainWindowFocusStore.self) private var focusStore
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""
    @State private var showReadyOnly = false
    @State private var selectedItemID: UUID?

    @State private var browserExpanded = false
    @State private var agentSectionExpanded = false
    @State private var selectedDirectory: String?

    @State private var sessions: [OpenCodeSession] = []
    @State private var directories: [(directory: String, sessionCount: Int)] = []
    @State private var totalSessionCount: Int = 0
    @State private var isLoadingSessions = false
    @State private var sessionSearchText = ""
    @State private var sessionRefreshTask: Task<Void, Never>?
    @State private var lastSessionSignature: String?

    private var reader: OpenCodeReader { .shared }

    private var hasOpenCodeDB: Bool {
        reader.isAvailable
    }

    private var hasConversations: Bool {
        hasOpenCodeDB
    }

    private var filteredSessions: [OpenCodeSession] {
        var result = sessions

        if !sessionSearchText.isEmpty {
            let query = sessionSearchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.directory.lowercased().contains(query)
            }
        }

        return result
    }

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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    browserSection
                    if hasConversations {
                        agentSection
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()
            footerBar
        }
        .frame(width: 248)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { stopSessionPolling() }
        .onChange(of: preferences.agentSessionRefreshInterval) { _, _ in
            restartSessionPollingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard agentSectionExpanded else { return }
            refreshSessionsIfNeeded()
        }
    }

    // MARK: - Captured Section

    @ViewBuilder
    private var browserSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Browser",
                systemImage: "safari",
                badge: contextQueue.ready.count,
                isExpanded: browserExpanded,
                onTap: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        browserExpanded.toggle()
                    }
                }
            )
            .padding(.horizontal, 8)

            if browserExpanded {
                searchBar

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
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
                        .onChange(of: selectedItemID) { _, id in
                            guard focusStore.activeZone == .contextTray, let id else { return }
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
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

    // MARK: - Agent Sessions Section

    @ViewBuilder
    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    agentSectionExpanded.toggle()
                }
                if agentSectionExpanded {
                    if sessions.isEmpty && !isLoadingSessions {
                        loadSessionData(directory: selectedDirectory)
                    }
                    startSessionPolling()
                } else {
                    stopSessionPolling()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: agentSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("Sessions")
                        .font(.system(size: 12, weight: .semibold))

                    Spacer()

                    if agentSectionExpanded {
                        Button {
                            loadSessionData(directory: selectedDirectory, force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh sessions")
                    }

                    if totalSessionCount > 0 {
                        Text("\(totalSessionCount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            if agentSectionExpanded {
                if isLoadingSessions {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Loading sessions...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    sessionListView
                }
            }
        }
    }

    @ViewBuilder
    private var sessionListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionSearchField

            if directories.count > 1 {
                directoryFilterBar
                Divider()
            }

            if filteredSessions.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "terminal")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text(emptySessionsMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredSessions) { session in
                        Button {
                            openWindow(value: AgentSessionPayload(sourceID: session.id))
                        } label: {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title.isEmpty ? "Untitled session" : session.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        if session.messageCount > 0 {
                                            Text("\(session.messageCount) msgs")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        }

                                        Text(session.projectDisplayName)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary.opacity(0.7))
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        Text(session.timeUpdated, style: .relative)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary.opacity(0.6))
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptySessionsMessage: String {
        if !sessionSearchText.isEmpty { return "No matching sessions" }
        if selectedDirectory != nil { return "No sessions loaded for this project" }
        return "No sessions found"
    }

    private var sessionSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 10))
            TextField("Search sessions...", text: $sessionSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
            if !sessionSearchText.isEmpty {
                Button { sessionSearchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Shared Views

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 11))
            Text("Context")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(height: 44)
        .background(.bar)
    }

    private func sectionHeader(title: String, systemImage: String, badge: Int, isExpanded: Bool, onTap: (() -> Void)?) -> some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Text("\(badge)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var directoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    selectedDirectory = nil
                    loadSessionData(directory: nil, force: true)
                } label: {
                    Text("All")
                        .font(.system(size: 10))
                        .fontWeight(selectedDirectory == nil ? .semibold : .regular)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(selectedDirectory == nil ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                ForEach(directories, id: \.directory) { entry in
                    let lastComponent = (entry.directory as NSString).lastPathComponent
                    Button {
                        selectedDirectory = entry.directory
                        loadSessionData(directory: entry.directory, force: true)
                    } label: {
                        HStack(spacing: 2) {
                            Text(lastComponent)
                                .font(.system(size: 10))
                                .fontWeight(selectedDirectory == entry.directory ? .semibold : .regular)
                            Text("\(entry.sessionCount)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(selectedDirectory == entry.directory ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
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

    // MARK: - Helpers

    private func loadSessionData(directory: String? = nil, force: Bool = false) {
        guard !isLoadingSessions else { return }
        isLoadingSessions = true
        if force { lastSessionSignature = nil }

        Task.detached { [reader, directory] in
            let signature = reader.sessionListSignature(directory: directory)
            let fetchedSessions = reader.fetchSessions(limit: 100, directory: directory)
            let fetchedDirectories = reader.fetchDirectories()
            let fetchedTotal = reader.totalSessionCount()

            await MainActor.run {
                self.lastSessionSignature = signature
                self.sessions = fetchedSessions
                self.directories = fetchedDirectories
                self.totalSessionCount = fetchedTotal
                self.isLoadingSessions = false
            }
        }
    }

    private func startSessionPolling() {
        guard sessionRefreshTask == nil,
              let interval = preferences.agentSessionRefreshInterval.duration else { return }

        sessionRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                refreshSessionsIfNeeded()
            }
        }
    }

    private func stopSessionPolling() {
        sessionRefreshTask?.cancel()
        sessionRefreshTask = nil
    }

    private func restartSessionPollingIfNeeded() {
        stopSessionPolling()
        guard agentSectionExpanded else { return }
        startSessionPolling()
    }

    private func refreshSessionsIfNeeded() {
        guard agentSectionExpanded, !isLoadingSessions else { return }
        let directory = selectedDirectory
        Task.detached { [reader, directory, lastSessionSignature] in
            let signature = reader.sessionListSignature(directory: directory)
            guard signature != lastSessionSignature else { return }
            await MainActor.run {
                loadSessionData(directory: directory)
            }
        }
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
