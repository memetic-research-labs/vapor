import SwiftUI

struct StatsBarView: View {
    let originalTokens: Int
    let compressedTokens: Int
    let ratio: Double

    var body: some View {
        HStack {
            Label {
                Text(String(format: "%.2f", ratio))
            } icon: {
                Image(systemName: "chart.bar.fill")
            }
            .font(.system(size: 12, weight: .medium))

            Spacer()

            Text("Tokens: \(originalTokens) → \(compressedTokens)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Text("Saved: \(originalTokens - compressedTokens)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ratioColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
    }

    private var ratioColor: Color {
        if ratio < 0.5 {
            return .green
        } else if ratio < 0.7 {
            return .orange
        } else {
            return .red
        }
    }
}