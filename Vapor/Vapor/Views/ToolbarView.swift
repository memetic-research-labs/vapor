import SwiftUI

struct ToolbarView: View {
    @Bindable var viewModel: EditorViewModel
    let preferences: UserPreferences
    let workspace: AppWorkspace
    let isContextTrayVisible: Bool
    let onCompressAndCopy: () async -> Void
    let onCopyOriginal: () -> Void
    let onShowHistory: () -> Void
    let onSelectWorkspace: (AppWorkspace) -> Void
    let onOpenExperiments: () -> Void
    let onToggleContextTray: () -> Void
    let onMinimize: () -> Void

    var body: some View {
        ZStack {
            workspaceSwitcher

            HStack(spacing: 12) {
                leftGroup
                Spacer(minLength: 24)
                rightGroup
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 46)
        .background(.bar)
    }

    @ViewBuilder
    private var leftGroup: some View {
        HStack(spacing: 8) {
            if workspace == .compose {
                Button {
                    Task { await onCompressAndCopy() }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isCompressing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "bolt.horizontal")
                        }
                        Text("Compress & Copy")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(viewModel.content.isEmpty ? 0.08 : 0.14))
                    .foregroundColor(viewModel.content.isEmpty ? .secondary : .accentColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.accentColor.opacity(viewModel.content.isEmpty ? 0.08 : 0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.content.isEmpty || viewModel.isCompressing)
            }
        }
    }

    private var workspaceSwitcher: some View {
        Group {
            if preferences.researchToolsEnabled {
                Picker("Workspace", selection: Binding(
                    get: { workspace },
                    set: onSelectWorkspace
                )) {
                    ForEach(AppWorkspace.allCases) { workspace in
                        Text(workspace.rawValue).tag(workspace)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            } else {
                Text("Compose")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var rightGroup: some View {
        HStack(spacing: 8) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)

            Menu {
                if workspace == .compose {
                    Button("Copy Original", action: onCopyOriginal)
                        .disabled(viewModel.content.isEmpty)
                    Button("Prompt History", action: onShowHistory)
                    Divider()
                }
                if preferences.showExperimentsButton {
                    Button("OpenRouter Test", action: onOpenExperiments)
                }
                Button("Minimize to Compact", action: onMinimize)
            } label: {
                Text("Window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.06))
                    )
            }
            .menuStyle(.borderlessButton)
            .help("More window actions")

            if workspace == .compose {
                Button {
                    onToggleContextTray()
                } label: {
                    Text("Context")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isContextTrayVisible ? .accentColor : .primary)
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isContextTrayVisible ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isContextTrayVisible ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.14), lineWidth: 1)
                )
                .help("Toggle context tray")
            }
        }
    }
}
