import SwiftUI

struct CaptureOnboardingView: View {
    @Binding var sessionCaptureEnabled: Bool
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("AI Session Capture")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                Label("Captures conversations from AI coding tools automatically", systemImage: "bubble.left.and.text.bubble.right")
                Label("Extracts entities, tags, and links per turn", systemImage: "sparkles")
                Label("Stores embeddings for semantic search", systemImage: "magnifyingglass")
                Label("Exports to git with automatic redaction", systemImage: "shield.lefthalf.filled")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Captured sessions are stored locally and never leave your machine unless you explicitly export them.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Not Now") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enable Capture") {
                    sessionCaptureEnabled = true
                    UserDefaults.standard.set(true, forKey: "sessionCaptureEnabled")
                    UserDefaults.standard.set(true, forKey: "sessionCaptureOnboarded")
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 400)
    }
}
