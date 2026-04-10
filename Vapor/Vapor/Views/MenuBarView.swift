import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(spacing: 0) {
            Button("Show Vapor") {
                WindowManager.shared.expand()
            }
            Divider()
            Button("Settings...") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            Divider()
            Button("Quit Vapor") {
                NSApp.terminate(nil)
            }
        }
    }
}

extension Notification.Name {
    static let showSettings = Notification.Name("showSettings")
    static let toggleWindowState = Notification.Name("toggleWindowState")
}