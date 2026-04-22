import Foundation

enum AppWorkspace: String, CaseIterable, Identifiable, Sendable {
    case compose = "Compose"
    case research = "Research"

    var id: String { rawValue }
}
