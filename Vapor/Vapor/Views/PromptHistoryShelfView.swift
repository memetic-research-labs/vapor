import SwiftData
import SwiftUI

struct PromptHistoryShelfView: View {
    @Environment(MainWindowFocusStore.self) private var focusStore

    @Query(sort: \PromptRecord.modifiedAt, order: .reverse)
    private var allRecords: [PromptRecord]

    let onRestore: (PromptRecord) -> Void

    private let horizontalInset: CGFloat = 10
    private let headerHeight: CGFloat = 44

    @State private var isExpanded = true
    @State private var focusedRecordID: UUID?

    private var records: [PromptRecord] {
        Array(allRecords.prefix(16))
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            headerView

            if isExpanded {
                Divider()
                contentView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .vaporFocusPromptHistory)) { _ in
            guard !records.isEmpty else { return }
            isExpanded = true
            focusStore.focus(.promptHistory)
            focusedRecordID = records.first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporPromptHistoryMoveLeft)) { _ in
            guard focusStore.activeZone == .promptHistory, let focusedRecordID else { return }
            moveFocus(by: -1, currentRecordID: focusedRecordID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporPromptHistoryMoveRight)) { _ in
            guard focusStore.activeZone == .promptHistory, let focusedRecordID else { return }
            moveFocus(by: 1, currentRecordID: focusedRecordID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaporPromptHistoryRestoreSelected)) { _ in
            guard focusStore.activeZone == .promptHistory, let selectedRecord else { return }
            onRestore(selectedRecord)
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Prompt History")
                        .font(.system(size: 11, weight: .semibold))
                    if !records.isEmpty {
                        Text("\(records.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }
            }
            .buttonStyle(.plain)

            Text(records.isEmpty ? "Used prompts appear here for quick restore." : headerHintText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 8)
        .frame(height: headerHeight)
        .background(.bar)
    }

    @ViewBuilder
    private var contentView: some View {
        if records.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompts you actually use are staged here for quick restore.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Double-click to restore, or select a card and press Return.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 8)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(records) { record in
                            PromptHistoryShelfCard(
                                record: record,
                                isFocused: focusedRecordID == record.id,
                                onSelect: {
                                    focusStore.focus(.promptHistory)
                                    focusedRecordID = record.id
                                },
                                onRestore: {
                                    onRestore(record)
                                }
                            )
                            .id(record.id)
                        }
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    if focusedRecordID == nil {
                        focusedRecordID = records.first?.id
                    }
                }
                .onChange(of: records.map(\.id)) { _, ids in
                    guard let focusedRecordID else {
                        self.focusedRecordID = ids.first
                        return
                    }

                    if !ids.contains(focusedRecordID) {
                        self.focusedRecordID = ids.first
                    }
                }
                .onChange(of: focusedRecordID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var selectedRecord: PromptRecord? {
        guard let focusedRecordID else { return nil }
        return records.first(where: { $0.id == focusedRecordID })
    }

    private func moveFocus(by delta: Int, currentRecordID: UUID) {
        let ids = records.map(\.id)
        guard let currentIndex = ids.firstIndex(of: currentRecordID) else {
            focusedRecordID = ids.first
            return
        }

        let nextIndex = min(max(0, currentIndex + delta), ids.count - 1)
        focusedRecordID = ids[nextIndex]
    }

    private var headerHintText: String {
        if focusStore.activeZone == .promptHistory {
            return "Return restores · double-click also restores"
        }
        return "Recently used prompts stay here for quick reuse."
    }
}

private struct PromptHistoryShelfCard: View {
    let record: PromptRecord
    let isFocused: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.originalText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text(String(format: "%.2f", record.compressionRatio))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)

                Text("\(record.useCount)x")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Text(formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder((isFocused ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.08)), lineWidth: isFocused ? 1.5 : 1)
        )
        .editorGlow(isFocused: isFocused)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 2) {
            onSelect()
            onRestore()
        }
        .onTapGesture {
            onSelect()
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: record.modifiedAt)
    }
}
