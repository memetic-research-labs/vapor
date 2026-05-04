import Foundation
import SwiftData

@Model
final class AISession {
    var id: UUID
    var title: String
    var tool: String
    var projectPath: String?
    var projectName: String?
    var branchName: String?
    var prNumber: Int?
    var startedAt: Date
    var endedAt: Date?
    var tags: [String]
    var isArchived: Bool
    var gitCommitSHA: String?
    var embeddingID: String?

    var summaryAbstract: String?
    var summaryKeyPointsData: Data?

    var totalTokensEstimated: Int
    var totalTurns: Int
    var totalAttachedImages: Int
    var totalAttachedURLs: Int

    var project: VaporProject?

    @Relationship(deleteRule: .cascade, inverse: \AITurn.session)
    var turns: [AITurn] = []

    @Relationship(deleteRule: .nullify, inverse: \ImageAsset.aiSession)
    var attachedImages: [ImageAsset] = []

    @Relationship(deleteRule: .cascade, inverse: \AISessionEntityLink.session)
    var entityLinks: [AISessionEntityLink] = []

    @Relationship(deleteRule: .cascade, inverse: \AIGitExportRecord.session)
    var exportRecords: [AIGitExportRecord] = []

    init(
        title: String,
        tool: String,
        projectPath: String? = nil,
        projectName: String? = nil,
        branchName: String? = nil,
        prNumber: Int? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.tool = tool
        self.projectPath = projectPath
        self.projectName = projectName
        self.branchName = branchName
        self.prNumber = prNumber
        self.startedAt = Date()
        self.endedAt = nil
        self.tags = []
        self.isArchived = false
        self.gitCommitSHA = nil
        self.embeddingID = nil
        self.summaryAbstract = nil
        self.summaryKeyPointsData = nil
        self.totalTokensEstimated = 0
        self.totalTurns = 0
        self.totalAttachedImages = 0
        self.totalAttachedURLs = 0
    }
}
