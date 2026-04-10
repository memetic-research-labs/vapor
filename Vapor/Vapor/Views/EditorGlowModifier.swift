import SwiftUI
import Combine

/// Colors extracted from the Vapor app icon's vapor/smoke gradient.
enum VaporColors {
    static let deepBlue = Color(red: 0.10, green: 0.23, blue: 0.42)
    static let cyanBlue = Color(red: 0.29, green: 0.66, blue: 1.00)
    static let purple   = Color(red: 0.53, green: 0.33, blue: 0.80)
    static let magenta  = Color(red: 0.80, green: 0.33, blue: 1.00)

    static let all: [Color] = [deepBlue, cyanBlue, purple, magenta]
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
                guard isFocused, !isDictating else { return }
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
            // VU meter: base opacity + input level boost
            return 0.3 + Double(smoothedLevel) * 0.5
        }
        return 0.35
    }

    private var borderWidth: CGFloat {
        if !isFocused { return 0 }
        if isDictating {
            // Thicker border during dictation, modulated by input level
            return 1.5 + smoothedLevel * 1.5
        }
        return 1.0
    }

    private var shadowOpacity: Double {
        if !isFocused { return 0 }
        if isDictating {
            return 0.2 + Double(smoothedLevel) * 0.4
        }
        return 0.25
    }

    private var shadowRadius: CGFloat {
        if !isFocused { return 0 }
        if isDictating {
            return 3 + smoothedLevel * 5
        }
        return 4
    }
}

extension View {
    func editorGlow(isFocused: Bool, isDictating: Bool = false, inputLevel: Float = 0) -> some View {
        modifier(EditorGlowModifier(isFocused: isFocused, isDictating: isDictating, inputLevel: inputLevel))
    }
}
