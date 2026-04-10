import SwiftUI
import Combine

/// Colors extracted from the Vapor app icon's vapor/smoke gradient, brightened for visibility.
enum VaporColors {
    static let blue    = Color(red: 0.25, green: 0.50, blue: 1.00)
    static let cyan    = Color(red: 0.30, green: 0.75, blue: 1.00)
    static let purple  = Color(red: 0.60, green: 0.40, blue: 1.00)
    static let magenta = Color(red: 0.85, green: 0.40, blue: 1.00)

    static let all: [Color] = [blue, cyan, purple, magenta]
}

/// A glow effect for the text editor that:
/// - Cycles through Vapor icon colors when focused
/// - Pulses with audio input level during dictation
struct EditorGlowModifier: ViewModifier {
    var isFocused: Bool
    var isDictating: Bool
    var inputLevel: Float // 0.0 - 1.0

    @State private var colorIndex: Int = 0
    @State private var smoothedLevel: CGFloat = 0

    // Timer-driven color cycling
    private let cycleTimer = Timer.publish(every: 1.25, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(glowColor.opacity(borderOpacity), lineWidth: borderWidth)
                    .shadow(color: glowColor.opacity(shadowOpacity), radius: shadowRadius)
                    .allowsHitTesting(false)
            )
            .onReceive(cycleTimer) { _ in
                guard isFocused else { return }
                withAnimation(.easeInOut(duration: 1.0)) {
                    colorIndex = (colorIndex + 1) % VaporColors.all.count
                }
            }
            .onChange(of: inputLevel) { _, newLevel in
                // Smooth the audio level for a polished VU meter effect
                withAnimation(.easeOut(duration: 0.15)) {
                    smoothedLevel = CGFloat(newLevel)
                }
            }
    }

    // MARK: - Computed Properties

    private var glowColor: Color {
        if !isFocused { return .clear }
        return VaporColors.all[colorIndex]
    }

    private var borderOpacity: Double {
        if !isFocused { return 0 }
        if isDictating {
            // VU meter: throbs with audio level
            return 0.5 + Double(smoothedLevel) * 0.4
        }
        return 0.5
    }

    private var borderWidth: CGFloat {
        if !isFocused { return 0 }
        if isDictating {
            // Fixed 4px solid border during dictation
            return 4.0
        }
        return 2.0
    }

    private var shadowOpacity: Double {
        if !isFocused { return 0 }
        if isDictating {
            // No shadow during dictation — clean solid border only
            return 0
        }
        return 0.35
    }

    private var shadowRadius: CGFloat {
        if !isFocused { return 0 }
        if isDictating {
            // No shadow during dictation
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
