import SwiftUI

/// RGB color values for smooth interpolation between Vapor icon colors.
struct GlowColor {
    let red: Double
    let green: Double
    let blue: Double

    func interpolated(to other: GlowColor, fraction: Double) -> Color {
        Color(
            red: red + (other.red - red) * fraction,
            green: green + (other.green - green) * fraction,
            blue: blue + (other.blue - blue) * fraction
        )
    }
}

/// Colors from the Vapor app icon's vapor/smoke gradient, brightened for visibility.
enum VaporColors {
    static let blue = GlowColor(red: 0.25, green: 0.50, blue: 1.00)
    static let cyan = GlowColor(red: 0.30, green: 0.75, blue: 1.00)
    static let purple = GlowColor(red: 0.60, green: 0.40, blue: 1.00)
    static let magenta = GlowColor(red: 0.85, green: 0.40, blue: 1.00)

    static let all: [GlowColor] = [blue, cyan, purple, magenta]

    /// Compute smoothly interpolated color based on a 0-1 phase through all colors.
    static func color(at phase: Double) -> Color {
        let count = Double(all.count)
        let scaled = phase * count
        let index = Int(scaled) % all.count
        let nextIndex = (index + 1) % all.count
        let fraction = scaled - Double(Int(scaled))
        return all[index].interpolated(to: all[nextIndex], fraction: fraction)
    }
}

/// A glow border for the text editor that:
/// - Smoothly cycles through Vapor icon colors when focused (TimelineView-driven)
/// - Pulses border opacity with audio input level during dictation
struct EditorGlowView: View {
    var isFocused: Bool
    var isDictating: Bool
    var inputLevel: Float

    // Track start time for phase calculation
    @State private var startTime: Date = .now
    @State private var smoothedLevel: CGFloat = 0

    // 5 second full cycle through all 4 colors
    private let cycleDuration: Double = 5.0

    var body: some View {
        if isFocused {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                let phase = (elapsed / cycleDuration).truncatingRemainder(dividingBy: 1.0)
                let color = VaporColors.color(at: phase)

                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(borderOpacity), lineWidth: borderWidth)
                    .shadow(color: color.opacity(shadowOpacity), radius: shadowRadius)
            }
            .allowsHitTesting(false)
            .onChange(of: inputLevel) { _, newLevel in
                withAnimation(.easeOut(duration: 0.12)) {
                    smoothedLevel = CGFloat(newLevel)
                }
            }
        }
    }

    private var borderOpacity: Double {
        if isDictating {
            return 0.5 + Double(smoothedLevel) * 0.4
        }
        return 0.5
    }

    private var borderWidth: CGFloat {
        if isDictating {
            return 4.0
        }
        return 2.0
    }

    private var shadowOpacity: Double {
        if isDictating { return 0 }
        return 0.35
    }

    private var shadowRadius: CGFloat {
        if isDictating { return 0 }
        return 4
    }
}

/// ViewModifier that overlays the glow border on a view.
struct EditorGlowModifier: ViewModifier {
    var isFocused: Bool
    var isDictating: Bool
    var inputLevel: Float

    func body(content: Content) -> some View {
        content.overlay(
            EditorGlowView(
                isFocused: isFocused,
                isDictating: isDictating,
                inputLevel: inputLevel
            )
        )
    }
}

extension View {
    func editorGlow(isFocused: Bool, isDictating: Bool = false, inputLevel: Float = 0) -> some View {
        modifier(EditorGlowModifier(isFocused: isFocused, isDictating: isDictating, inputLevel: inputLevel))
    }
}
