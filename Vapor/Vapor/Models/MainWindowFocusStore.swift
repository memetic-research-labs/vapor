import Foundation

enum MainWindowFocusZone: String, Codable {
    case editor
    case screenshots
    case contextTray
    case toolRail
}

@MainActor
@Observable
final class MainWindowFocusStore {
    var activeZone: MainWindowFocusZone = .editor
    var previousZone: MainWindowFocusZone?

    func focus(_ zone: MainWindowFocusZone) {
        if activeZone != zone {
            previousZone = activeZone
            activeZone = zone
        }
    }
}
