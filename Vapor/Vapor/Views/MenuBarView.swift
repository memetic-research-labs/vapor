import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(spacing: 0) {
            Button("Show Vapor") {
                WindowManager.shared.focus()
            }
            Divider()
            SettingsLink {
                Text("Settings...")
            }
            Divider()
            Button("Quit Vapor") {
                NSApp.terminate(nil)
            }
        }
    }
}
