import Foundation

struct AgentSessionPayload: Identifiable, Hashable, Codable {
    let id: String
    let sourceID: String

    init(sourceID: String) {
        self.id = sourceID
        self.sourceID = sourceID
    }
}
