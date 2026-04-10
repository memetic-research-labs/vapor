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

    /// Base window configuration shared by both states.
    private func configureWindow(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true

        // Unified compact toolbar eliminates the separator line between title bar and content
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "vapor.main")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact
        }

        // Eliminate content border thickness on all edges
        window.setContentBorderThickness(0, for: .minY)
        window.setContentBorderThickness(0, for: .maxY)

        // Layer-backed content view for smoother resize rendering, zero out any layer borders
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.borderWidth = 0
        window.contentView?.layer?.borderColor = nil
    }

    func expand() {
        windowState = .expanded
        preferences.windowState = .expanded

        guard let window = findWindow() else {
            logger.warning("expand: no window found")
            return
        }

        configureWindow(window)

        // Expanded: show title bar with "Vapor", opaque background matching content
        window.titleVisibility = .visible
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true

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

        configureWindow(window)

        // Minimized: hide title bar, transparent background for pill material
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false

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
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleState() {
        switch windowState {
        case .minimized: expand()
        case .expanded: minimize()
        }
    }

    /// Bring the window to front and focus it without changing state.
    func focus() {
        guard let window = findWindow() else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
            window.isOpaque = false

            let currentFrame = window.frame
            let pillOrigin = NSPoint(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + currentFrame.height - minimizedSize.height
            )
            window.setFrame(NSRect(origin: pillOrigin, size: minimizedSize), display: true)
        } else {
            window.titleVisibility = .visible
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
        }
    }
}
