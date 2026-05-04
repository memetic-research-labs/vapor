import SwiftUI
import SwiftData

struct SessionListView: View {
    let sessions: [AISession]
    let onSelectSession: (UUID) -> Void

    private let cardBackground = Color(nsColor: .controlBackgroundColor)

    var body: some View {
        if sessions.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("No AI sessions captured yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Sessions are captured automatically when you use AI coding tools.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
                .padding()
            }
        }
    }

    private func sessionRow(_ session: AISession) -> some View {
        Button {
            onSelectSession(session.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    toolBadge(session.tool)
                }

                HStack(spacing: 12) {
                    Label("\(session.totalTurns) turns", systemImage: "text.bubble")
                    if let branch = session.branchName {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                    Label(formattedDate(session.startedAt), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !session.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(session.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                        if session.tags.count > 4 {
                            Text("+\(session.tags.count - 4)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(12)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }
}
