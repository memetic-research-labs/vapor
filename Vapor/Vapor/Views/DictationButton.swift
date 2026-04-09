import SwiftUI

struct DictationButton: View {
    let isDictating: Bool
    
    var body: some View {
        Button {} label: {
            if isDictating {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .symbolEffect(.pulse, options: .repeating, isActive: isDictating)
                    Text("Listening...")
                }
                .foregroundColor(.red)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "mic")
                    Text("Hold Fn")
                }
                .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .disabled(true)
    }
}
