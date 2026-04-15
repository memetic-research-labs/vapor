import SwiftUI
import SwiftData

struct ContextItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let itemID: UUID

    @State private var item: ContextItem?
    @State private var showCopyConfirmation = false

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection(item: item)

                        Divider()

                        sourceSection(item: item)

                        if item.citation != nil {
                            Divider()
                            citationSection(item: item)
                        }

                        if !item.entities.isEmpty {
                            Divider()
                            entitiesSection(item: item)
                        }

                        if !item.tags.isEmpty {
                            Divider()
                            tagsSection(item: item)
                        }

                        Divider()

                        contentSection(item: item)

                        Divider()

                        actionButtons(item: item)
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Item not found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            fetchItem()
        }
        .overlay(alignment: .top) {
            if showCopyConfirmation {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied to clipboard")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
                .padding(.top, 40)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopyConfirmation)
    }

    private func fetchItem() {
        let descriptor = FetchDescriptor<ContextItem>(predicate: #Predicate { $0.id == itemID })
        if let results = try? modelContext.fetch(descriptor), let found = results.first {
            item = found
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(item: ContextItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 24))
                .foregroundColor(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.sourceTitle.isEmpty ? "Untitled" : item.sourceTitle)
                    .font(.system(size: 16, weight: .semibold))

                HStack(spacing: 8) {
                    Text(item.kind.displayName)
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundColor(.accentColor)

                    statusBadge(item: item)

                    Text(formattedDate(item.capturedAt))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if let text = item.textContent {
                        Text("\(text.count) chars")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Source")

            if !item.sourceURL.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let url = URL(string: item.sourceURL) {
                        Link(item.sourceURL, destination: url)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(item.sourceURL)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No source URL")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func citationSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionHeader("Citation")
                Spacer()
                Button {
                    if let rendered = item.citation?.rendered {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(rendered, forType: .string)
                        flashCopyConfirmation()
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy citation")
            }

            if let citation = item.citation {
                Text(citation.rendered)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func entitiesSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Entities (\(item.entities.count))")

            FlowLayout(spacing: 6) {
                ForEach(groupedEntities(item.entities)) { group in
                    HStack(spacing: 3) {
                        Image(systemName: group.kind.systemImage)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(group.text)
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
                    .help("\(group.kind.displayName) · \(Int(group.confidence * 100))%")
                }
            }
        }
    }

    @ViewBuilder
    private func tagsSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Tags (\(item.tags.count))")

            FlowLayout(spacing: 6) {
                ForEach(item.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                        .foregroundColor(.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func contentSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionHeader("Content")
                Spacer()
                Button {
                    if let text = item.textContent {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(String(text), forType: .string)
                        flashCopyConfirmation()
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy content")
            }

            if let text = item.textContent, !text.isEmpty {
                Text(text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No text content")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(item: ContextItem) -> some View {
        HStack(spacing: 10) {
            Button {
                copyAsMarkdown(item: item)
            } label: {
                Label("Copy as Markdown", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)

            Button {
                copyAllToClipboard(item: item)
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.05)
    }

    @ViewBuilder
    private func statusBadge(item: ContextItem) -> some View {
        switch item.status {
        case .pending:
            Text("Pending")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        case .processing:
            HStack(spacing: 3) {
                ProgressView().scaleEffect(0.4)
                Text("Processing")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        case .ready:
            Text("Ready")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .failed:
            Text("Failed")
                .font(.system(size: 10))
                .foregroundColor(.red)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        return formatter.string(from: date)
    }

    private func groupedEntities(_ entities: [ExtractedEntity]) -> [ExtractedEntity] {
        let seen = NSMutableSet()
        return entities.filter { entity in
            let key = "\(entity.kind.rawValue):\(entity.text.lowercased())"
            if seen.contains(key) { return false }
            seen.add(key)
            return true
        }
    }

    private func flashCopyConfirmation() {
        showCopyConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopyConfirmation = false }
        }
    }

    // MARK: - Markdown Export

    private func copyAsMarkdown(item: ContextItem) {
        var md = "# \(item.sourceTitle.isEmpty ? "Untitled" : item.sourceTitle)\n\n"
        md += "**Source:** \(item.sourceURL.isEmpty ? "None" : item.sourceURL)  \n"
        md += "**Captured:** \(formattedDate(item.capturedAt))  \n"
        md += "**Kind:** \(item.kind.displayName)  \n"

        if !item.tags.isEmpty {
            md += "**Tags:** \(item.tags.joined(separator: ", "))  \n"
        }

        md += "\n---\n\n"

        if let text = item.textContent, !text.isEmpty {
            md += "\(text)\n"
        }

        md += "\n---\n\n"

        if !item.entities.isEmpty {
            md += "## Entities\n\n"
            let grouped = Dictionary(grouping: item.entities, by: \.kind)
            for (kind, entities) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                md += "- **\(kind.displayName):** \(entities.map(\.text).joined(separator: ", "))\n"
            }
            md += "\n"
        }

        if let citation = item.citation {
            md += "## Citation\n\n"
            md += "[\(citation.title)](\(citation.url))\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        flashCopyConfirmation()
    }

    private func copyAllToClipboard(item: ContextItem) {
        copyAsMarkdown(item: item)
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        let totalHeight = currentY + lineHeight
        return LayoutResult(size: CGSize(width: min(maxX, maxWidth), height: totalHeight), positions: positions)
    }
}

extension EntityKind {
    var systemImage: String {
        switch self {
        case .person: "person"
        case .organization: "building.2"
        case .product: "box"
        case .location: "mappin"
        case .date: "calendar"
        case .url: "link"
        case .number: "number"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .concept: "lightbulb"
        }
    }

    var displayName: String {
        switch self {
        case .person: "Person"
        case .organization: "Org"
        case .product: "Product"
        case .location: "Location"
        case .date: "Date"
        case .url: "URL"
        case .number: "Number"
        case .code: "Code"
        case .concept: "Concept"
        }
    }
}
