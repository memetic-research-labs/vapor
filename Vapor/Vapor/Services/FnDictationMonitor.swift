import Foundation
import AppKit
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Dictation")

final class FnDictationMonitor {
    static let shared = FnDictationMonitor()

    private var localMonitor: Any?
    private var callback: ((Bool) -> Void)?
    private var lastFnState = false

    private init() {}

    func start(callback: @escaping (Bool) -> Void) {
        self.callback = callback

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

        logger.debug("Started monitoring (local only — sandbox-compatible)")
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        callback = nil
        logger.debug("Stopped monitoring")
    }

    /// Temporarily pause monitoring without forgetting the callback (used by the onboarding window).
    func pauseForOnboarding() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        // callback is preserved so resumeAfterOnboarding() can restart
        logger.debug("Paused monitoring for onboarding")
    }

    /// Restart monitoring using the callback that was active before `pauseForOnboarding()`.
    func resumeAfterOnboarding() {
        guard let callback else {
            logger.debug("No saved callback — skipping resume")
            return
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
        lastFnState = false
        logger.debug("Resumed monitoring after onboarding")
        // Surface a "key up" so the main app is not stuck thinking Fn is held
        callback(false)
    }

    private func handleEvent(_ event: NSEvent) {
        let isFnDown = event.modifierFlags.contains(.function)

        if isFnDown != lastFnState {
            lastFnState = isFnDown
            logger.debug("Fn key \(isFnDown ? "pressed" : "released")")
            callback?(isFnDown)
        }
    }
}