import SwiftUI

struct ActivityLogView: View {
    @Environment(StatusBarService.self) private var statusBar

    @State private var selectedDomain: StatusEventDomain?
    @State private var errorsOnly = false

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var filteredEvents: [StatusEvent] {
        statusBar.events.reversed().filter { event in
            let matchesDomain = selectedDomain == nil || event.domain == selectedDomain
            let matchesLevel = !errorsOnly || event.level == .error
            return matchesDomain && matchesLevel
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()

            if filteredEvents.isEmpty {
                emptyState
            } else {
                List(filteredEvents) { event in
                    ActivityLogRow(event: event, timestampFormatter: Self.timestampFormatter)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 700, minHeight: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity Log")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(filteredEvents.count) events shown")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Clear") {
                statusBar.clearEvents()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Domain", selection: $selectedDomain) {
                Text("All").tag(Optional<StatusEventDomain>.none)
                ForEach(StatusEventDomain.allCases) { domain in
                    Text(domain.rawValue).tag(Optional(domain))
                }
            }
            .pickerStyle(.segmented)

            Toggle("Errors only", isOn: $errorsOnly)
                .toggleStyle(.switch)
                .controlSize(.small)
                .frame(width: 110)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.append")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No activity yet")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Context processing, browser activity, compression, and vectorization events will appear here.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityLogRow: View {
    let event: StatusEvent
    let timestampFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(timestampFormatter.string(from: event.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(event.domain.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(domainColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(domainColor.opacity(0.12))
                    .clipShape(Capsule())

                Text(event.message)
                    .font(.system(size: 12))

                Spacer()

                Image(systemName: levelSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(levelColor)
            }

            if !event.metadata.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(event.metadata.keys.sorted(), id: \.self) { key in
                        if let value = event.metadata[key] {
                            HStack(spacing: 4) {
                                Text("\(key):")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(value)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.leading, 72)
            }
        }
        .padding(.vertical, 4)
    }

    private var levelSymbol: String {
        switch event.level {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var levelColor: Color {
        switch event.level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private var domainColor: Color {
        switch event.domain {
        case .browser: .blue
        case .compression: .purple
        case .context: .orange
        case .system: .secondary
        case .vectorization: .green
        }
    }
}
