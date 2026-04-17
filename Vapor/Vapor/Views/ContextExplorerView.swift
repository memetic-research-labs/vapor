import SwiftUI
import SwiftData

private struct ExplorerFacetCount: Identifiable, Hashable {
    let key: String
    let title: String
    let count: Int
    let subtitle: String?

    var id: String { key }
}

struct ContextExplorerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ContextExplorerStore.self) private var explorerStore
    @Environment(VectorizationService.self) private var vectorizationService
    @Environment(\.openWindow) private var openWindow

    @Query(sort: [SortDescriptor(\ContextItem.capturedAt, order: .reverse)]) private var items: [ContextItem]
    @Query(sort: [SortDescriptor(\URLRecord.lastSeenAt, order: .reverse)]) private var urlRecords: [URLRecord]
    @Query(sort: [SortDescriptor(\EntityRecord.lastSeenAt, order: .reverse)]) private var entityRecords: [EntityRecord]

    @State private var semanticResultIDs: [UUID] = []
    @State private var isRunningSemanticSearch = false
    @State private var semanticSearchTask: Task<Void, Never>?
    @State private var semanticSearchRequestID = 0

    private let mainPaneBackground = Color(nsColor: .windowBackgroundColor)
    private let cardBackground = Color(nsColor: .controlBackgroundColor)

    private var entityByHash: [String: EntityRecord] {
        Dictionary(uniqueKeysWithValues: entityRecords.map { ($0.entityHash, $0) })
    }

    private var urlByHash: [String: URLRecord] {
        Dictionary(uniqueKeysWithValues: urlRecords.map { ($0.urlHash, $0) })
    }

    private var totalDomainCount: Int {
        Set(items.compactMap { item in
            item.sortedURLLinks.first(where: { $0.role == .source })?.domain.lowercased()
        }).count
    }

    private var totalAuthorCount: Int {
        Set(items.compactMap { $0.sourceAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }).count
    }

    private var totalTagCount: Int {
        Set(items.flatMap(\.tags)).count
    }

    private var sourceDomains: [ExplorerFacetCount] {
        facetCounts(from: items.compactMap { item in
            item.sortedURLLinks.first(where: { $0.role == .source })?.domain
        })
    }

    private var authors: [ExplorerFacetCount] {
        facetCounts(from: items.compactMap { $0.sourceAuthor })
    }

    private var tags: [ExplorerFacetCount] {
        facetCounts(from: items.flatMap(\.tags))
    }

    private var types: [ExplorerFacetCount] {
        Dictionary(grouping: items, by: { $0.kind })
            .map { kind, grouped in
                ExplorerFacetCount(key: kind.rawValue, title: kind.displayName, count: grouped.count, subtitle: nil)
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.title < rhs.title }
                return lhs.count > rhs.count
            }
    }

    private var topURLs: [ExplorerFacetCount] {
        urlRecords
            .map { record in
                ExplorerFacetCount(
                    key: record.urlHash,
                    title: record.canonicalURL,
                    count: record.links.count,
                    subtitle: record.domain
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.title < rhs.title }
                return lhs.count > rhs.count
            }
    }

    private var groupedEntities: [(kind: EntityKind, values: [ExplorerFacetCount])] {
        Dictionary(grouping: entityRecords, by: { $0.kind })
            .map { kind, records in
                let values = records
                    .map { record in
                        ExplorerFacetCount(
                            key: record.entityHash,
                            title: record.displayText,
                            count: record.links.count,
                            subtitle: nil
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.count == rhs.count { return lhs.title < rhs.title }
                        return lhs.count > rhs.count
                    }
                return (kind, values)
            }
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private var breadcrumbText: String {
        var values = explorerStore.breadcrumbs
        if explorerStore.hasActiveSearch {
            values.append("Search")
        }
        return values.joined(separator: " / ")
    }

    private var shouldShowResults: Bool {
        if explorerStore.hasActiveSearch || explorerStore.hasActiveStructuredFilter {
            return true
        }

        switch explorerStore.selectedSection {
        case .recent, .processing, .failed:
            return true
        default:
            return false
        }
    }

    private var sortedFilteredItems: [ContextItem] {
        let base = items.filter(matchesStructuredFilters)

        if explorerStore.semanticMode == .semantic,
           !semanticResultIDs.isEmpty,
           explorerStore.hasActiveSearch {
            let index = Dictionary(uniqueKeysWithValues: semanticResultIDs.enumerated().map { ($1, $0) })
            return base
                .filter { index[$0.id] != nil }
                .sorted { (index[$0.id] ?? .max) < (index[$1.id] ?? .max) }
        }

        switch explorerStore.sortMode {
        case .newestFirst:
            return base.sorted { $0.capturedAt > $1.capturedAt }
        case .oldestFirst:
            return base.sorted { $0.capturedAt < $1.capturedAt }
        case .titleAZ:
            return base.sorted {
                let lhs = $0.sourceTitle.isEmpty ? "Untitled" : $0.sourceTitle
                let rhs = $1.sourceTitle.isEmpty ? "Untitled" : $1.sourceTitle
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack {
                mainPaneBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Divider()
                    if shouldShowResults {
                        resultsPane
                    } else {
                        switch explorerStore.selectedSection {
                        case .overview:
                            overviewPane
                        case .domains:
                            facetPane(title: "Domains", subtitle: "Browse the sources you capture from most often.") {
                                facetList(sourceDomains) { facet in
                                    explorerStore.focusOnDomain(facet.title)
                                }
                            }
                        case .authors:
                            facetPane(title: "Authors", subtitle: "Browse context by author provenance.") {
                                facetList(authors) { facet in
                                    explorerStore.focusOnAuthor(facet.title)
                                }
                            }
                        case .entities:
                            entitiesFacetPane
                        case .urls:
                            facetPane(title: "URLs", subtitle: "Canonicalized source and referenced URLs across your corpus.") {
                                facetList(topURLs) { facet in
                                    if let record = urlByHash[facet.key] {
                                        explorerStore.selectedSection = .urls
                                        explorerStore.selectedURLHash = record.urlHash
                                        explorerStore.searchText = record.canonicalURL
                                        explorerStore.semanticMode = .keyword
                                    }
                                }
                            }
                        case .tags:
                            facetPane(title: "Tags", subtitle: "Browse your auto-generated tags and quickly pivot into matching captures.") {
                                facetList(tags) { facet in
                                    explorerStore.focusOnTag(facet.title)
                                }
                            }
                        case .types:
                            facetPane(title: "Types", subtitle: "Browse by capture type.") {
                                facetList(types) { facet in
                                    if let kind = ContextItemKind(rawValue: facet.key) {
                                        explorerStore.focusOnKind(kind)
                                    }
                                }
                            }
                        case .recent, .processing, .failed:
                            resultsPane
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.searchText) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.semanticMode) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.selectedDomain) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.selectedAuthor) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.selectedEntityHash) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.selectedURLHash) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.selectedTag) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.selectedKindRaw) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onChange(of: explorerStore.selectedSection) { _, _ in
            runSemanticSearchIfNeeded()
        }
        .onDisappear {
            semanticSearchTask?.cancel()
            semanticSearchTask = nil
        }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { explorerStore.selectedSection },
            set: { newValue in
                guard let newValue else { return }
                explorerStore.showSection(newValue)
            }
        )) {
            Section("Browse") {
                sidebarRow(.overview)
                sidebarRow(.recent, badge: items.count)
            }

            Section("Facets") {
                sidebarRow(.domains, badge: totalDomainCount)
                sidebarRow(.authors, badge: totalAuthorCount)
                sidebarRow(.entities, badge: entityRecords.count)
                sidebarRow(.urls, badge: urlRecords.count)
                sidebarRow(.tags, badge: totalTagCount)
                sidebarRow(.types, badge: types.count)
            }

            Section("Queue") {
                sidebarRow(.processing, badge: items.filter { $0.status == .processing || $0.status == .pending }.count)
                sidebarRow(.failed, badge: items.filter { $0.status == .failed }.count)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    }

    @ViewBuilder
    private func sidebarRow(_ section: ContextExplorerSection, badge: Int? = nil) -> some View {
        HStack {
            Label(section.displayName, systemImage: section.systemImage)
            Spacer()
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
        .tag(section)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Search titles, summaries, entities, URLs, authors...", text: Binding(
                    get: { explorerStore.searchText },
                    set: { explorerStore.searchText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 320)

                Picker("Mode", selection: Binding(
                    get: { explorerStore.semanticMode },
                    set: { explorerStore.semanticMode = $0 }
                )) {
                    ForEach(ContextExplorerSemanticMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)

                Picker("Sort", selection: Binding(
                    get: { explorerStore.sortMode },
                    set: { explorerStore.sortMode = $0 }
                )) {
                    ForEach(ContextExplorerSortMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 94)

                Button("Overview") {
                    explorerStore.openOverview()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Label(explorerStore.selectedSection.displayName, systemImage: explorerStore.selectedSection.systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                if breadcrumbText != explorerStore.selectedSection.displayName {
                    Text(breadcrumbText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Toggle("Ready only", isOn: Binding(
                    get: { explorerStore.readyOnly },
                    set: { explorerStore.readyOnly = $0 }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer()

                if explorerStore.semanticMode == .semantic, explorerStore.hasActiveSearch {
                    if isRunningSemanticSearch {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("\(semanticResultIDs.count) semantic matches")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("\(sortedFilteredItems.count) items")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            if explorerStore.hasActiveSearch || explorerStore.hasActiveStructuredFilter {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if explorerStore.hasActiveSearch {
                            filterChip("Search: \(explorerStore.searchText)") {
                                explorerStore.clearQuery()
                            }
                        }
                        if let domain = explorerStore.selectedDomain {
                            filterChip("Domain: \(domain)") {
                                explorerStore.selectedDomain = nil
                            }
                        }
                        if let author = explorerStore.selectedAuthor {
                            filterChip("Author: \(author)") {
                                explorerStore.selectedAuthor = nil
                            }
                        }
                        if let tag = explorerStore.selectedTag {
                            filterChip("Tag: \(tag)") {
                                explorerStore.selectedTag = nil
                            }
                        }
                        if let kind = explorerStore.selectedKind {
                            filterChip("Type: \(kind.displayName)") {
                                explorerStore.selectedKind = nil
                            }
                        }
                        if let entityHash = explorerStore.selectedEntityHash,
                           let entity = entityByHash[entityHash] {
                            filterChip("Entity: \(entity.displayText)") {
                                explorerStore.selectedEntityHash = nil
                            }
                        }
                        if let urlHash = explorerStore.selectedURLHash,
                           let url = urlByHash[urlHash] {
                            filterChip("URL: \(url.canonicalURL)") {
                                explorerStore.selectedURLHash = nil
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(mainPaneBackground)
    }

    private var overviewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewSummaryRow

                GroupBox("Recent Captures") {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLead("Jump back into the latest material you captured.")
                        ForEach(Array(items.prefix(8))) { item in
                            overviewItemButton(item)
                        }
                        if items.isEmpty {
                            emptyFacetText("Capture a few articles or selections and they will appear here.")
                        }
                    }
                    .padding(6)
                }

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Top Domains") {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLead("The sources you have captured from most often.")
                            compactFacetButtons(sourceDomains.prefix(8)) { facet in
                                explorerStore.focusOnDomain(facet.title)
                            }
                        }
                        .padding(6)
                    }

                    GroupBox("Top Tags") {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLead("Your auto-generated topics for quick drilldown.")
                            compactFacetButtons(tags.prefix(10)) { facet in
                                explorerStore.focusOnTag(facet.title)
                            }
                        }
                        .padding(6)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Top Entities") {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLead("Named entities and concepts extracted from your corpus.")
                            ForEach(groupedEntities.prefix(3), id: \.kind.rawValue) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(group.kind.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                    compactFacetButtons(group.values.prefix(4)) { facet in
                                        explorerStore.selectedSection = .entities
                                        explorerStore.selectedEntityHash = facet.key
                                        explorerStore.searchText = facet.title
                                        explorerStore.semanticMode = .keyword
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }

                    GroupBox("Authors") {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLead("Authors surfaced from the pages you collect.")
                            compactFacetButtons(authors.prefix(8)) { facet in
                                explorerStore.focusOnAuthor(facet.title)
                            }
                        }
                        .padding(6)
                    }
                }

                if items.contains(where: { $0.status == .processing || $0.status == .pending || $0.status == .failed }) {
                    GroupBox("Queue Health") {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLead("Keep an eye on processing and failures without leaving the explorer.")
                            HStack(spacing: 12) {
                                queueStatusButton(title: "Processing", count: items.filter { $0.status == .processing || $0.status == .pending }.count, section: .processing, tint: .blue)
                                queueStatusButton(title: "Failed", count: items.filter { $0.status == .failed }.count, section: .failed, tint: .red)
                            }
                        }
                        .padding(6)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(mainPaneBackground)
    }

    private var overviewSummaryRow: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                summaryCard(title: "Context Items", value: items.count, symbol: "tray.full", tint: .accentColor)
                summaryCard(title: "Domains", value: totalDomainCount, symbol: "globe", tint: .blue)
                summaryCard(title: "Authors", value: totalAuthorCount, symbol: "person.2", tint: .purple)
            }
            GridRow {
                summaryCard(title: "Entities", value: entityRecords.count, symbol: "sparkles", tint: .orange)
                summaryCard(title: "URLs", value: urlRecords.count, symbol: "link", tint: .green)
                summaryCard(title: "Tags", value: totalTagCount, symbol: "tag", tint: .pink)
            }
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: Int, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sectionLead(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func overviewItemButton(_ item: ContextItem) -> some View {
        Button {
            openWindow(value: ContextItemDetailPayload(itemID: item.id))
        } label: {
            explorerItemRow(item)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func compactFacetButtons<S: Sequence>(_ values: S, action: @escaping (ExplorerFacetCount) -> Void) -> some View where S.Element == ExplorerFacetCount {
        FlowLayout(spacing: 6) {
            ForEach(Array(values)) { facet in
                Button {
                    action(facet)
                } label: {
                    HStack(spacing: 6) {
                        Text(facet.title)
                            .lineLimit(1)
                        Text("\(facet.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private func queueStatusButton(title: String, count: Int, section: ContextExplorerSection, tint: Color) -> some View {
        Button {
            explorerStore.showSection(section)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text("\(count)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func facetPane<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                content()
            }
            .padding(16)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(mainPaneBackground)
    }

    @ViewBuilder
    private func facetList(_ values: [ExplorerFacetCount], action: @escaping (ExplorerFacetCount) -> Void) -> some View {
        if values.isEmpty {
            emptyFacetText("No captured values yet.")
        } else {
            LazyVStack(spacing: 6) {
                ForEach(values) { facet in
                    Button {
                        action(facet)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(facet.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.leading)
                                    .foregroundColor(.primary)
                                if let subtitle = facet.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(facet.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(cardBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private var entitiesFacetPane: some View {
        facetPane(title: "Entities", subtitle: "Browse named entities and concepts grouped by extracted kind.") {
            if groupedEntities.isEmpty {
                emptyFacetText("No entities have been extracted yet.")
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedEntities, id: \.kind.rawValue) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.kind.displayName)
                                .font(.system(size: 12, weight: .semibold))
                            facetList(group.values) { facet in
                                explorerStore.selectedSection = .entities
                                explorerStore.selectedEntityHash = facet.key
                                explorerStore.searchText = facet.title
                                explorerStore.semanticMode = .keyword
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func emptyFacetText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            if sortedFilteredItems.isEmpty {
                ContentUnavailableView(
                    "No Matching Context",
                    systemImage: "magnifyingglass",
                    description: Text("Adjust your filters or query to explore a different slice of your captured corpus.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedFilteredItems) { item in
                    Button {
                        openWindow(value: ContextItemDetailPayload(itemID: item.id))
                    } label: {
                        explorerItemRow(item)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Open Detail") {
                            openWindow(value: ContextItemDetailPayload(itemID: item.id))
                        }
                        if let sourceLink = item.sortedURLLinks.first(where: { $0.role == .source }), !sourceLink.domain.isEmpty {
                            Button("Filter by Domain") {
                                explorerStore.focusOnDomain(sourceLink.domain)
                            }
                        }
                        if let author = item.sourceAuthor, !author.isEmpty {
                            Button("Filter by Author") {
                                explorerStore.focusOnAuthor(author)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(mainPaneBackground)
    }

    @ViewBuilder
    private func explorerItemRow(_ item: ContextItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.sourceTitle.isEmpty ? "Untitled" : item.sourceTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.kind.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if let summary = item.summary?.abstract, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if let text = item.textContent, !text.isEmpty {
                Text(String(text.prefix(180)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let sourceLink = item.sortedURLLinks.first(where: { $0.role == .source }), !sourceLink.domain.isEmpty {
                    resultChip(systemName: "globe", text: sourceLink.domain) {
                        explorerStore.focusOnDomain(sourceLink.domain)
                    }
                }
                if let author = item.sourceAuthor, !author.isEmpty {
                    resultChip(systemName: "person", text: author) {
                        explorerStore.focusOnAuthor(author)
                    }
                }
                if !item.sortedEntityLinks.isEmpty {
                    resultCountChip(systemName: "sparkles", text: "\(item.sortedEntityLinks.count) entities")
                }
                if !item.sortedURLLinks.isEmpty {
                    resultCountChip(systemName: "link", text: "\(item.sortedURLLinks.count) URLs")
                }
                if item.status != .ready {
                    resultCountChip(systemName: "clock", text: item.status.rawValue.capitalized)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func resultChip(systemName: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 9))
                Text(text)
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func resultCountChip(systemName: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func filterChip(_ title: String, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.accentColor.opacity(0.1)))
        .foregroundColor(.accentColor)
    }

    private func facetCounts(from rawValues: [String]) -> [ExplorerFacetCount] {
        Dictionary(grouping: rawValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }, by: { $0 })
            .map { key, values in
                ExplorerFacetCount(key: key.lowercased(), title: key, count: values.count, subtitle: nil)
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
                return lhs.count > rhs.count
            }
    }

    private func matchesStructuredFilters(_ item: ContextItem) -> Bool {
        if explorerStore.readyOnly, item.status != .ready {
            return false
        }

        switch explorerStore.selectedSection {
        case .processing:
            if item.status != .processing && item.status != .pending { return false }
        case .failed:
            if item.status != .failed { return false }
        case .recent, .overview, .domains, .authors, .entities, .urls, .tags, .types:
            break
        }

        if let selectedURLHash = explorerStore.selectedURLHash,
           !item.urlLinks.contains(where: { $0.urlRecord?.urlHash == selectedURLHash }) {
            return false
        }

        if let selectedEntityHash = explorerStore.selectedEntityHash,
           !item.entityLinks.contains(where: { $0.entityRecord?.entityHash == selectedEntityHash }) {
            return false
        }

        if let selectedDomain = explorerStore.selectedDomain,
           !item.urlLinks.contains(where: { $0.urlRecord?.domain.lowercased() == selectedDomain.lowercased() }) {
            return false
        }

        if let selectedAuthor = explorerStore.selectedAuthor,
           item.sourceAuthor?.localizedCaseInsensitiveCompare(selectedAuthor) != .orderedSame {
            return false
        }

        if let selectedTag = explorerStore.selectedTag,
           !item.tags.contains(where: { $0.localizedCaseInsensitiveCompare(selectedTag) == .orderedSame }) {
            return false
        }

        if let selectedKind = explorerStore.selectedKind, item.kind != selectedKind {
            return false
        }

        let query = explorerStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let entityText = item.sortedEntityLinks.map(\.displayText).joined(separator: " ")
        let urlText = item.sortedURLLinks.map(\.urlDisplayText).joined(separator: " ")
        let domainText = item.sortedURLLinks.map(\.domain).joined(separator: " ")
        let haystacks = [
            item.sourceTitle,
            item.sourceURL,
            item.sourceAuthor ?? "",
            item.textContent ?? "",
            item.summary?.abstract ?? "",
            item.tags.joined(separator: " "),
            entityText,
            urlText,
            domainText
        ]

        return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func runSemanticSearchIfNeeded() {
        semanticSearchTask?.cancel()
        semanticSearchTask = nil

        guard explorerStore.semanticMode == .semantic else {
            semanticSearchRequestID += 1
            semanticResultIDs = []
            isRunningSemanticSearch = false
            return
        }

        let query = explorerStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            semanticSearchRequestID += 1
            semanticResultIDs = []
            isRunningSemanticSearch = false
            return
        }

        guard vectorizationService.isReady else {
            semanticSearchRequestID += 1
            semanticResultIDs = []
            isRunningSemanticSearch = false
            return
        }

        semanticSearchRequestID += 1
        let requestID = semanticSearchRequestID
        isRunningSemanticSearch = true

        semanticSearchTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard !Task.isCancelled, requestID == semanticSearchRequestID else { return }

            let resultIDs = await vectorizationService.searchContextItemIDs(matching: query, limit: 50)

            guard !Task.isCancelled, requestID == semanticSearchRequestID else { return }

            semanticResultIDs = resultIDs
            isRunningSemanticSearch = false
            semanticSearchTask = nil
        }
    }
}
