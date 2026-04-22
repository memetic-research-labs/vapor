import AppKit
import SwiftUI

struct BrowserSourceExplorerView: View {
    let source: DiscoveredSource?
    let preview: SourcePreview?
    let isLoadingPreview: Bool
    let onClearSelection: () -> Void

    @State private var selectedSection: ExplorerSection = .overview
    @State private var wrapsLines = false
    @State private var parsedJSONRoot: JSONTreeNode?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isLoadingPreview {
                loadingState
            } else if let source {
                VStack(spacing: 0) {
                    sectionPicker
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                    Divider()

                    switch selectedSection {
                    case .overview:
                        overviewContent(source)
                    case .tree:
                        treeContent(for: source)
                    case .raw:
                        rawContent(for: source)
                    }
                }
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshParsedJSON()
        }
        .onChange(of: source?.id) { _, _ in
            selectedSection = .overview
            refreshParsedJSON()
        }
        .onChange(of: preview?.sourceId) { _, _ in
            refreshParsedJSON()
        }
        .onChange(of: preview?.content) { _, _ in
            refreshParsedJSON()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let source {
                Image(systemName: source.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text(source.kindLabel + " · " + source.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Data Explorer")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            if source != nil {
                Button("Clear") {
                    onClearSelection()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sectionPicker: some View {
        HStack {
            Picker("Explorer Section", selection: $selectedSection) {
                ForEach(availableSections) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: parsedJSONRoot == nil ? 220 : 320)

            Spacer()

            if selectedSection == .raw, preview != nil {
                Toggle("Wrap Lines", isOn: $wrapsLines)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button("Copy") {
                    copyPreviewToPasteboard()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func overviewContent(_ source: DiscoveredSource) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewCard(title: "Source") {
                    overviewRow(label: "Kind", value: source.kindLabel)
                    overviewRow(label: "Label", value: source.label)
                    overviewRow(label: "Detail", value: source.detail)
                    if let recordEstimate = source.recordEstimate {
                        overviewRow(label: "Estimated Records", value: "\(recordEstimate)")
                    }
                    if let sizeHint = source.sizeHint {
                        overviewRow(label: "Size Hint", value: sizeHint)
                    }
                }

                overviewCard(title: "Preview") {
                    if let preview, preview.sourceId == source.id {
                        overviewRow(label: "MIME Type", value: preview.mimeType)
                        overviewRow(label: "Payload Size", value: formatBytes(preview.sizeBytes ?? 0))
                        if parsedJSONRoot != nil {
                            overviewRow(label: "Structured View", value: "Available")
                        }

                        Divider()
                            .padding(.vertical, 4)

                        Text(previewExcerpt(preview.content))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Select a source from the sidebar to load its contents here.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func treeContent(for source: DiscoveredSource) -> some View {
        if let preview, preview.sourceId == source.id, let parsedJSONRoot {
            JSONTreeExplorerView(rootNode: parsedJSONRoot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Spacer()
                Text("Structured JSON view is not available for this source.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rawContent(for source: DiscoveredSource) -> some View {
        Group {
            if let preview, preview.sourceId == source.id {
                ScrollView([.vertical, wrapsLines ? [] : .horizontal]) {
                    Group {
                        if wrapsLines {
                            Text(preview.content)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(16)
                        } else {
                            HStack(alignment: .top, spacing: 0) {
                                Text(preview.content)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: true, vertical: true)
                                    .padding(16)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                loadingState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var availableSections: [ExplorerSection] {
        parsedJSONRoot == nil ? [.overview, .raw] : [.overview, .tree, .raw]
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView("Loading source data...")
                .controlSize(.small)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("Select a source")
                .font(.system(size: 15, weight: .semibold))
            Text("Choose a discovered source from the interrogation sidebar to inspect its data here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func overviewCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            content()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func overviewRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }

    private func previewExcerpt(_ content: String) -> String {
        let snippetLimit = 1600
        guard content.count > snippetLimit else { return content }
        return String(content.prefix(snippetLimit)) + "\n..."
    }

    private func copyPreviewToPasteboard() {
        guard let preview else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preview.content, forType: .string)
    }

    private func refreshParsedJSON() {
        guard let source, let preview, preview.sourceId == source.id else {
            parsedJSONRoot = nil
            return
        }

        guard source.sourceKind == .structuredJSON || mimeTypeLooksLikeJSON(preview.mimeType) || contentLooksLikeJSON(preview.content) else {
            parsedJSONRoot = nil
            return
        }

        parsedJSONRoot = JSONTreeParser.parse(preview.content)

        if selectedSection == .tree, parsedJSONRoot == nil {
            selectedSection = .raw
        }
    }

    private func mimeTypeLooksLikeJSON(_ mimeType: String) -> Bool {
        mimeType.localizedCaseInsensitiveContains("json")
    }

    private func contentLooksLikeJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }
}

private enum ExplorerSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case tree = "Tree"
    case raw = "Raw"

    var id: String { rawValue }
}
