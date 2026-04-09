import SwiftUI

struct ToastView: View {
    let message: String
    let isError: Bool
    
    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
            )
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}
