import SwiftUI
import SwiftData

struct PromptHistoryView: View {
    @Query(sort: \PromptRecord.modifiedAt, order: .reverse)
    private var allRecords: [PromptRecord]

    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var historyStore = HistoryStore.shared
    @State private var historyService = PromptHistoryService()

    // We need the history service for delete/undo/favorite operations.
    // Since this is a separate window without access to ContentView's service,
    // we use the modelContext directly.
    @Environment(\.modelContext) private var modelContext

    private var filteredRecords: [PromptRecord] {
        var records = allRecords

        if showFavoritesOnly {
            records = records.filter { $0.isFavorite }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            records = records.filter {
                $0.originalText.lowercased().contains(query) ||
                $0.compressedText.lowercased().contains(query)
            }
        }

        return records
    }

    private var groupedRecords: [(String, [PromptRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRecords) { record -> String in
            if calendar.isDateInToday(record.modifiedAt) {
                return "Today"
            } else if calendar.isDateInYesterday(record.modifiedAt) {
                return "Yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy"
                return formatter.string(from: record.modifiedAt)
            }
        }

        // Sort groups: Today first, then Yesterday, then by date descending
        let sortOrder = ["Today", "Yesterday"]
        return grouped.sorted { a, b in
            let aIdx = sortOrder.firstIndex(of: a.key)
            let bIdx = sortOrder.firstIndex(of: b.key)
            if let aIdx, let bIdx { return aIdx < bIdx }
            if aIdx != nil { return true }
            if bIdx != nil { return false }
            // Both are date strings — sort by first record's date descending
            let aDate = a.value.first?.modifiedAt ?? .distantPast
            let bDate = b.value.first?.modifiedAt ?? .distantPast
            return aDate > bDate
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search prompts…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }, label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    })
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Records list
            if filteredRecords.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(groupedRecords, id: \.0) { group, records in
                            // Section header
                            Text(group)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 2)

                            ForEach(records) { record in
                                PromptHistoryCardView(
                                    record: record,
                                    onRestore: { historyStore.requestRestore($0) },
                                    onToggleFavorite: { toggleFavorite($0) },
                                    onDelete: { deleteRecord($0) }
                                )
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Undo toast
            if historyStore.showUndoToast {
                Divider()
                undoBar
            }
        }
        .frame(minWidth: 360, minHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            historyService.setModelContext(modelContext)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Prompt History")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Button(action: { showFavoritesOnly.toggle() }, label: {
                Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(showFavoritesOnly ? .yellow : .secondary)
            })
            .buttonStyle(.plain)
            .help(showFavoritesOnly ? "Show all" : "Show favorites only")

            Text("\(filteredRecords.count) prompts")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            if showFavoritesOnly {
                Text("No favorite prompts yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Star a prompt to see it here")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            } else if !searchText.isEmpty {
                Text("No prompts matching \"\(searchText)\"")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                Text("No prompts yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Compress a prompt to see it here")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Undo Bar

    private var undoBar: some View {
        HStack {
            Text(historyStore.undoToastMessage)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Button("Undo") {
                undoDelete()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func toggleFavorite(_ record: PromptRecord) {
        try? historyService.toggleFavorite(record)
    }

    private func deleteRecord(_ record: PromptRecord) {
        historyStore.lastDeletedRecord = record
        historyStore.undoToastMessage = "Deleted — tap Undo to restore"
        withAnimation(.easeInOut(duration: 0.2)) {
            historyStore.showUndoToast = true
        }

        try? historyService.delete(record)

        Task {
            try? await Task.sleep(for: .seconds(4))
            if historyStore.showUndoToast {
                withAnimation(.easeInOut(duration: 0.2)) {
                    historyStore.showUndoToast = false
                }
                historyStore.lastDeletedRecord = nil
            }
        }
    }

    private func undoDelete() {
        guard let record = historyStore.lastDeletedRecord else { return }
        try? historyService.save(record)
        historyStore.lastDeletedRecord = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            historyStore.showUndoToast = false
        }
    }
}
