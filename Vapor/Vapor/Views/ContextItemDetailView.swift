import AppKit
import SwiftData
import SwiftUI

struct ContextItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(ContextExplorerStore.self) private var contextExplorerStore
    let itemID: UUID

    @State private var item: ContextItem?
    @State private var refreshTask: Task<Void, Never>?
    @State private var hasTimedOutLoadingItem = false
    @State private var showCopyConfirmation = false
    @State private var isSummarizing = false
    @State private var isRegeneratingCitation = false
    private let summarizer = SummarizationService()
    private let citationBuilder = CitationBuilder()
    private let missingItemRetryLimit = 15

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection(item: item)

                        if item.status == .processing || item.status == .pending {
                            processingBanner(item: item)
                        }

                        if item.primaryImageAsset != nil {
                            Divider()
                            imageSection(item: item)
                        }

                        Divider()

                        sourceSection(item: item)

                        summarySection(item: item)

                        if item.citation != nil || item.status == .processing {
                            Divider()
                            citationSection(item: item)
                        }

                        if item.entityCount > 0 || item.status == .processing {
                            Divider()
                            entitiesSection(item: item)
                        }

                        if !item.tags.isEmpty || item.status == .processing {
                            Divider()
                            tagsSection(item: item)
                        }

                        Divider()

                        contentSection(item: item)

                        if !item.sortedURLLinks.isEmpty || item.status == .processing {
                            Divider()
                            urlsSection(item: item)
                        }

                        Divider()

                        actionButtons(item: item)
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    if hasTimedOutLoadingItem {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                        Text("Item not found")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text("The captured item could not be loaded. It may have been removed or never finished saving.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading captured item")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text("This window will update as the document is saved and processed.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            hasTimedOutLoadingItem = false
            fetchItem()
            startRefreshingItem()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
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

    private func startRefreshingItem() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            var missingItemAttempts = 0

            while !Task.isCancelled {
                fetchItem()

                if let item {
                    missingItemAttempts = 0
                    hasTimedOutLoadingItem = false

                    if item.status != .processing && item.status != .pending {
                        break
                    }
                } else {
                    missingItemAttempts += 1
                    if missingItemAttempts >= missingItemRetryLimit {
                        hasTimedOutLoadingItem = true
                        break
                    }
                }

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }

            refreshTask = nil
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
    private func processingBanner(item: ContextItem) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.status == .pending ? "Queued for processing" : "Processing captured content")
                    .font(.system(size: 11, weight: .medium))
                Text("You can read the captured content now. This window will fill in the summary, entities, tags, and citation as they finish.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }

    @ViewBuilder
    private func sourceSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Source")

            if let sourceLink = item.sortedURLLinks.first(where: { $0.role == .source }),
               !sourceLink.urlDisplayText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Button(sourceLink.urlDisplayText) {
                        openExplorer(for: sourceLink)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                    if let url = URL(string: sourceLink.urlDisplayText) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("No source URL")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if item.sourceAuthor != nil || item.sourcePublishedDate != nil {
                HStack(spacing: 12) {
                    if let author = item.sourceAuthor {
                        HStack(spacing: 4) {
                            Image(systemName: "person")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Button(author) {
                                openExplorerForAuthor(author)
                            }
                            .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    if let domain = item.sortedURLLinks.first(where: { $0.role == .source })?.domain, !domain.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Button(domain) {
                                openExplorerForDomain(domain)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    }
                    if let pubDate = item.sourcePublishedDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(formattedDate(pubDate))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func imageSection(item: ContextItem) -> some View {
        if let asset = item.primaryImageAsset {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Image")

                ImageAssetThumbnailView(asset: asset, size: nil, preferThumbnail: false, contentMode: .fit) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 8) {
                    Text(asset.sourceKind.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))

                    if asset.pixelWidth > 0, asset.pixelHeight > 0 {
                        Text("\(asset.pixelWidth) x \(asset.pixelHeight)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Reveal") {
                        if let imageURL = imageURL(for: asset) {
                            NSWorkspace.shared.activateFileViewerSelecting([imageURL])
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func urlsSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("URLs (\(item.sortedURLLinks.count))")

            if item.sortedURLLinks.isEmpty, item.status == .processing {
                processingPlaceholder("Extracting URLs...")
            } else {
                ForEach(item.sortedURLLinks) { link in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: link.role == .source ? "link.circle.fill" : "link")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 12, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(link.role.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                                if !link.domain.isEmpty {
                                    Button(link.domain) {
                                        openExplorerForDomain(link.domain)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                }
                            }

                            HStack(spacing: 6) {
                                Button(link.urlDisplayText) {
                                    openExplorer(for: link)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .lineLimit(2)
                                .truncationMode(.middle)

                                if let url = URL(string: link.urlDisplayText) {
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Spacer()
                    }
                }
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
                    regenerateCitation(for: item)
                } label: {
                    if isRegeneratingCitation {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Regenerate citation")
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
            } else if item.status == .processing {
                processingPlaceholder("Building citation...")
            }
        }
    }

    @ViewBuilder
    private func entitiesSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                sectionHeader("Entities (\(item.sortedEntityLinks.count))")

                if let backend = item.extractionBackend {
                    backendBadge(backend)
                }
            }

            if item.sortedEntityLinks.isEmpty, item.status == .processing {
                processingPlaceholder("Extracting entities...")
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(item.sortedEntityLinks) { link in
                        Button {
                            openExplorer(for: link)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: link.entityKind.systemImage)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(link.displayText)
                                    .font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
                        .help("\(link.entityKind.displayName) · \(Int(link.confidence * 100))%")
                    }
                }
            }
        }
    }

    private func backendBadge(_ backend: EntityExtractionBackend) -> some View {
        let (color, label): (Color, String) = {
            switch backend {
            case .openRouter: (.green, "OpenRouter")
            case .ollama: (.blue, "Ollama")
            case .nlTagger: (.orange, "NLTagger")
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    @ViewBuilder
    private func tagsSection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Tags (\(item.tags.count))")

            if item.tags.isEmpty, item.status == .processing {
                processingPlaceholder("Generating tags...")
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        Button {
                            openExplorerForTag(tag)
                        } label: {
                            Text(tag)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .contentShape(Rectangle())
                    }
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
                    if let content = item.markdownContent ?? item.textContent {
                        copyToPasteboard(content)
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

            let sections = contentSections(for: item)
            if !sections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sections) { section in
                        MarkdownSectionView(section: section) {
                            copyToPasteboard(section.rawContent)
                            flashCopyConfirmation()
                        }
                    }
                }
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

    private func flashCopyConfirmation() {
        showCopyConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopyConfirmation = false }
        }
    }

    private func copyToPasteboard(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    // MARK: - Summary

    @ViewBuilder
    private func summarySection(item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader("Summary")
                Spacer()
                if item.summary != nil {
                    Button {
                        if let summary = item.summary, !summary.abstract.isEmpty {
                            let points = summary.keyPoints.map { "• \($0)" }.joined(separator: "\n")
                            let full = points.isEmpty ? summary.abstract : "\(summary.abstract)\n\n\(points)"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(full, forType: .string)
                            flashCopyConfirmation()
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy summary")
                }
            }

            if let summary = item.summary {
                VStack(alignment: .leading, spacing: 6) {
                    if !summary.abstract.isEmpty {
                        Text(summary.abstract)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }

                    if !summary.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(summary.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(point)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            } else if item.status == .processing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                    Text("Generating summary...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                Button {
                    generateSummary(for: item)
                } label: {
                    HStack(spacing: 4) {
                        if isSummarizing {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                        }
                        Text(isSummarizing ? "Generating…" : "Generate Summary")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSummarizing)
            }
        }
    }

    private func generateSummary(for item: ContextItem) {
        guard let text = item.textContent, !text.isEmpty else { return }
        isSummarizing = true
        Task { @MainActor in
            if let summary = await summarizer.summarize(text: text) {
                item.summary = summary
                try? modelContext.save()
            }
            isSummarizing = false
        }
    }

    private func regenerateCitation(for item: ContextItem) {
        isRegeneratingCitation = true
        Task { @MainActor in
            item.citation = citationBuilder.build(for: item, format: .apa)
            try? modelContext.save()
            isRegeneratingCitation = false
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

        if let summary = item.summary {
            md += "## Summary\n\n"
            if !summary.abstract.isEmpty {
                md += "\(summary.abstract)\n\n"
            }
            if !summary.keyPoints.isEmpty {
                for point in summary.keyPoints {
                    md += "- \(point)\n"
                }
                md += "\n"
            }
            md += "---\n\n"
        }

        if let markdown = item.markdownContent, !markdown.isEmpty {
            md += "\(markdown)\n"
        } else if let text = item.textContent, !text.isEmpty {
            md += "\(text)\n"
        }

        md += "\n---\n\n"

        if !item.sortedURLLinks.isEmpty {
            md += "## URLs\n\n"
            for link in item.sortedURLLinks {
                md += "- **\(link.role.displayName):** \(link.urlDisplayText)"
                if !link.domain.isEmpty {
                    md += " (\(link.domain))"
                }
                md += "\n"
            }
            md += "\n"
        }

        if !item.sortedEntityLinks.isEmpty {
            md += "## Entities\n\n"
            let grouped = Dictionary(grouping: item.sortedEntityLinks, by: \.entityKind)
            for (kind, entities) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                md += "- **\(kind.displayName):** \(entities.map(\.displayText).joined(separator: ", "))\n"
            }
            md += "\n"
        }

        if let citation = item.citation {
            md += "## Citation\n\n"
            md += "\(citation.rendered)\n"
        }

        copyToPasteboard(md)
        flashCopyConfirmation()
    }

    private func copyAllToClipboard(item: ContextItem) {
        if let markdown = item.markdownContent, !markdown.isEmpty {
            copyToPasteboard(markdown)
            flashCopyConfirmation()
            return
        }

        if let text = item.textContent, !text.isEmpty {
            copyToPasteboard(text)
            flashCopyConfirmation()
            return
        }

        copyAsMarkdown(item: item)
    }

    @ViewBuilder
    private func processingPlaceholder(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func imageURL(for asset: ImageAsset) -> URL? {
        if let originalPath = asset.originalPath, FileManager.default.fileExists(atPath: originalPath) {
            return URL(fileURLWithPath: originalPath)
        }

        if BlobStore.shared.exists(relativePath: asset.blobPath) {
            return BlobStore.shared.fileURL(relativePath: asset.blobPath)
        }

        return nil
    }

    private func openExplorer(for link: ContextItemURLLink) {
        contextExplorerStore.focusOnURL(link)
        openWindow(id: "context-explorer")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openExplorer(for link: ContextItemEntityLink) {
        contextExplorerStore.focusOnEntity(link)
        openWindow(id: "context-explorer")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openExplorerForAuthor(_ author: String) {
        contextExplorerStore.focusOnAuthor(author)
        openWindow(id: "context-explorer")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openExplorerForDomain(_ domain: String) {
        contextExplorerStore.focusOnDomain(domain)
        openWindow(id: "context-explorer")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openExplorerForTag(_ tag: String) {
        contextExplorerStore.focusOnTag(tag)
        openWindow(id: "context-explorer")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func contentSections(for item: ContextItem) -> [MarkdownContentSection] {
        let content = item.markdownContent ?? item.textContent ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return MarkdownContentSection.sections(from: content, markdownPreferred: item.markdownContent != nil)
    }
}

private struct MarkdownSectionView: View {
    let section: MarkdownContentSection
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                sectionBody
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy section")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch section.kind {
        case .code:
            Text(section.displayContent)
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(4)
                .textSelection(.enabled)
        case .heading, .markdown:
            if let attributed = try? AttributedString(markdown: section.displayContent) {
                Text(attributed)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .textSelection(.enabled)
            } else {
                Text(section.displayContent)
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct MarkdownContentSection: Identifiable {
    enum Kind {
        case heading
        case markdown
        case code
    }

    let id = UUID()
    let kind: Kind
    let rawContent: String
    let displayContent: String

    static func sections(from content: String, markdownPreferred: Bool) -> [MarkdownContentSection] {
        markdownPreferred ? markdownSections(from: content) : plainTextSections(from: content)
    }

    private static func markdownSections(from content: String) -> [MarkdownContentSection] {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var sections: [MarkdownContentSection] = []
        var current: [String] = []
        var inCodeFence = false

        func flushCurrent(as kind: Kind = .markdown) {
            let raw = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            current.removeAll()
            guard !raw.isEmpty else { return }
            let display = kind == .code ? stripCodeFence(raw) : raw
            sections.append(MarkdownContentSection(kind: kind, rawContent: raw, displayContent: display))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                current.append(line)
                inCodeFence.toggle()
                if !inCodeFence {
                    flushCurrent(as: .code)
                }
                continue
            }

            if inCodeFence {
                current.append(line)
                continue
            }

            if trimmed.hasPrefix("#") {
                flushCurrent()
                sections.append(MarkdownContentSection(kind: .heading, rawContent: trimmed, displayContent: trimmed))
                continue
            }

            if trimmed.isEmpty {
                flushCurrent()
                continue
            }

            current.append(line)
        }

        flushCurrent()
        return sections
    }

    private static func plainTextSections(from content: String) -> [MarkdownContentSection] {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { MarkdownContentSection(kind: .markdown, rawContent: $0, displayContent: $0) }
    }

    private static func stripCodeFence(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        if !lines.isEmpty, lines[0].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeFirst()
        }
        if !lines.isEmpty, lines[lines.count - 1].trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
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
