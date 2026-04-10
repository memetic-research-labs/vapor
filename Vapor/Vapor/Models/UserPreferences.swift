import Foundation

@MainActor
@Observable
final class UserPreferences {
    var windowState: WindowState {
        didSet { UserDefaults.standard.set(windowState == .expanded, forKey: Keys.windowExpanded) }
    }
    var autoCompressEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCompressEnabled, forKey: Keys.autoCompress) }
    }
    var autoMinimizeEnabled: Bool {
        didSet { UserDefaults.standard.set(autoMinimizeEnabled, forKey: Keys.autoMinimize) }
    }

    struct Keys {
        static let windowExpanded = "windowExpanded"
        static let autoCompress = "autoCompressEnabled"
        static let autoMinimize = "autoMinimizeEnabled"
        static let windowPositionX = "windowPositionX"
        static let windowPositionY = "windowPositionY"
    }

    init() {
        let hasPreference = UserDefaults.standard.object(forKey: Keys.windowExpanded) != nil
        self.windowState = hasPreference ? (UserDefaults.standard.bool(forKey: Keys.windowExpanded) ? .expanded : .minimized) : .expanded
        self.autoCompressEnabled = UserDefaults.standard.object(forKey: Keys.autoCompress) as? Bool ?? false
        self.autoMinimizeEnabled = UserDefaults.standard.object(forKey: Keys.autoMinimize) as? Bool ?? false
    }

    func saveWindowPosition(_ point: CGPoint) {
        UserDefaults.standard.set(point.x, forKey: Keys.windowPositionX)
        UserDefaults.standard.set(point.y, forKey: Keys.windowPositionY)
    }

    func loadWindowPosition() -> CGPoint? {
        let x = UserDefaults.standard.double(forKey: Keys.windowPositionX)
        let y = UserDefaults.standard.double(forKey: Keys.windowPositionY)
        if x == 0 && y == 0 { return nil }
        return CGPoint(x: x, y: y)
    }
}