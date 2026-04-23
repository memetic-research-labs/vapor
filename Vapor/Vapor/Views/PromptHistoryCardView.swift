import SwiftUI
import SwiftData

struct PromptHistoryCardView: View {
    let record: PromptRecord
    let onRestore: (PromptRecord) -> Void
    let onToggleFavorite: (PromptRecord) -> Void
    let onDelete: (PromptRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Original text (truncated)
            Text(record.originalText)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Compressed text
            Text(record.compressedText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats row
            HStack(spacing: 6) {
                Text(String(format: "%.2f ratio", record.compressionRatio))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)

                Text("\u{00B7}")
                    .foregroundColor(.secondary)

                Text("\(record.originalTokenCount) \u{2192} \(record.compressedTokenCount) tokens")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("\u{00B7}")
                    .foregroundColor(.secondary)

                Text(record.compressorUsed)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(record.shortHash)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())

                Spacer()

                Text(formattedTime)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))

                // Favorite toggle
                Button(action: { onToggleFavorite(record) }, label: {
                    Image(systemName: record.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundColor(record.isFavorite ? .yellow : .secondary.opacity(0.5))
                })
                .buttonStyle(.borderless)

                // Delete
                Button(action: { onDelete(record) }, label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                })
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onRestore(record) }
    }

    private var formattedTime: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(record.modifiedAt) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(record.modifiedAt) {
            formatter.dateFormat = "'Yesterday' h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: record.modifiedAt)
    }
}
