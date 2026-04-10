import SwiftUI

enum ToastKind {
    case success
    case info
    case error
}

struct ToastView: View {
    let message: String
    let isError: Bool
    var isInfo: Bool = false

    private var kind: ToastKind {
        if isError { return .error }
        if isInfo { return .info }
        return .success
    }

    private var backgroundColor: Color {
        switch kind {
        case .success: return .green.opacity(0.9)
        case .info: return .blue.opacity(0.9)
        case .error: return .red.opacity(0.9)
        }
    }

    private var iconName: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
            Text(message)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}