import Foundation
import SwiftData

@Model
final class EntityRecord {
    var id: UUID
    @Attribute(.unique) var entityHash: String
    var kindRaw: String
    var normalizedText: String
    var displayText: String
    var firstSeenAt: Date
    var lastSeenAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ContextItemEntityLink.entityRecord)
    var links: [ContextItemEntityLink] = []

    init(
        entityHash: String,
        kind: EntityKind,
        normalizedText: String,
        displayText: String,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = UUID()
        self.entityHash = entityHash
        self.kindRaw = kind.rawValue
        self.normalizedText = normalizedText
        self.displayText = displayText
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }

    var kind: EntityKind {
        get { EntityKind(rawValue: kindRaw) ?? .concept }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class ContextItemEntityLink {
    var id: UUID
    var confidence: Double
    var surfaceText: String
    var createdAt: Date

    var contextItem: ContextItem?
    var entityRecord: EntityRecord?

    init(
        confidence: Double,
        surfaceText: String,
        contextItem: ContextItem? = nil,
        entityRecord: EntityRecord? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.confidence = confidence
        self.surfaceText = surfaceText
        self.createdAt = createdAt
        self.contextItem = contextItem
        self.entityRecord = entityRecord
    }

    var entityKind: EntityKind {
        entityRecord?.kind ?? .concept
    }

    var displayText: String {
        if !surfaceText.isEmpty {
            return surfaceText
        }
        return entityRecord?.displayText ?? ""
    }
}
