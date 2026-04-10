import SwiftUI
import Combine

/// RGB color values for smooth interpolation between Vapor icon colors.
struct GlowColor {
    let r: Double, g: Double, b: Double

    func interpolated(to other: GlowColor, fraction: Double) -> Color {
        Color(
            red: r + (other.r - r) * fraction,
            green: g + (other.g - g) * fraction,
            blue: b + (other.b - b) * fraction
        )
    }

    func brightened(by amount: Double) -> Color {
        Color(
            red: min(1.0, r + amount),
            green: min(1.0, g + amount),
            blue: min(1.0, b + amount)
        )
    }
}

/// Colors extracted from the Vapor app icon's vapor/smoke gradient, brightened for visibility.
enum VaporColors {
    static let blue    = GlowColor(r: 0.25, g: 0.50, b: 1.00)
    static let cyan    = GlowColor(r: 0.30, g: 0.75, b: 1.00)
    static let purple  = GlowColor(r: 0.60, g: 0.40, b: 1.00)
    static let magenta = GlowColor(r: 0.85, g: 0.40, b: 1.00)

    static let all: [GlowColor] = [blue, cyan, purple, magenta]
}

/// A glow effect for the text editor that:
/// - Smoothly cycles through Vapor icon colors when focused
/// - Pulses with audio input level during dictation
struct EditorGlowModifier: ViewModifier {
    var isFocused: Bool
    var isDictating: Bool
    var inputLevel: Float // 0.0 - 1.0

    // Continuous animation phase: 0.0 → 1.0 over the full cycle
    @State private var animationPhase: Double = 0
    @State private var smoothedLevel: CGFloat = 0
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(currentColor.opacity(borderOpacity), lineWidth: borderWidth)
                    .shadow(color: currentColor.opacity(shadowOpacity), radius: shadowRadius)
                    .allowsHitTesting(false)
            )
            .onChange(of: isFocused) { _, focused in
                if focused && !isAnimating {
                    startAnimation()
                }
            }
            .onChange(of: inputLevel) { _, newLevel in
                withAnimation(.easeOut(duration: 0.15)) {
                    smoothedLevel = CGFloat(newLevel)
                }
            }
            .onAppear {
                if isFocused && !isAnimating {
                    startAnimation()
                }
            }
    }

    private func startAnimation() {
        isAnimating = true
        // Reset to 0 and animate to 1 over a 5s cycle, repeating forever
        animationPhase = 0
        withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
            animationPhase = 1.0
        }
    }

    // MARK: - Color Interpolation

    /// Smoothly interpolate through the 4 colors based on animation phase.
    private var currentColor: Color {
        if !isFocused { return .clear }

        let colors = VaporColors.all
        let count = Double(colors.count)
        let phase = animationPhase * count
        let index = Int(phase) % colors.count
        let nextIndex = (index + 1) % colors.count
        let fraction = phase - Double(Int(phase))

        let baseColor = colors[index].interpolated(to: colors[nextIndex], fraction: fraction)

        if isDictating {
            // Brighten based on audio input level
            let boost = Double(smoothedLevel) * 0.25
            let c = colors[index]
            let n = colors[nextIndex]
            let r = c.r + (n.r - c.r) * fraction
            let g = c.g + (n.g - c.g) * fraction
            let b = c.b + (n.b - c.b) * fraction
            return Color(
                red: min(1.0, r + boost),
                green: min(1.0, g + boost),
                blue: min(1.0, b + boost)
            )
        }

        return baseColor
    }

    // MARK: - Border & Shadow Properties

    private var borderOpacity: Double {
        if !isFocused { return 0 }
        if isDictating {
            return 0.5 + Double(smoothedLevel) * 0.4
        }
        return 0.5
    }

    private var borderWidth: CGFloat {
        if !isFocused { return 0 }
        if isDictating {
            return 4.0
        }
        return 2.0
    }

    private var shadowOpacity: Double {
        if !isFocused { return 0 }
        if isDictating {
            return 0
        }
        return 0.35
    }

    private var shadowRadius: CGFloat {
        if !isFocused { return 0 }
        if isDictating {
            return 0
        }
        return 4
    }
}

extension View {
    func editorGlow(isFocused: Bool, isDictating: Bool = false, inputLevel: Float = 0) -> some View {
        modifier(EditorGlowModifier(isFocused: isFocused, isDictating: isDictating, inputLevel: inputLevel))
    }
}
