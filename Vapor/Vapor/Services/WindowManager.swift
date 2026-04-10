import AppKit
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "WindowManager")

@MainActor
@Observable
final class WindowManager {
    static let shared = WindowManager()

    var windowState: WindowState = .expanded {
        didSet { logger.debug("Window state: \(self.windowState == .minimized ? "minimized" : "expanded")") }
    }

    private let preferences = UserPreferences()
    private let expandedSize = CGSize(width: 500, height: 400)
    private let minimizedSize = CGSize(width: 320, height: 200)

    private init() {}

    private func findWindow() -> NSWindow? {
        let windows = NSApplication.shared.windows
        return windows.first(where: { $0.title == "Vapor" || $0.identifier?.rawValue == "main" })
            ?? NSApplication.shared.keyWindow
            ?? windows.first(where: { $0.isVisible && $0.canBecomeKey })
    }

    private func configureWindow(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
    }

    func expand() {
        windowState = .expanded
        preferences.windowState = .expanded

        guard let window = findWindow() else {
            logger.warning("expand: no window found")
            return
        }

        configureWindow(window)

        let screen = window.screen ?? NSScreen.main!
        let screenFrame = screen.visibleFrame

        var targetOrigin: NSPoint
        if let saved = preferences.loadWindowPosition() {
            targetOrigin = NSPoint(
                x: saved.x,
                y: screenFrame.maxY - saved.y - expandedSize.height
            )
        } else {
            targetOrigin = NSPoint(
                x: screenFrame.minX + 20,
                y: screenFrame.maxY - expandedSize.height - 200
            )
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(NSRect(origin: targetOrigin, size: expandedSize), display: true)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func minimize() {
        windowState = .minimized
        preferences.windowState = .minimized

        guard let window = findWindow() else {
            logger.warning("minimize: no window found")
            return
        }

        let screen = window.screen ?? NSScreen.main!
        let screenFrame = screen.visibleFrame

        let pillOrigin = NSPoint(
            x: screenFrame.minX + 16,
            y: screenFrame.maxY - minimizedSize.height - 200
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(NSRect(origin: pillOrigin, size: minimizedSize), display: true)
        }

        window.makeKeyAndOrderFront(nil)
    }

    func toggleState() {
        switch windowState {
        case .minimized: expand()
        case .expanded: minimize()
        }
    }

    func savePosition() {
        guard let window = findWindow() else { return }
        let screen = window.screen ?? NSScreen.main!
        let screenFrame = screen.visibleFrame
        let point = CGPoint(
            x: window.frame.origin.x,
            y: screenFrame.maxY - window.frame.origin.y
        )
        preferences.saveWindowPosition(point)
    }

    func setupWindowOnAppear() {
        guard let window = findWindow() else { return }
        configureWindow(window)

        if windowState == .minimized {
            let screen = window.screen ?? NSScreen.main!
            let screenFrame = screen.visibleFrame
            let pillOrigin = NSPoint(
                x: screenFrame.minX + 16,
                y: screenFrame.maxY - minimizedSize.height - 200
            )
            window.setFrame(NSRect(origin: pillOrigin, size: minimizedSize), display: true)
        }
    }
}