import Foundation
import SwiftData

enum TurnContentKind: String, Codable, Sendable {
    case text
    case tool
    case reasoning
    case patch
    case file
    case compaction
    case stepStart = "step-start"
    case stepFinish = "step-finish"
    case unknown
}

@Model
final class TurnContent {
    var id: UUID
    var sourceID: String
    var source: String
    var turnSourceID: String
    var conversationSourceID: String
    var kind: String
    var textContent: String?
    var toolName: String?
    var toolStatus: String?
    var toolTitle: String?
    var toolInput: String?
    var toolOutput: String?
    var patchFiles: [String]?
    var fileMime: String?
    var fileFilename: String?
    var fileURL: String?
    var timeCreated: Date
    var embeddingID: String?

    init(
        sourceID: String,
        source: String,
        turnSourceID: String,
        conversationSourceID: String,
        kind: String,
        textContent: String? = nil,
        toolName: String? = nil,
        toolStatus: String? = nil,
        toolTitle: String? = nil,
        toolInput: String? = nil,
        toolOutput: String? = nil,
        patchFiles: [String]? = nil,
        fileMime: String? = nil,
        fileFilename: String? = nil,
        fileURL: String? = nil,
        timeCreated: Date
    ) {
        self.id = UUID()
        self.sourceID = sourceID
        self.source = source
        self.turnSourceID = turnSourceID
        self.conversationSourceID = conversationSourceID
        self.kind = kind
        self.textContent = textContent
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.toolTitle = toolTitle
        self.toolInput = toolInput
        self.toolOutput = toolOutput
        self.patchFiles = patchFiles
        self.fileMime = fileMime
        self.fileFilename = fileFilename
        self.fileURL = fileURL
        self.timeCreated = timeCreated
        self.embeddingID = nil
    }

    var typedKind: TurnContentKind {
        TurnContentKind(rawValue: kind) ?? .unknown
    }

    var isText: Bool { kind == TurnContentKind.text.rawValue }
    var isTool: Bool { kind == TurnContentKind.tool.rawValue }
    var isReasoning: Bool { kind == TurnContentKind.reasoning.rawValue }
}
