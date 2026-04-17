import AppKit
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "WindowManager")

@MainActor
@Observable
final class WindowManager {
    static private(set) var shared = WindowManager(preferences: UserPreferences())

    /// Call once at app startup to inject the shared UserPreferences instance.
    static func configure(preferences: UserPreferences) {
        shared = WindowManager(preferences: preferences)
    }

    var windowState: WindowState {
        didSet { logger.debug("Window state: \(self.windowState == .minimized ? "minimized" : "expanded")") }
    }

    private let preferences: UserPreferences
    private let expandedSize = CGSize(width: 683, height: 540)
    private let minimizedSize = CGSize(width: 320, height: 200)
    private let contextTrayWidth: CGFloat = 261
    private let testSidebarWidth: CGFloat = 351

    private init(preferences: UserPreferences) {
        self.preferences = preferences
        // Restore last window state from preferences
        self.windowState = preferences.windowState
    }

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
        expand(showContextTray: false, showTestSidebar: false)
    }

    func expand(showContextTray: Bool, showTestSidebar: Bool) {
        windowState = .expanded
        preferences.windowState = .expanded

        guard let window = findWindow() else {
            logger.warning("expand: no window found")
            return
        }

        configureWindow(window)

        window.titleVisibility = .visible
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true

        let targetFrame = expandedFrame(
            from: window.frame,
            for: window,
            showContextTray: showContextTray,
            showTestSidebar: showTestSidebar
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
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

        // Minimized: opaque title bar with "Vapor" title visible
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbar = nil
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

    func resizeForPanels(showContextTray: Bool, showTestSidebar: Bool) {
        guard let window = findWindow(), windowState == .expanded else { return }
        let targetFrame = expandedFrame(
            from: window.frame,
            for: window,
            showContextTray: showContextTray,
            showTestSidebar: showTestSidebar
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func expandedFrame(from currentFrame: NSRect, for window: NSWindow, showContextTray: Bool, showTestSidebar: Bool) -> NSRect {
        let targetWidth = expandedSize.width
            + (showContextTray ? contextTrayWidth : 0)
            + (showTestSidebar ? testSidebarWidth : 0)
        let targetHeight = expandedSize.height
        let topEdge = currentFrame.origin.y + currentFrame.height
        var originX = currentFrame.origin.x

        if let screen = window.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            originX = min(originX, visibleFrame.maxX - targetWidth)
            originX = max(originX, visibleFrame.minX)
        }

        return NSRect(
            x: originX,
            y: topEdge - targetHeight,
            width: targetWidth,
            height: targetHeight
        )
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
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.toolbar = nil
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
            let targetFrame = expandedFrame(
                from: window.frame,
                for: window,
                showContextTray: false,
                showTestSidebar: false
            )
            window.setFrame(targetFrame, display: true)
        }
    }
}
