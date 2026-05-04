import SwiftUI
import SwiftData

struct ExportPreviewSheet: View {
    let session: AISession
    @Binding var isPresented: Bool
    @Binding var isExporting: Bool
    @Binding var exportCompleted: Bool
    @State private var customProjectRoot: String = ""
    @State private var preview: ExportPreview?

    private let cardBackground = Color(nsColor: .controlBackgroundColor)
    private var effectiveProjectRoot: String {
        customProjectRoot.isEmpty ? (preview?.projectRoot ?? "") : customProjectRoot
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Preview")
                .font(.headline)

            if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(preview.title)
                                .font(.title3.bold())
                            Spacer()
                            toolBadge(preview.tool)
                        }

                        HStack(spacing: 12) {
                            Label("\(preview.totalTurns) turns", systemImage: "text.bubble")
                            if !preview.branchName.isEmpty {
                                Label(preview.branchName, systemImage: "arrow.triangle.branch")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if preview.redactionCount > 0 {
                            warningBox(
                                title: "Redactions",
                                message: "\(preview.redactionCount) pattern(s) will be redacted.",
                                icon: "shield.lefthalf.filled",
                                color: .orange
                            )
                        }

                        if !preview.sensitiveKeywords.isEmpty {
                            warningBox(
                                title: "Sensitive Content Detected",
                                message: "Found keywords: \(preview.sensitiveKeywords.joined(separator: ", ")). Review before exporting.",
                                icon: "exclamationmark.triangle.fill",
                                color: .red
                            )
                        }

                        if !preview.hasProjectPath && effectiveProjectRoot.isEmpty {
                            warningBox(
                                title: "No Project Path",
                                message: "Set a project root directory to export to.",
                                icon: "folder.badge.questionmark",
                                color: .yellow
                            )
                        }

                        GroupBox("Files") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(preview.estimatedFiles, id: \.self) { file in
                                    Label(file, systemImage: "doc")
                                        .font(.caption)
                                }
                            }
                            .padding(4)
                        }

                        GroupBox("Export Location") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Project root path", text: $customProjectRoot)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                if preview.hasProjectPath {
                                    Text("Detected: \(preview.projectRoot)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(4)
                        }
                    }
                }

                if exportCompleted {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Export completed successfully")
                            .foregroundStyle(.green)
                    }
                    .font(.caption)
                }

                HStack {
                    Button("Cancel") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Exporting...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Export") {
                            performExport()
                        }
                        .disabled(effectiveProjectRoot.isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                ProgressView("Calculating preview...")
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            preview = GitExportService.shared.previewExport(session)
        }
    }

    private func performExport() {
        let projectRoot = effectiveProjectRoot
        guard !projectRoot.isEmpty else { return }
        isExporting = true
        Task { @MainActor in
            do {
                _ = try await GitExportService.shared.exportSession(session, to: projectRoot)
                exportCompleted = true
                StatusBarService.shared.log("Exported session: \(session.title)", domain: .system, level: .success)
            } catch {
                StatusBarService.shared.log("Export failed: \(error.localizedDescription)", domain: .system, level: .error)
            }
            isExporting = false
        }
    }

    private func warningBox(title: String, message: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toolBadge(_ tool: String) -> some View {
        let icon = switch tool.lowercased() {
        case let val where val.contains("opencode"): "terminal"
        case let val where val.contains("cursor"): "cursorarrow"
        case let val where val.contains("claude"): "bubble.left"
        case let val where val.contains("copilot"): "sparkles"
        default: "cpu"
        }
        return Label(tool, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
    }
}
