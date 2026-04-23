import SwiftUI

struct ResearchInterrogationView: View {
    @Environment(BrowserBridge.self) private var browserBridge

    @State private var sourceFilterText: String = ""
    @State private var tabFilterText: String = ""
    @State private var showTabChooser: Bool = false

    private var isChoosingTab: Bool {
        showTabChooser || browserBridge.interrogationTabID == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            if isChoosingTab {
                tabChooserContent
            } else if let tabTitle = browserBridge.interrogationTabTitle,
                      browserBridge.discoveredSources.isEmpty,
                      !browserBridge.isInterrogating {
                emptyState(tabTitle: tabTitle)
            } else {
                interrogationContent
            }
        }
        .task(id: isChoosingTab) {
            guard isChoosingTab else { return }
            requestTabsIfNeeded(force: browserBridge.interrogationAvailableTabs.isEmpty)
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text("Interrogate")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if let tabTitle = browserBridge.interrogationTabTitle, !isChoosingTab {
                Text(tabTitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Button(isChoosingTab ? "Refresh Tabs" : "Change Tab") {
                browserBridge.clearInterrogationSourceSelection()
                showTabChooser = true
                requestTabsIfNeeded(force: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                showTabChooser = false
                browserBridge.endInterrogation()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Close interrogation")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var tabChooserContent: some View {
        VStack(spacing: 0) {
            TextField("Filter tabs", text: $tabFilterText)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            if browserBridge.isLoadingInterrogationTabs {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView("Loading browser tabs...")
                        .controlSize(.small)
                    Spacer()
                }
            } else if filteredTabs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(browserBridge.interrogationAvailableTabs.isEmpty ? "No tabs available" : "No matching tabs")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(filteredTabs) { tab in
                    Button {
                        sourceFilterText = ""
                        browserBridge.clearInterrogationSourceSelection()
                        browserBridge.interrogateTab(tab)
                        showTabChooser = false
                    } label: {
                        tabRow(tab)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
    }

    private var interrogationContent: some View {
        sourceInventory
    }

    private var sourceInventory: some View {
        VStack(spacing: 0) {
            Text("Sources")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if browserBridge.isInterrogating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
            }

            if let error = browserBridge.interrogationError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }

            TextField("Filter sources", text: $sourceFilterText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(groupedSources) { group in
                        if !group.kind.isEmpty {
                            Text(group.kind)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }

                        ForEach(group.items) { source in
                            Button {
                                browserBridge.selectInterrogationSource(source)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: source.systemImage)
                                        .font(.system(size: 10))
                                        .foregroundColor(sourceIconColor(source))
                                        .frame(width: 14)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(source.label)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(source.detail)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(browserBridge.selectedInterrogationSourceID == source.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func emptyState(tabTitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text(tabTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            Text("No sources discovered")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button("Re-scan") {
                    if let tab = selectedInterrogationTab {
                        browserBridge.interrogateTab(tab)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Refresh Network") {
                    browserBridge.refreshXHRSources()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(20)
    }

    private var filteredTabs: [BrowserTab] {
        let query = tabFilterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return browserBridge.interrogationAvailableTabs }
        return browserBridge.interrogationAvailableTabs.filter {
            $0.displayTitle.lowercased().contains(query)
                || $0.displayHost.lowercased().contains(query)
                || $0.url.lowercased().contains(query)
                || $0.platform.lowercased().contains(query)
        }
    }

    private var groupedSources: [SourceGroup] {
        let query = sourceFilterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [DiscoveredSource]
        if query.isEmpty {
            filtered = browserBridge.discoveredSources
        } else {
            filtered = browserBridge.discoveredSources.filter { source in
                source.label.lowercased().contains(query)
                    || source.detail.lowercased().contains(query)
                    || source.kindLabel.lowercased().contains(query)
            }
        }

        let kindOrder: [ResearchSourceKind] = [.domSummary, .structuredJSON, .table, .xhrFeed, .imageFeed]
        var groups: [SourceGroup] = []

        for kind in kindOrder {
            let items = filtered.filter { $0.sourceKind == kind }
            if !items.isEmpty {
                groups.append(SourceGroup(kind: Self.kindLabel(for: kind), items: items))
            }
        }

        let unknown = filtered.filter { source in !kindOrder.contains(source.sourceKind) }
        if !unknown.isEmpty {
            groups.append(SourceGroup(kind: "", items: unknown))
        }

        return groups
    }

    private var selectedInterrogationTab: BrowserTab? {
        guard let tabID = browserBridge.interrogationTabID else { return nil }
        return BrowserTab(
            id: tabID,
            platform: "browser",
            title: browserBridge.interrogationTabTitle ?? browserBridge.interrogationTabURL ?? "Browser Tab",
            url: browserBridge.interrogationTabURL ?? ""
        )
    }

    private func requestTabsIfNeeded(force: Bool) {
        if force || browserBridge.interrogationAvailableTabs.isEmpty {
            browserBridge.queryTabs(forInterrogation: true)
        }
    }

    @ViewBuilder
    private func tabRow(_ tab: BrowserTab) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tab.matchesKnownAIHost ? .accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(tab.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(tab.displayHost)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(tab.url)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func sourceIconColor(_ source: DiscoveredSource) -> Color {
        switch source.sourceKind {
        case .domSummary: return .blue
        case .structuredJSON: return .orange
        case .table: return .green
        case .xhrFeed: return .purple
        case .imageFeed: return .pink
        }
    }

    private static func kindLabel(for kind: ResearchSourceKind) -> String {
        switch kind {
        case .domSummary: return "Page Content"
        case .structuredJSON: return "JSON"
        case .table: return "Tables"
        case .xhrFeed: return "Network"
        case .imageFeed: return "Media"
        }
    }
}

private struct SourceGroup: Identifiable {
    let id = UUID()
    let kind: String
    let items: [DiscoveredSource]
}
