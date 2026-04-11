import SwiftUI

struct AudioLevelView: View {
    let inputLevel: Float
    let isActive: Bool

    private let barCount = 5
    private let maxHeight: CGFloat = 14
    private let minHeight: CGFloat = 3
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(for: index))
                    .frame(width: barWidth, height: barHeight(for: index))
            }
        }
        .animation(.easeInOut(duration: 0.05), value: inputLevel)
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isActive else { return minHeight }

        let threshold = Float(index) / Float(barCount - 1)
        let adjustedLevel = inputLevel * 1.3

        if adjustedLevel > threshold {
            let range = maxHeight - minHeight
            let levelInRange = min(adjustedLevel - threshold, 1.0 - threshold)
            let normalizedLevel = levelInRange / (1.0 - threshold)
            return minHeight + range * CGFloat(normalizedLevel)
        }
        return minHeight
    }

    private func barColor(for index: Int) -> Color {
        guard isActive else { return .gray.opacity(0.5) }
        let threshold = Float(index) / Float(barCount - 1)
        if inputLevel > 0.85 && threshold > 0.6 {
            return .red.opacity(0.9)
        }
        return .red.opacity(0.8)
    }
}