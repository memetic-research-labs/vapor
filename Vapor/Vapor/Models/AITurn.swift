import Foundation
import SwiftData

@Model
final class AITurn {
    var id: UUID
    var turnIndex: Int
    var role: String
    var content: String
    var contentTokenCount: Int
    var capturedAt: Date
    var embeddingID: String?

    var modelID: String?
    var toolName: String?
    var attachedImageIDs: [String]
    var attachedURLs: [String]
    var durationSeconds: Double?
    var isEdited: Bool
    var isRedacted: Bool

    var session: AISession?

    @Relationship(deleteRule: .cascade, inverse: \AITurnEntityLink.turn)
    var entityLinks: [AITurnEntityLink] = []

    init(
        role: String,
        content: String,
        turnIndex: Int,
        capturedAt: Date = Date(),
        contentTokenCount: Int = 0,
        modelID: String? = nil,
        toolName: String? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.turnIndex = turnIndex
        self.capturedAt = capturedAt
        self.contentTokenCount = contentTokenCount
        self.embeddingID = nil
        self.modelID = modelID
        self.toolName = toolName
        self.attachedImageIDs = []
        self.attachedURLs = []
        self.durationSeconds = durationSeconds
        self.isEdited = false
        self.isRedacted = false
    }
}
