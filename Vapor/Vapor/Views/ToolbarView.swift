import SwiftUI

struct ToolbarView: View {
    @Bindable var viewModel: EditorViewModel
    let onCompressAndCopy: () async -> Void
    let onCopyOriginal: () -> Void
    let onClear: () -> Void
    let onToggleSettings: () -> Void
    let onToggleDictation: () -> Void
    let onToggleTest: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggleDictation()
            } label: {
                if viewModel.isDictating {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .symbolEffect(.pulse, options: .repeating, isActive: true)
                        Text("Listening...")
                    }
                    .foregroundColor(.red)
                } else {
                    Image(systemName: "mic")
                }
            }
            .buttonStyle(.bordered)
            .help("Click to start/stop dictation (or hold Fn key)")
            
            Button {
                Task { await onCompressAndCopy() }
            } label: {
                if viewModel.isCompressing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "compress")
                }
                Text("Compress & Copy")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.content.isEmpty || viewModel.isCompressing)
            
            Menu {
                Button("Copy Original") {
                    onCopyOriginal()
                }
                .keyboardShortcut("C", modifiers: [.command, .shift])
            } label: {
                Image(systemName: "doc.on.doc")
                Text("Copy")
            }
            .menuStyle(.borderlessButton)
            .disabled(viewModel.content.isEmpty)
            
            Spacer()
            
            Button("Clear") {
                onClear()
            }
            .keyboardShortcut("N", modifiers: .command)
            .disabled(viewModel.content.isEmpty)
            
            Button {
                onToggleSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            
            Button {
                onToggleTest()
            } label: {
                Image(systemName: "flask")
            }
            .buttonStyle(.borderless)
            .help("OpenRouter Test")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
