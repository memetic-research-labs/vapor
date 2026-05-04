import SwiftUI
import SwiftData

struct SessionReaderView: View {
    let session: AISession
    @Environment(\.modelContext) private var modelContext
    @State private var copiedTurnID: UUID?
    @State private var showingExportPreview = false
    @State private var isExporting = false
    @State private var exportCompleted = false

    private let cardBackground = Color(nsColor: .controlBackgroundColor)

    private var sortedTurns: [AITurn] {
        session.turns.sorted { $0.turnIndex < $1.turnIndex }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                Divider()

                if let abstract = session.summaryAbstract, !abstract.isEmpty {
                    summarySection(abstract)
                }

                turnsSection
            }
            .padding()
        }
        .sheet(isPresented: $showingExportPreview, onDismiss: {
            if exportCompleted { exportCompleted = false }
        }) {
            ExportPreviewSheet(session: session, isPresented: $showingExportPreview, isExporting: $isExporting, exportCompleted: $exportCompleted)
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title)
                    .font(.title2.bold())
                Spacer()
                Button {
                    showingExportPreview = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                toolBadge(session.tool)
            }

            HStack(spacing: 16) {
                Label("\(session.totalTurns) turns", systemImage: "text.bubble")
                if let branch = session.branchName {
                    Label(branch, systemImage: "arrow.triangle.branch")
                }
                if let prNumber = session.prNumber {
                    Label("PR #\(prNumber)", systemImage: "number")
                }
                Label(formattedDate(session.startedAt), systemImage: "clock")
                if let ended = session.endedAt {
                    Text(durationString(from: session.startedAt, to: ended))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !session.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(session.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
            }
        }
    }

    private func summarySection(_ abstract: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Summary", systemImage: "doc.text")
                .font(.subheadline.bold())
            Text(abstract)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var turnsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sortedTurns) { turn in
                turnCard(turn)
            }
        }
    }

    private func turnCard(_ turn: AITurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                roleBadge(turn.role)
                if let model = turn.modelID {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(formattedTimestamp(turn.capturedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Menu {
                    Button("Copy text") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(turn.content, forType: .string)
                        copiedTurnID = turn.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedTurnID == turn.id { copiedTurnID = nil }
                        }
                    }
                    Button(turn.isRedacted ? "Unmark private" : "Mark private") {
                        turn.isRedacted.toggle()
                        try? modelContext.save()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            Text(turn.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if turn.attachedImageIDs.count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(turn.attachedImageIDs, id: \.self) { imageID in
                            if let uuid = UUID(uuidString: imageID) {
                                AttachedImageThumbnail(imageID: uuid)
                            }
                        }
                    }
                }
            }

            if turn.attachedURLs.count > 0 {
                let firstURL = turn.attachedURLs[0]
                if let components = URLComponents(string: firstURL) {
                    HStack(spacing: 4) {
                        Label(components.host ?? firstURL, systemImage: "link")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }
            }

            if copiedTurnID == turn.id {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Copied")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func roleBadge(_ role: String) -> some View {
        let config = switch role.lowercased() {
        case "user": (color: Color.blue, icon: "person")
        case "assistant": (color: Color.green, icon: "sparkles")
        case "system": (color: Color.orange, icon: "gearshape")
        case "tool": (color: Color.purple, icon: "wrench")
        default: (color: Color.secondary, icon: "circle")
        }
        return Label(role.capitalized, systemImage: config.icon)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(config.color.opacity(0.15)))
            .foregroundStyle(config.color)
    }

    private func toolBadge(_ tool: String) -> some View {
        let icon = switch tool.lowercased() {
        case let val where val.contains("opencode"): "terminal"
        case let val where val.contains("cursor"): "cursorarrow"
        case let val where val.contains("claude"): "bubble.left"
        case let val where val.contains("copilot"): "sparkles"
        default: "cpu"
        }
        return Label(tool, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy HH:mm"
        return formatter.string(from: date)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func durationString(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 60 {
            let hours = minutes / 60
            return "\(hours)h \(minutes % 60)m"
        }
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}

struct AttachedImageThumbnail: View {
    let imageID: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let descriptor = FetchDescriptor<ImageAsset>(predicate: #Predicate { $0.id == imageID })
        guard let asset = try? modelContext.fetch(descriptor).first else { return }
        let blobURL = BlobStore.shared.fileURL(relativePath: asset.blobPath)
        guard let data = try? Data(contentsOf: blobURL), let image = NSImage(data: data) else { return }
        self.thumbnail = image
    }
}
