import Foundation

enum MaxImageDimension: Int, Codable, CaseIterable, Sendable {
    case d768 = 768
    case d1024 = 1024

    var displayName: String {
        switch self {
        case .d768: "768px (balanced)"
        case .d1024: "1024px (high detail)"
        }
    }
}

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
    var showExperimentsButton: Bool {
        didSet { UserDefaults.standard.set(showExperimentsButton, forKey: Keys.showExperiments) }
    }
    var researchToolsEnabled: Bool {
        didSet { UserDefaults.standard.set(researchToolsEnabled, forKey: Keys.researchToolsEnabled) }
    }
    var autoCopyOriginalEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCopyOriginalEnabled, forKey: Keys.autoCopyOriginal) }
    }
    var browserIntegrationEnabled: Bool {
        didSet { UserDefaults.standard.set(browserIntegrationEnabled, forKey: Keys.browserIntegrationEnabled) }
    }
    var autoSendToBrowser: Bool {
        didSet { UserDefaults.standard.set(autoSendToBrowser, forKey: Keys.autoSendToBrowser) }
    }
    var autoSubmitToAI: Bool {
        didSet { UserDefaults.standard.set(autoSubmitToAI, forKey: Keys.autoSubmitToAI) }
    }
    var embeddedServerPort: Int {
        didSet {
            let clamped = max(1, min(65_535, embeddedServerPort))
            if clamped != embeddedServerPort {
                embeddedServerPort = clamped
                return
            }
            UserDefaults.standard.set(embeddedServerPort, forKey: Keys.embeddedServerPort)
        }
    }
    var maxImageDimension: MaxImageDimension {
        didSet { UserDefaults.standard.set(maxImageDimension.rawValue, forKey: Keys.maxImageDimension) }
    }

    struct Keys {
        static let windowExpanded = "windowExpanded"
        static let autoCompress = "autoCompressEnabled"
        static let autoMinimize = "autoMinimizeEnabled"
        static let showExperiments = "showExperimentsButton"
        static let researchToolsEnabled = "researchToolsEnabled"
        static let autoCopyOriginal = "autoCopyOriginalEnabled"
        static let windowPositionX = "windowPositionX"
        static let windowPositionY = "windowPositionY"
        static let browserIntegrationEnabled = "browserIntegrationEnabled"
        static let autoSendToBrowser = "autoSendToBrowser"
        static let autoSubmitToAI = "autoSubmitToAI"
        static let embeddedServerPort = "embeddedServerPort"
        static let maxImageDimension = "maxImageDimension"
    }

    init() {
        let hasPreference = UserDefaults.standard.object(forKey: Keys.windowExpanded) != nil
        self.windowState = hasPreference ? (UserDefaults.standard.bool(forKey: Keys.windowExpanded) ? .expanded : .minimized) : .expanded
        self.autoCompressEnabled = UserDefaults.standard.object(forKey: Keys.autoCompress) as? Bool ?? false
        self.autoMinimizeEnabled = UserDefaults.standard.object(forKey: Keys.autoMinimize) as? Bool ?? false
        self.showExperimentsButton = UserDefaults.standard.object(forKey: Keys.showExperiments) as? Bool ?? false
        self.researchToolsEnabled = UserDefaults.standard.object(forKey: Keys.researchToolsEnabled) as? Bool ?? false
        self.autoCopyOriginalEnabled = UserDefaults.standard.object(forKey: Keys.autoCopyOriginal) as? Bool ?? false
        self.browserIntegrationEnabled = UserDefaults.standard.object(forKey: Keys.browserIntegrationEnabled) as? Bool ?? false
        self.autoSendToBrowser = UserDefaults.standard.object(forKey: Keys.autoSendToBrowser) as? Bool ?? false
        self.autoSubmitToAI = UserDefaults.standard.object(forKey: Keys.autoSubmitToAI) as? Bool ?? false
        self.embeddedServerPort = UserDefaults.standard.object(forKey: Keys.embeddedServerPort) as? Int ?? 8766
        self.maxImageDimension = UserDefaults.standard.object(forKey: Keys.maxImageDimension)
            .flatMap { MaxImageDimension(rawValue: ($0 as? Int) ?? 0) } ?? .d768
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
