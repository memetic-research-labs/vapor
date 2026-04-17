import Foundation
import SwiftData

enum ContextURLRole: String, Codable, CaseIterable, Sendable {
    case source
    case mentioned

    var displayName: String {
        switch self {
        case .source: "Source"
        case .mentioned: "Mentioned"
        }
    }

    var sortOrder: Int {
        switch self {
        case .source: 0
        case .mentioned: 1
        }
    }
}

@Model
final class URLRecord {
    var id: UUID
    @Attribute(.unique) var urlHash: String
    var canonicalURL: String
    var domain: String
    var scheme: String
    var path: String
    var query: String?
    var firstSeenAt: Date
    var lastSeenAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ContextItemURLLink.urlRecord)
    var links: [ContextItemURLLink] = []

    init(
        urlHash: String,
        canonicalURL: String,
        domain: String,
        scheme: String,
        path: String,
        query: String? = nil,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = UUID()
        self.urlHash = urlHash
        self.canonicalURL = canonicalURL
        self.domain = domain
        self.scheme = scheme
        self.path = path
        self.query = query
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
}

@Model
final class ContextItemURLLink {
    var id: UUID
    var roleRaw: String
    var createdAt: Date

    var contextItem: ContextItem?
    var urlRecord: URLRecord?

    init(
        role: ContextURLRole,
        contextItem: ContextItem? = nil,
        urlRecord: URLRecord? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.createdAt = createdAt
        self.contextItem = contextItem
        self.urlRecord = urlRecord
    }

    var role: ContextURLRole {
        get { ContextURLRole(rawValue: roleRaw) ?? .mentioned }
        set { roleRaw = newValue.rawValue }
    }

    var urlDisplayText: String {
        urlRecord?.canonicalURL ?? ""
    }

    var domain: String {
        urlRecord?.domain ?? ""
    }
}
