import Foundation

enum ContextExplorerSemanticMode: String, Codable, CaseIterable {
    case keyword
    case semantic

    var displayName: String {
        switch self {
        case .keyword: "Keyword"
        case .semantic: "Semantic"
        }
    }
}

enum ContextExplorerSection: String, Codable, CaseIterable, Identifiable {
    case overview
    case recent
    case domains
    case authors
    case entities
    case urls
    case tags
    case types
    case aiSessions
    case processing
    case failed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overview: "Overview"
        case .recent: "Recent"
        case .domains: "Domains"
        case .authors: "Authors"
        case .entities: "Entities"
        case .urls: "URLs"
        case .tags: "Tags"
        case .types: "Types"
        case .aiSessions: "AI Sessions"
        case .processing: "Processing"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .recent: "clock"
        case .domains: "globe"
        case .authors: "person.2"
        case .entities: "sparkles"
        case .urls: "link"
        case .tags: "tag"
        case .types: "square.stack.3d.up"
        case .aiSessions: "bubble.left.and.text.bubble.right"
        case .processing: "hourglass"
        case .failed: "exclamationmark.triangle"
        }
    }
}

enum ContextExplorerSortMode: String, Codable, CaseIterable {
    case newestFirst
    case oldestFirst
    case titleAZ

    var displayName: String {
        switch self {
        case .newestFirst: "Newest"
        case .oldestFirst: "Oldest"
        case .titleAZ: "Title A-Z"
        }
    }
}

private struct PersistedContextExplorerState: Codable {
    var selectedSection: ContextExplorerSection
    var searchText: String
    var selectedDomain: String?
    var selectedAuthor: String?
    var selectedEntityHash: String?
    var selectedURLHash: String?
    var selectedTag: String?
    var selectedKindRaw: String?
    var selectedProjectID: UUID?
    var selectedSessionID: UUID?
    var semanticMode: ContextExplorerSemanticMode
    var readyOnly: Bool
    var sortMode: ContextExplorerSortMode
}

@Observable
final class ContextExplorerStore {
    static let shared = ContextExplorerStore()

    private static let storageKey = "contextExplorerState.v2"

    var selectedSection: ContextExplorerSection = .overview { didSet { persist() } }
    var searchText: String = "" { didSet { persist() } }
    var selectedDomain: String? { didSet { persist() } }
    var selectedAuthor: String? { didSet { persist() } }
    var selectedEntityHash: String? { didSet { persist() } }
    var selectedURLHash: String? { didSet { persist() } }
    var selectedTag: String? { didSet { persist() } }
    var selectedKindRaw: String? { didSet { persist() } }
    var selectedProjectID: UUID? { didSet { persist() } }
    var selectedSessionID: UUID? { didSet { persist() } }
    var semanticMode: ContextExplorerSemanticMode = .keyword { didSet { persist() } }
    var readyOnly: Bool = false { didSet { persist() } }
    var sortMode: ContextExplorerSortMode = .newestFirst { didSet { persist() } }

    private var isRestoring = false

    private init() {
        restore()
    }

    var selectedKind: ContextItemKind? {
        get {
            guard let selectedKindRaw else { return nil }
            return ContextItemKind(rawValue: selectedKindRaw)
        }
        set {
            selectedKindRaw = newValue?.rawValue
        }
    }

    var hasActiveStructuredFilter: Bool {
        selectedDomain != nil
            || selectedAuthor != nil
            || selectedEntityHash != nil
            || selectedURLHash != nil
            || selectedTag != nil
            || selectedKind != nil
            || selectedProjectID != nil
    }

    var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openOverview() {
        clearPivotSelections()
        searchText = ""
        semanticMode = .keyword
        readyOnly = false
        sortMode = .newestFirst
        selectedSection = .overview
    }

    func showSection(_ section: ContextExplorerSection) {
        selectedSection = section

        switch section {
        case .overview:
            clearPivotSelections()
        case .recent, .processing, .failed:
            clearPivotSelections()
        case .domains:
            selectedDomain = nil
            clearNonDomainSelections()
        case .authors:
            selectedAuthor = nil
            clearNonAuthorSelections()
        case .entities:
            selectedEntityHash = nil
            clearNonEntitySelections()
        case .urls:
            selectedURLHash = nil
            clearNonURLSelections()
        case .tags:
            selectedTag = nil
            clearNonTagSelections()
        case .types:
            selectedKind = nil
            clearNonTypeSelections()
        case .aiSessions:
            clearPivotSelections()
            selectedSessionID = nil
        }
    }

    func focusOnURL(_ link: ContextItemURLLink) {
        selectedSection = .urls
        selectedURLHash = link.urlRecord?.urlHash
        selectedDomain = nil
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedTag = nil
        selectedKind = nil
        searchText = link.urlDisplayText
        semanticMode = .keyword
    }

