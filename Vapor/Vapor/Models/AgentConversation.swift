import Foundation
import SwiftData

@Model
final class AgentConversation {
    var id: UUID
    var sourceID: String
    var source: String
    var parentSourceID: String?
    var projectSourceID: String?
    var directory: String
    var title: String
    var slug: String?
    var version: String?
    var summaryFiles: Int?
    var summaryAdditions: Int?
    var summaryDeletions: Int?
    var timeCreated: Date
    var timeUpdated: Date
    var lastImportedAt: Date?

    init(
        sourceID: String,
        source: String,
        parentSourceID: String? = nil,
        projectSourceID: String? = nil,
        directory: String,
        title: String,
        slug: String? = nil,
        version: String? = nil,
        summaryFiles: Int? = nil,
        summaryAdditions: Int? = nil,
        summaryDeletions: Int? = nil,
        timeCreated: Date,
        timeUpdated: Date
    ) {
        self.id = UUID()
        self.sourceID = sourceID
        self.source = source
        self.parentSourceID = parentSourceID
        self.projectSourceID = projectSourceID
        self.directory = directory
        self.title = title
        self.slug = slug
        self.version = version
        self.summaryFiles = summaryFiles
        self.summaryAdditions = summaryAdditions
        self.summaryDeletions = summaryDeletions
        self.timeCreated = timeCreated
        self.timeUpdated = timeUpdated
        self.lastImportedAt = nil
    }

    var projectDisplayName: String {
        (directory as NSString).lastPathComponent
    }

    var diffSummary: String? {
        guard let files = summaryFiles, files > 0 else { return nil }
        let adds = summaryAdditions ?? 0
        let dels = summaryDeletions ?? 0
        return "+\(adds)/-\(dels) in \(files) files"
    }
}
