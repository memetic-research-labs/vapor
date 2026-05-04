import Foundation
import SwiftData

@Model
final class VaporProject {
    var id: UUID
    var name: String
    var notes: String?

    var gitLocalPath: String?
    var gitRemoteURL: String?
    var gitCurrentBranch: String?
    var detectedPRNumber: Int?

    var colorHex: String?
    var sortOrder: Int

    var createdAt: Date
    var lastActiveAt: Date

    @Relationship(deleteRule: .nullify, inverse: \ContextItem.project)
    var contextItems: [ContextItem] = []

    @Relationship(deleteRule: .nullify, inverse: \PromptRecord.project)
    var promptRecords: [PromptRecord] = []

    @Relationship(deleteRule: .nullify, inverse: \AISession.project)
    var sessions: [AISession] = []

    @Relationship(deleteRule: .nullify, inverse: \ImageAsset.project)
    var imageAssets: [ImageAsset] = []

    @Relationship(deleteRule: .cascade, inverse: \VaporProjectBookmark.bookmark)
    var bookmarks: [VaporProjectBookmark] = []

    init(
        name: String,
        notes: String? = nil,
        gitLocalPath: String? = nil,
        gitRemoteURL: String? = nil,
        gitCurrentBranch: String? = nil,
        detectedPRNumber: Int? = nil,
        colorHex: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.gitLocalPath = gitLocalPath
        self.gitRemoteURL = gitRemoteURL
        self.gitCurrentBranch = gitCurrentBranch
        self.detectedPRNumber = detectedPRNumber
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }
}
