import SwiftUI
import AppKit
import AVFoundation
import Speech

struct PermissionsOverlayView: View {
    let speechStatus: SFSpeechRecognizerAuthorizationStatus
    let micStatus: AVAuthorizationStatus
    let onRetry: () -> Void

    private var speechDenied: Bool {
        speechStatus == .denied || speechStatus == .restricted
    }

    private var micDenied: Bool {
        micStatus == .denied || micStatus == .restricted
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Permissions Required")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                if micDenied {
                    permissionRow(
                        icon: "mic.slash",
                        title: "Microphone Access Denied",
                        description: "Vapor needs microphone access for voice dictation."
                    )
                }

                if speechDenied {
                    permissionRow(
                        icon: "text.bubble.fill",
                        title: "Speech Recognition Denied",
                        description: "Vapor needs speech recognition to transcribe your voice."
                    )
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 10) {
                Button(action: openSystemSettings) {
                    Label("Open System Settings", systemImage: "gear")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Text("After granting permissions in System Settings, click Retry.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func permissionRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.red)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func openSystemSettings() {
        let urls: [String] = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        ]

        for urlString in urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                break
            }
        }
    }
}
