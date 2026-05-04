import SwiftUI

struct MenuBarView: View {
    @State private var facade = SessionCaptureFacade.shared

    var body: some View {
        VStack(spacing: 0) {
            if facade.isCapturing || facade.isPaused {
                HStack {
                    Circle()
                        .fill(facade.isPaused ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(facade.isPaused ? "Capture Paused" : "Capturing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if facade.isPaused {
                    Button {
                        facade.isPaused = false
                        StatusBarService.shared.log("Session capture resumed", domain: .system, level: .success)
                    } label: {
                        Label("Resume Capture", systemImage: "play.fill")
                    }
                } else {
                    Button {
                        facade.isPaused = true
                        StatusBarService.shared.log("Session capture paused", domain: .system, level: .warning)
                    } label: {
                        Label("Pause Capture", systemImage: "pause.fill")
                    }
                }

                Button {
                    Task {
                        await facade.stopAll()
                    }
                } label: {
                    Label("Stop Capture", systemImage: "stop.fill")
                }

                Divider()
            }

            Button {
                WindowManager.shared.focus()
            } label: {
                Label("Show Vapor", systemImage: "macwindow")
            }

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gearshape")
            }

            Divider()

            Button("Quit Vapor") {
                NSApp.terminate(nil)
            }
        }
    }
}
