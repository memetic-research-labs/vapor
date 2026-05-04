import SwiftUI

/// A reusable sheet/panel that handles OpenRouter OAuth configuration.
/// Launched from onboarding, Settings > Cloud, and the sidebar button.
struct OpenRouterConfigView: View {

    // The caller can pass a closure that fires after a key is successfully saved.
    var onKeyChanged: ((String) -> Void)? = nil

    private let oauthService = OpenRouterOAuthService.shared
    @State private var showManualEntry = false
    @State private var manualKeyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerRow

            Divider()

            stateContent
        }
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.indigo)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenRouter")
                    .font(.system(size: 15, weight: .semibold))
                Text("Cloud LLM for compression, extraction & summarization")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - State content

    @ViewBuilder
    private var stateContent: some View {
        switch oauthService.state {
        case .idle:
            notConnectedContent
        case .inProgress:
            inProgressContent
        case .connected:
            connectedContent
        case .error(let message):
            errorContent(message)
        }
    }

    // MARK: - Not connected

    private var notConnectedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBadge(color: .orange, label: "Not connected")

            Button {
                Task { await triggerOAuth() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                    Text("Connect OpenRouter")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if showManualEntry {
                manualEntrySection
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showManualEntry = true }
                } label: {
                    Text("Or paste an API key manually…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Opens a system browser window to sign in with OpenRouter. No password is stored — only the resulting API key.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - In progress

    private var inProgressContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Waiting for authorization…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }

    // MARK: - Connected

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBadge(color: .green, label: "Connected")

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("API key saved")
                        .font(.system(size: 12, weight: .medium))
                    Text(maskedKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    oauthService.disconnect()
                    onKeyChanged?("")
                } label: {
                    Text("Disconnect")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                Task { await triggerOAuth() }
            } label: {
                Text("Reconnect / refresh key")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Error

    private func errorContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await triggerOAuth() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Manual entry

    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("sk-or-v1-…", text: $manualKeyDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button {
                    let key = manualKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { return }
                    oauthService.saveManualKey(key)
                    onKeyChanged?(key)
                    showManualEntry = false
                    manualKeyDraft = ""
                } label: {
                    Text("Save")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manualKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    withAnimation { showManualEntry = false; manualKeyDraft = "" }
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Shared UI helpers

    private func statusBadge(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
        }
    }

    private var maskedKey: String {
        let key = oauthService.apiKey
        guard key.count > 12 else {
            return String(repeating: "•", count: key.count)
        }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }

    // MARK: - OAuth trigger

    @MainActor
    private func triggerOAuth() async {
        guard let window = NSApplication.shared.keyWindow else { return }
        await oauthService.connect(presentationAnchor: window)
        if oauthService.isConnected {
            onKeyChanged?(oauthService.apiKey)
        }
    }
}
