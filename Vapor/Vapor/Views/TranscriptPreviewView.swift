import SwiftUI

struct TranscriptPreviewView: View {
    @State private var store = TranscriptStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "text.quote")
                    .foregroundColor(.secondary)
                Text("Captured Text")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(wordCount) words")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Text("No text captured yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Start dictating or type in the main window")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    Text(store.text)
                        .font(.system(size: 13, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
        .frame(minWidth: 280, minHeight: 150)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var wordCount: Int {
        store.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
}
