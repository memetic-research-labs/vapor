import Foundation
import SwiftData

@Model
final class AgentTurn {
    var id: UUID
    var sourceID: String
    var source: String
    var conversationSourceID: String
    var role: String
    var agent: String?
    var mode: String?
    var modelID: String?
    var providerID: String?
    var cost: Double?
    var tokensInput: Int?
    var tokensOutput: Int?
    var tokensReasoning: Int?
    var tokensCacheRead: Int?
    var tokensCacheWrite: Int?
    var pathCwd: String?
    var pathRoot: String?
    var finishReason: String?
    var timeCreated: Date
    var timeCompleted: Date?
    var embeddingID: String?

    init(
        sourceID: String,
        source: String,
        conversationSourceID: String,
        role: String,
        agent: String? = nil,
        mode: String? = nil,
        modelID: String? = nil,
        providerID: String? = nil,
        cost: Double? = nil,
        tokensInput: Int? = nil,
        tokensOutput: Int? = nil,
        tokensReasoning: Int? = nil,
        tokensCacheRead: Int? = nil,
        tokensCacheWrite: Int? = nil,
        pathCwd: String? = nil,
        pathRoot: String? = nil,
        finishReason: String? = nil,
        timeCreated: Date,
        timeCompleted: Date? = nil
    ) {
        self.id = UUID()
        self.sourceID = sourceID
        self.source = source
        self.conversationSourceID = conversationSourceID
        self.role = role
        self.agent = agent
        self.mode = mode
        self.modelID = modelID
        self.providerID = providerID
        self.cost = cost
        self.tokensInput = tokensInput
        self.tokensOutput = tokensOutput
        self.tokensReasoning = tokensReasoning
        self.tokensCacheRead = tokensCacheRead
        self.tokensCacheWrite = tokensCacheWrite
        self.pathCwd = pathCwd
        self.pathRoot = pathRoot
        self.finishReason = finishReason
        self.timeCreated = timeCreated
        self.timeCompleted = timeCompleted
        self.embeddingID = nil
    }

    var totalTokens: Int? {
        let components = [tokensInput, tokensOutput, tokensReasoning].compactMap { $0 }
        guard !components.isEmpty else { return nil }
        return components.reduce(0, +)
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
}
