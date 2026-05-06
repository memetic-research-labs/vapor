import SwiftUI

struct OpenCodeSessionWindowView: View {
    let sourceID: String

    @Environment(VectorizationService.self) private var vectorizationService

    @State private var session: OpenCodeSession?
    @State private var messages: [OpenCodeMessage] = []
    @State private var partsCache: [String: [OpenCodePart]] = [:]
    @State private var loadingParts: Set<String> = []
    @State private var expandedToolCalls: Set<String> = []
    @State private var expandedReasoning: Set<String> = []
    @State private var copiedMessageID: String?
    @State private var displayedTurnCount: Int = 30
    @State private var isLoadingMore: Bool = false
    @State private var totalCost: Double?
    @State private var isLoadingSession: Bool = true
    @State private var indexerState: OpenCodeSessionIndexer.IndexState = .idle
    @State private var importStatus: OpenCodeSessionIndexer.ImportStatus = .notImported
    @State private var isSearchPresented = false
    @State private var searchQuery = ""
    @State private var searchResults: [TurnSearchResult] = []
    @State private var isSearching = false
    @State private var highlightedTurnID: String?
    @State private var highlightedSearchQuery = ""
    @State private var isHighlightPulsing = false
    @State private var isIndexDetailsPresented = false
    @FocusState private var isSearchFieldFocused: Bool

