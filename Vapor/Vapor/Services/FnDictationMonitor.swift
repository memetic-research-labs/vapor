import Foundation
import AppKit

final class FnDictationMonitor {
    static let shared = FnDictationMonitor()
    
    private var monitor: Any?
    private var callback: ((Bool) -> Void)?
    private var lastFnState = false
    
    private init() {}
    
    func start(callback: @escaping (Bool) -> Void) {
        self.callback = callback
        
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let isFnDown = event.modifierFlags.contains(.function)
            
            if let self, isFnDown != self.lastFnState {
                self.lastFnState = isFnDown
                print("[FnDictationMonitor] Fn key \(isFnDown ? "pressed" : "released")")
                self.callback?(isFnDown)
            }
            
            return event
        }
        
        print("[FnDictationMonitor] Started monitoring")
    }
    
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        callback = nil
        print("[FnDictationMonitor] Stopped monitoring")
    }
}
