import SwiftUI

struct VaporActivitySpinner: View {
    let size: CGFloat

    @State private var startTime: Date = .now

    private let cycleDuration: Double = 3.0

    init(size: CGFloat = 12) {
        self.size = size
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startTime)
            let phase = (elapsed / cycleDuration).truncatingRemainder(dividingBy: 1.0)
            let color = VaporColors.color(at: phase)
            let rotation = (elapsed / cycleDuration) * 360.0

            Circle()
                .trim(from: 0.2, to: 1.0)
                .stroke(color, style: StrokeStyle(lineWidth: size / 5, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
        }
        .allowsHitTesting(false)
    }
}