    private struct ToolCallInfo {
        let name: String
        let status: String
        let input: String?
        let output: String?
        let title: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .top) {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(displayedTurns) { message in
                                    turnCard(message)
                                        .id(message.id)
                                }

                                if hasMoreTurns {
                                    loadMoreSentinel
                                }
                            }
                            .padding(16)
                        }

                        if isSearchPresented {
                            searchOverlay(proxy: proxy)
                        }
                    }
                }
            }
        }
        .onAppear {
            let indexer = OpenCodeSessionIndexer.shared
            indexerState = indexer.state
            importStatus = indexer.status(for: sourceID)
            loadSession()
            observeIndexerState()
        }
    }

    private var displayedTurns: [OpenCodeMessage] {
        Array(messages.prefix(displayedTurnCount))
    }

    private var hasMoreTurns: Bool {
        displayedTurnCount < messages.count
    }

    // MARK: - Load Data

    private func loadSession() {
        isLoadingSession = true
        Task.detached { [sourceID] in
            let reader = OpenCodeReader.shared
            let session = reader.fetchSession(sessionID: sourceID)
            let fetchedMessages = reader.fetchAllMessages(sessionID: sourceID)
            let cost = fetchedMessages.compactMap(\.cost).reduce(0, +)

            await MainActor.run {
                self.session = session
                self.messages = fetchedMessages
                self.totalCost = cost > 0 ? cost : nil
                self.isLoadingSession = false
                self.preloadTextParts()
                self.checkImportStatus()
            }
        }
    }

    private func checkImportStatus() {
        guard let session else { return }
        let sessionTimeUpdated = session.timeUpdated
        Task { [sourceID] in
            let indexer = OpenCodeSessionIndexer.shared
            let status = await indexer.checkImportState(
                sourceID: sourceID,
                sessionTimeUpdated: sessionTimeUpdated,
                vectorizationService: vectorizationService
            )
            await MainActor.run {
                importStatus = status
            }
        }
    }

    private func observeIndexerState() {
        let indexer = OpenCodeSessionIndexer.shared
        withObservationTracking {
            _ = indexer.state
            _ = indexer.status(for: sourceID)
        } onChange: {
            Task { @MainActor in
                indexerState = indexer.state
                importStatus = indexer.status(for: sourceID)
                observeIndexerState()
            }
        }
    }

    private func preloadTextParts() {
        for message in messages {
            let messageID = message.id
            guard partsCache[messageID] == nil, !loadingParts.contains(messageID) else { continue }
            loadingParts.insert(messageID)
            Task.detached { [sourceID] in
                let reader = OpenCodeReader.shared
                let parts = reader.fetchParts(messageID: messageID)
                let textParts = parts.filter { if case .text = $0.kind { true } else { false } }
                await MainActor.run {
                    partsCache[messageID] = textParts
                    loadingParts.remove(messageID)
                }
            }
        }
    }

    private func loadFullParts(for messageID: String) {
        guard !loadingParts.contains(messageID) else { return }
        loadingParts.insert(messageID)
        Task.detached { [sourceID] in
            let reader = OpenCodeReader.shared
            let parts = reader.fetchAllParts(sessionID: sourceID).filter { $0.messageID == messageID }
            await MainActor.run {
                partsCache[messageID] = parts
                loadingParts.remove(messageID)
            }
        }
    }

    // MARK: - Load More

    private var loadMoreSentinel: some View {
        Group {
            if isLoadingMore {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Loading more...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        loadMore()
                    }
            }
        }
    }

    private func loadMore() {
        guard hasMoreTurns, !isLoadingMore else { return }
        isLoadingMore = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            displayedTurnCount += 30
            isLoadingMore = false
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let session {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.title.isEmpty ? "Untitled session" : session.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            Label {
                                Text(session.projectDisplayName)
                            } icon: {
                                Image(systemName: "folder")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Label {
                                Text("\(messages.count) turns")
                            } icon: {
                                Image(systemName: "text.bubble")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let version = session.version {
                                Text("v\(version)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }

                            Text(session.timeUpdated, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let cost = totalCost {
                                Text("$\(String(format: "%.2f", cost))")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.orange)
                                    .monospacedDigit()
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        searchToggleButton
                        importAndIndexButton
                        indexDetailsButton
                    }
                }
            }
        } else {
            HStack {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Loading session...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var searchToggleButton: some View {
        Button {
            presentSearchOverlay()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(isSearchPresented ? Color.accentColor : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSearchPresented ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: .command)
        .help("Search turns")
    }

    @ViewBuilder
    private var importAndIndexButton: some View {
        let isIndexerActive: Bool = {
            switch indexerState {
            case .importing, .indexing:
                true
            case .idle, .done, .error:
                false
            }
        }()
        let isIndexerForThisSession: Bool = {
            switch indexerState {
            case .importing(let sid, _, _), .indexing(let sid, _, _):
                return sid == sourceID
            default:
                return false
            }
        }()

        if isIndexerActive && isIndexerForThisSession {
            switch indexerState {
            case .idle:
                EmptyView()
            case .importing(_, let current, let total):
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .controlSize(.mini)
                    Text("Importing \(current)/\(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.06))
                .clipShape(Capsule())
            case .indexing(_, let current, let total):
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .controlSize(.mini)
                    Text(total > 0 ? "Updating search \(current)/\(total)" : "Updating search...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.06))
                .clipShape(Capsule())
            case .done(_, let turnCount, let chunkCount):
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Search ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help("\(turnCount) turns, \(chunkCount) chunks indexed")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.06))
                .clipShape(Capsule())
            case .error(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.06))
                .clipShape(Capsule())
            }
        } else {
            switch importStatus {
            case .notImported:
                Button {
                    let indexer = OpenCodeSessionIndexer.shared
                    indexer.importAndIndex(sourceID: sourceID, vectorizationService: vectorizationService)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption)
                        Text("Import & Index")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            case .ready(let turnCount, let chunkCount, let vectorCount):
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Search ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help("\(turnCount) turns, \(chunkCount) chunks, \(vectorCount) vectors")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.06))
                .clipShape(Capsule())
            case .dirty(let turnCount, let chunkCount, let vectorCount):
                Button {
                    let indexer = OpenCodeSessionIndexer.shared
                    indexer.importAndIndex(sourceID: sourceID, vectorizationService: vectorizationService)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                        Text("Update Search")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(turnCount) turns, \(chunkCount) chunks, \(vectorCount) vectors — session changed")
            case .needsRepair(let turnCount, let chunkCount, let vectorCount):
                Button {
                    let indexer = OpenCodeSessionIndexer.shared
                    indexer.repairSearchIndex(sourceID: sourceID, vectorizationService: vectorizationService)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption)
                        Text("Repair Search")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Search index incomplete: \(turnCount) turns, \(chunkCount) chunks, \(vectorCount) vectors")
            }
        }
    }

    @ViewBuilder
    private var indexDetailsButton: some View {
        Button {
            isIndexDetailsPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isIndexDetailsPresented, arrowEdge: .bottom) {
            searchIndexDetailsPopover
        }
        .help("Search index details")
    }

    private var searchIndexDetailsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search Index")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Status").foregroundStyle(.secondary)
                    Text(searchIndexStatusLabel)
                }
                if let counts = searchIndexCounts {
                    GridRow {
                        Text("Turns").foregroundStyle(.secondary)
                        Text("\(counts.turns)")
                    }
                    GridRow {
                        Text("Chunks").foregroundStyle(.secondary)
                        Text("\(counts.chunks)")
                    }
                    GridRow {
                        Text("Vectors").foregroundStyle(.secondary)
                        Text("\(counts.vectors)")
                    }
                }
                GridRow {
                    Text("Model").foregroundStyle(.secondary)
                    Text(vectorizationService.providerDisplayName)
                }
            }
            .font(.caption)

        }
        .padding(14)
        .frame(width: 260)
    }

    private var searchIndexStatusLabel: String {
        switch importStatus {
        case .notImported: "Not imported"
        case .ready: "Search ready"
        case .dirty: "Needs update"
        case .needsRepair: "Needs repair"
        }
    }

    private var searchIndexCounts: (turns: Int, chunks: Int, vectors: Int)? {
        switch importStatus {
        case .notImported:
            nil
        case .ready(let turnCount, let chunkCount, let vectorCount),
             .dirty(let turnCount, let chunkCount, let vectorCount),
             .needsRepair(let turnCount, let chunkCount, let vectorCount):
            (turnCount, chunkCount, vectorCount)
        }
    }

    // MARK: - Turn Card

    @ViewBuilder
    private func turnCard(_ message: OpenCodeMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            turnHeader(message)
            turnContent(message)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(highlightedTurnID == message.id ? Color.accentColor.opacity(isHighlightPulsing ? 0.95 : 0.25) : Color.clear, lineWidth: 2.5)
                .scaleEffect(highlightedTurnID == message.id && isHighlightPulsing ? 1.012 : 1.0)
                .shadow(color: highlightedTurnID == message.id ? Color.accentColor.opacity(isHighlightPulsing ? 0.42 : 0.08) : Color.clear, radius: 8)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isHighlightPulsing)
        )
    }

    @ViewBuilder
    private func turnHeader(_ message: OpenCodeMessage) -> some View {
        HStack(spacing: 8) {
            roleBadge(message.role)

            Text(message.timeCreated, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            if let agent = message.agent, message.role == "assistant" {
                Text(agent)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

            if message.role == "assistant" {
                if let modelID = message.modelID {
                    Text(modelID)
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let cost = message.cost, cost > 0 {
                Text("$\(String(format: "%.4f", cost))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }

            if let tokens = message.tokens, tokens.total > 0 {
                Text("\(tokens.total) tok")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .monospacedDigit()
            }

            Button {
                copyTurnText(message)
            } label: {
                Image(systemName: copiedMessageID == message.id ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func roleBadge(_ role: String) -> some View {
        let (text, color) = roleBadgeInfo(role)
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func roleBadgeInfo(_ role: String) -> (String, Color) {
        switch role {
        case "user": return ("You", .blue)
        case "assistant": return ("AI", .green)
        case "system": return ("System", .orange)
        default: return (role.capitalized, .secondary)
        }
    }

    // MARK: - Turn Content

    @ViewBuilder
    private func turnContent(_ message: OpenCodeMessage) -> some View {
        let parts = partsCache[message.id] ?? []
        let isLoading = loadingParts.contains(message.id)

        if isLoading && parts.isEmpty {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 10, height: 10)
                Text("loading...")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .italic()
            }
        } else if parts.isEmpty {
            Button {
                loadFullParts(for: message.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("show content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            ForEach(parts) { part in
                contentPartView(part)
            }
            let textOnly = parts.allSatisfy { if case .text = $0.kind { true } else { false } }
            if textOnly {
                Button {
                    loadFullParts(for: message.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("show tools & details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Part Views

    @ViewBuilder
    private func contentPartView(_ part: OpenCodePart) -> some View {
        switch part.kind {
        case .text(let text):
            if !text.isEmpty {
                Text(part.messageID == highlightedTurnID ? highlightedText(text, query: highlightedSearchQuery) : AttributedString(text))
                    .font(.body)
                    .textSelection(.enabled)
            }
        case .tool(let name, let callID, let status, let input, let output, let title):
            toolCallView(name: name, status: status, input: input, output: output, title: title, partID: part.id)
        case .reasoning(let text):
            reasoningView(text: text, partID: part.id)
        case .stepStart, .stepFinish, .compaction, .unknown:
            EmptyView()
        case .patch(_, let files):
            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: "doc.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(files, id: \.self) { file in
                        Text((file as NSString).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
            }
        case .file(_, let filename, _):
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(filename ?? "attachment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tool Call

    @ViewBuilder
    private func toolCallView(name: String, status: String, input: String?, output: String?, title: String?, partID: String) -> some View {
        let isExpanded = expandedToolCalls.contains(partID)
        let displayTitle = title ?? name

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedToolCalls.remove(partID)
                    } else {
                        expandedToolCalls.insert(partID)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)

                    Text(displayTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    statusIndicator(status)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let input {
                        toolOutputSection(label: "Input", content: input)
                    }
                    if let output, !output.isEmpty {
                        toolOutputSection(label: "Output", content: output)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func statusIndicator(_ status: String) -> some View {
        let color: Color = switch status {
        case "completed": .green
        case "running": .blue
        case "error": .red
        default: Color.secondary.opacity(0.5)
        }
        let label: String = switch status {
        case "completed": "done"
        case "running": "running"
        case "error": "error"
        default: status
        }
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
        Text(label)
            .font(.caption2)
            .foregroundStyle(.quaternary)
    }

    @ViewBuilder
    private func toolOutputSection(label: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Reasoning

    @ViewBuilder
    private func reasoningView(text: String, partID: String) -> some View {
        let isExpanded = expandedReasoning.contains(partID)

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedReasoning.remove(partID)
                } else {
                    expandedReasoning.insert(partID)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "eye.fill" : "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                if isExpanded {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("reasoning")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                        .italic()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func copyTurnText(_ message: OpenCodeMessage) {
        let parts = partsCache[message.id] ?? []
        let textParts: [String] = parts.compactMap {
            if case .text(let text) = $0.kind { return text }
            return nil
        }
        let combined = textParts.joined(separator: "\n")
        if !combined.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(combined, forType: .string)
        }
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMessageID == message.id {
                copiedMessageID = nil
            }
        }
    }
}

// MARK: - Search Types

struct TurnSearchResult: Identifiable, Sendable {
    let id: String
    let turnSourceID: String
    let sessionID: String
    let chunkIndex: Int
    let chunkText: String
    let distance: Double
}

// MARK: - Search Views

extension OpenCodeSessionWindowView {

    @ViewBuilder
    private func searchOverlay(proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { dismissSearchOverlay() }

            VStack(spacing: 0) {
                searchOverlayHeader
                Divider()
                searchOverlayContent(proxy: proxy)
            }
            .frame(maxWidth: 560, maxHeight: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            .padding(.top, 18)
            .padding(.horizontal, 24)
            .onAppear {
                searchQuery = ""
                searchResults = []
                DispatchQueue.main.async { isSearchFieldFocused = true }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var searchOverlayHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            TextField("Search this session...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFieldFocused)
                .disabled(!canSearchCurrentSession)
                .onSubmit { performSearch() }
                .onChange(of: searchQuery) { _, _ in
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        await MainActor.run { performSearch() }
                    }
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button { dismissSearchOverlay() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func searchOverlayContent(proxy: ScrollViewProxy) -> some View {
        if let activeState = activeIndexStateForCurrentSession, !hasUsableSearchIndex {
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.75)
                Text(activeIndexTitle(for: activeState))
                    .font(.headline)
                Text(activeIndexMessage(for: activeState))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        } else if !canSearchCurrentSession {
            VStack(spacing: 10) {
                Image(systemName: searchUnavailableIcon)
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(searchUnavailableTitle)
                    .font(.headline)
                Text(searchUnavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(searchUnavailableActionHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        } else if isSearching {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.65)
                Text("Searching indexed turns...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
        } else if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 8) {
                Text("Search this session")
                    .font(.headline)
                Text("Type a phrase, topic, or implementation detail. Results come from indexed turns only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        } else if searchResults.isEmpty {
            VStack(spacing: 8) {
                Text("No results")
                    .font(.headline)
                Text("This session may not be indexed yet, or no indexed turn matched that query.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    ForEach(searchResults) { result in
                        searchResultButton(result, proxy: proxy)
                    }
                }
                .padding(12)
            }
        }
    }

    private func performSearch() {
        guard canSearchCurrentSession else { return }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { searchResults = []; return }
        isSearching = true

        Task { [query, sourceID] in
            let rows = await vectorizationService.searchTurnChunks(matching: query, sessionID: sourceID, limit: 20)
            let results: [TurnSearchResult] = rows.compactMap { row in
                guard let id = row["embedding_id"] as? String,
                      let text = row["chunk_text"] as? String,
                      let turnSourceID = row["turn_source_id"] as? String,
                      let sessionID = row["session_id"] as? String,
                      let chunkIndex = row["chunk_index"] as? Int,
                      let distance = row["distance"] as? Double else { return nil }
                return TurnSearchResult(
                    id: id,
                    turnSourceID: turnSourceID,
                    sessionID: sessionID,
                    chunkIndex: chunkIndex,
                    chunkText: text,
                    distance: distance
                )
            }
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }

    @ViewBuilder
    private func searchResultButton(_ result: TurnSearchResult, proxy: ScrollViewProxy) -> some View {
        Button {
            selectSearchResult(result, proxy: proxy)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: 6, height: 6)
                    Text(result.turnSourceID.suffix(8))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(matchStrengthLabel(for: result.distance))
                        .font(.caption2)
                        .foregroundStyle(matchStrengthColor(for: result.distance))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(matchStrengthColor(for: result.distance).opacity(0.12)))
                    Text("Distance \(String(format: "%.3f", result.distance))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .help("Cosine distance. Lower is better.")
                }

                Text(highlightedText(String(result.chunkText.prefix(1_200)), query: searchQuery))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func presentSearchOverlay() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isSearchPresented = true
        }
        DispatchQueue.main.async { isSearchFieldFocused = true }
    }

    private func dismissSearchOverlay() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isSearchPresented = false
        }
        isSearchFieldFocused = false
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    private func selectSearchResult(_ result: TurnSearchResult, proxy: ScrollViewProxy) {
        if let index = messages.firstIndex(where: { $0.id == result.turnSourceID }) {
            displayedTurnCount = max(displayedTurnCount, index + 1)
        }

        highlightedTurnID = result.turnSourceID
        highlightedSearchQuery = searchQuery
        isHighlightPulsing = false
        dismissSearchOverlay()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(result.turnSourceID, anchor: .center)
            }
            isHighlightPulsing = true
        }

        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if highlightedTurnID == result.turnSourceID {
                highlightedTurnID = nil
                highlightedSearchQuery = ""
                isHighlightPulsing = false
            }
        }
    }

    private func matchStrengthLabel(for distance: Double) -> String {
        if distance < 0.30 { return "Strong" }
        if distance < 0.60 { return "Related" }
        return "Weak"
    }

    private func matchStrengthColor(for distance: Double) -> Color {
        if distance < 0.30 { return .green }
        if distance < 0.60 { return .orange }
        return .secondary
    }

    private func highlightedText(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let terms = highlightTerms(from: query)
        guard !terms.isEmpty else { return attributed }

        let lowercasedText = text.lowercased()
        for term in terms {
            var searchStart = lowercasedText.startIndex
            while searchStart < lowercasedText.endIndex,
                  let range = lowercasedText.range(of: term, range: searchStart..<lowercasedText.endIndex) {
                let startOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)
                let endOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound)
                let start = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
                let end = attributed.index(attributed.startIndex, offsetByCharacters: endOffset)
                attributed[start..<end].backgroundColor = Color.accentColor.opacity(0.22)
                attributed[start..<end].foregroundColor = .primary
                searchStart = range.upperBound
            }
        }
        return attributed
    }

    private func highlightTerms(from query: String) -> [String] {
        let cleaned = query
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }
        return Array(Set(cleaned)).sorted { $0.count > $1.count }
    }

    private var canSearchCurrentSession: Bool {
        hasUsableSearchIndex
    }

    private var hasUsableSearchIndex: Bool {
        switch importStatus {
        case .ready, .dirty:
            return true
        case .notImported, .needsRepair:
            return false
        }
    }

    private var activeIndexStateForCurrentSession: OpenCodeSessionIndexer.IndexState? {
        switch indexerState {
        case .importing(let sid, _, _) where sid == sourceID:
            return indexerState
        case .indexing(let sid, _, _) where sid == sourceID:
            return indexerState
        default:
            return nil
        }
    }

    private func activeIndexTitle(for state: OpenCodeSessionIndexer.IndexState) -> String {
        switch state {
        case .importing:
            "Importing session"
        case .indexing:
            "Updating search index"
        case .idle, .done, .error:
            "Updating"
        }
    }

    private func activeIndexMessage(for state: OpenCodeSessionIndexer.IndexState) -> String {
        switch state {
        case .importing(_, let current, let total):
            total > 0 ? "Imported \(current) of \(total) turns." : "Preparing imported content."
        case .indexing(_, let current, let total):
            total > 0 ? "Indexed \(current) of \(total) turns." : "Preparing searchable vectors."
        case .idle, .done, .error:
            ""
        }
    }

    private var searchUnavailableIcon: String {
        switch importStatus {
        case .notImported: "square.and.arrow.down"
        case .needsRepair: "wrench.and.screwdriver"
        case .ready, .dirty: "magnifyingglass"
        }
    }

    private var searchUnavailableTitle: String {
        switch importStatus {
        case .notImported: "Import this session to search"
        case .needsRepair: "Search index needs repair"
        case .ready, .dirty: "Search this session"
        }
    }

    private var searchUnavailableMessage: String {
        switch importStatus {
        case .notImported:
            "This session has not been added to local search yet."
        case .needsRepair(let turnCount, let chunkCount, let vectorCount):
            "Imported content exists, but searchable vectors are missing or incomplete. Turns: \(turnCount), chunks: \(chunkCount), vectors: \(vectorCount)."
        case .ready, .dirty:
            ""
        }
    }

    private var searchUnavailableActionHint: String {
        switch importStatus {
        case .notImported:
            "Use Import & Index in the window header."
        case .needsRepair:
            "Use Repair Search in the window header."
        case .ready, .dirty:
            ""
        }
    }
}
