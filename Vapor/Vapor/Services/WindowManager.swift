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

        // Grow from current position — keep the top-left corner anchored
        let currentFrame = window.frame
        let targetOrigin = NSPoint(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + currentFrame.height - expandedSize.height
        )

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

        // Keep the pill near where the window currently is, just resize in place
        let currentFrame = window.frame
        let pillOrigin = NSPoint(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + currentFrame.height - minimizedSize.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(NSRect(origin: pillOrigin, size: minimizedSize), display: true)
        }

        window.makeKeyAndOrderFront(nil)
    }

    func toggleState() {
        // Just bring window to front and activate — no repositioning
        if let window = findWindow() {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
            // Just resize to pill size, keep current position
            let currentFrame = window.frame
            let pillOrigin = NSPoint(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + currentFrame.height - minimizedSize.height
            )
            window.setFrame(NSRect(origin: pillOrigin, size: minimizedSize), display: true)
        }
    }
}