    func focusOnEntity(_ link: ContextItemEntityLink) {
        selectedSection = .entities
        selectedEntityHash = link.entityRecord?.entityHash
        selectedURLHash = nil
        selectedDomain = nil
        selectedAuthor = nil
        selectedTag = nil
        selectedKind = nil
        searchText = link.displayText
        semanticMode = .keyword
    }

    func focusOnDomain(_ domain: String) {
        selectedSection = .domains
        selectedDomain = domain.lowercased()
        selectedURLHash = nil
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedTag = nil
        selectedKind = nil
        searchText = domain
        semanticMode = .keyword
    }

    func focusOnAuthor(_ author: String) {
        selectedSection = .authors
        selectedAuthor = author
        selectedDomain = nil
        selectedURLHash = nil
        selectedEntityHash = nil
        selectedTag = nil
        selectedKind = nil
        searchText = author
        semanticMode = .keyword
    }

    func focusOnTag(_ tag: String) {
        selectedSection = .tags
        selectedTag = tag
        selectedDomain = nil
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedURLHash = nil
        selectedKind = nil
        searchText = tag
        semanticMode = .keyword
    }

    func focusOnKind(_ kind: ContextItemKind) {
        selectedSection = .types
        selectedKind = kind
        selectedDomain = nil
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedURLHash = nil
        selectedTag = nil
        searchText = kind.displayName
        semanticMode = .keyword
    }

    func focusOnSession(_ sessionID: UUID) {
        selectedSection = .aiSessions
        selectedSessionID = sessionID
        clearPivotSelections()
    }

    func clearQuery() {
        searchText = ""
        semanticMode = .keyword
    }

    func clearFilters() {
        clearPivotSelections()
        readyOnly = false
        sortMode = .newestFirst
        searchText = ""
        semanticMode = .keyword
    }

    var breadcrumbs: [String] {
        var values = [selectedSection.displayName]

        if let selectedDomain {
            values.append(selectedDomain)
        } else if let selectedAuthor {
            values.append(selectedAuthor)
        } else if let selectedTag {
            values.append(selectedTag)
        } else if let selectedKind {
            values.append(selectedKind.displayName)
        }

        return values
    }

    func clearPivotSelections() {
        selectedDomain = nil
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedURLHash = nil
        selectedTag = nil
        selectedKind = nil
        selectedProjectID = nil
    }

    private func clearNonDomainSelections() {
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedURLHash = nil
        selectedTag = nil
        selectedKind = nil
        selectedProjectID = nil
    }

    private func clearNonAuthorSelections() {
        selectedDomain = nil
        selectedEntityHash = nil
        selectedURLHash = nil
        selectedTag = nil
        selectedKind = nil
        selectedProjectID = nil
    }

    private func clearNonEntitySelections() {
        selectedDomain = nil
        selectedAuthor = nil
        selectedURLHash = nil
        selectedTag = nil
        selectedKind = nil
        selectedProjectID = nil
    }

    private func clearNonURLSelections() {
        selectedDomain = nil
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedTag = nil
        selectedKind = nil
        selectedProjectID = nil
    }

    private func clearNonTagSelections() {
        selectedDomain = nil
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedURLHash = nil
        selectedKind = nil
        selectedProjectID = nil
    }

    private func clearNonTypeSelections() {
        selectedDomain = nil
        selectedAuthor = nil
        selectedEntityHash = nil
        selectedURLHash = nil
        selectedTag = nil
        selectedProjectID = nil
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let state = try? JSONDecoder().decode(PersistedContextExplorerState.self, from: data) else {
            return
        }

        isRestoring = true
        selectedSection = state.selectedSection
        searchText = state.searchText
        selectedDomain = state.selectedDomain
        selectedAuthor = state.selectedAuthor
        selectedEntityHash = state.selectedEntityHash
        selectedURLHash = state.selectedURLHash
        selectedTag = state.selectedTag
        selectedKindRaw = state.selectedKindRaw
        selectedProjectID = state.selectedProjectID
        selectedSessionID = state.selectedSessionID
        semanticMode = state.semanticMode
        readyOnly = state.readyOnly
        sortMode = state.sortMode
        isRestoring = false
    }

    private func persist() {
        guard !isRestoring else { return }

        let state = PersistedContextExplorerState(
            selectedSection: selectedSection,
            searchText: searchText,
            selectedDomain: selectedDomain,
            selectedAuthor: selectedAuthor,
            selectedEntityHash: selectedEntityHash,
            selectedURLHash: selectedURLHash,
            selectedTag: selectedTag,
            selectedKindRaw: selectedKindRaw,
            selectedProjectID: selectedProjectID,
            selectedSessionID: selectedSessionID,
            semanticMode: semanticMode,
            readyOnly: readyOnly,
            sortMode: sortMode
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
