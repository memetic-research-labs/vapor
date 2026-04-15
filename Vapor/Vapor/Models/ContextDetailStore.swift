import Foundation

@Observable
final class ContextDetailStore {
    static let shared = ContextDetailStore()

    var selectedItemID: UUID = UUID()

    private init() {}
}
