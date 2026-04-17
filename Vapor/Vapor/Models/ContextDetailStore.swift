import Foundation

struct ContextItemDetailPayload: Identifiable, Hashable, Codable {
    let id: String
    let itemID: UUID

    init(itemID: UUID) {
        self.id = itemID.uuidString
        self.itemID = itemID
    }
}

@Observable
final class ContextDetailStore {
    static let shared = ContextDetailStore()

    var selectedItemID: UUID = UUID()

    private init() {}
}
