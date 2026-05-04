import Foundation
import SwiftData

@Model
final class AISessionEntityLink {
    var id: UUID
    var confidence: Double
    var surfaceText: String
    var createdAt: Date

    var session: AISession?
    var entityRecord: EntityRecord?

    init(
        confidence: Double,
        surfaceText: String,
        session: AISession? = nil,
        entityRecord: EntityRecord? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.confidence = confidence
        self.surfaceText = surfaceText
        self.createdAt = createdAt
        self.session = session
        self.entityRecord = entityRecord
    }
}

@Model
final class AITurnEntityLink {
    var id: UUID
    var confidence: Double
    var surfaceText: String
    var createdAt: Date

    var turn: AITurn?
    var entityRecord: EntityRecord?

    init(
        confidence: Double,
        surfaceText: String,
        turn: AITurn? = nil,
        entityRecord: EntityRecord? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.confidence = confidence
        self.surfaceText = surfaceText
        self.createdAt = createdAt
        self.turn = turn
        self.entityRecord = entityRecord
    }
}

@Model
final class AISessionTag {
    var id: UUID
    var text: String
    var sourceRaw: String
    var confidence: Double?
    var createdAt: Date

    var session: AISession?

    init(
        text: String,
        source: String,
        confidence: Double? = nil,
        session: AISession? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.sourceRaw = source
        self.confidence = confidence
        self.createdAt = Date()
        self.session = session
    }

    var source: AISessionTagSource {
        get { AISessionTagSource(rawValue: sourceRaw) ?? .auto }
        set { sourceRaw = newValue.rawValue }
    }
}

enum AISessionTagSource: String, Codable, CaseIterable, Sendable {
    case auto
    case user
    case llm
}

@Model
final class AIGitExportRecord {
    var id: UUID
    var exportedAt: Date
    var gitCommitSHA: String
    var branchName: String
    var sessionDirPath: String
    var filesIncluded: [String]
    var totalBytes: Int
    var redactionCount: Int
    var redactedTurnIDs: [String]

    var session: AISession?

    init(
        gitCommitSHA: String,
        branchName: String,
        sessionDirPath: String,
        filesIncluded: [String] = [],
        totalBytes: Int = 0,
        redactionCount: Int = 0,
        redactedTurnIDs: [String] = [],
        session: AISession? = nil
    ) {
        self.id = UUID()
        self.exportedAt = Date()
        self.gitCommitSHA = gitCommitSHA
        self.branchName = branchName
        self.sessionDirPath = sessionDirPath
        self.filesIncluded = filesIncluded
        self.totalBytes = totalBytes
        self.redactionCount = redactionCount
        self.redactedTurnIDs = redactedTurnIDs
        self.session = session
    }
}
