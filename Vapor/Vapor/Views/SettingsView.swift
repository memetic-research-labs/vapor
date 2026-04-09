import SwiftUI

struct SettingsView: View {
    let compressionService: CompressionService
    @Binding var selectedCompressor: CompressorType
    @State private var openRouterApiKey: String = ""
    @State private var openRouterModel: String = "glm-5"
    @State private var isLocalLLMAvailable: Bool = false
    @State private var isDownloading: Bool = false
    @State private var downloadProgress: Double = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 20, weight: .semibold))
            
            GroupBox("Compression Backend") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(CompressorType.allCases, id: \.self) { type in
                        HStack {
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary, lineWidth: 1.5)
                                    .frame(width: 16, height: 16)
                                
                                if selectedCompressor == type {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(type.rawValue)
                                        .font(.system(size: 13, weight: .medium))
                                    
                                    if type == .localLLM {
                                        if isLocalLLMAvailable {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 10))
                                        } else {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .foregroundColor(.orange)
                                                .font(.system(size: 10))
                                        }
                                    }
                                }
                                Text(type.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCompressor = type
                        }
                    }
                }
                .padding(8)
            }
            
            if selectedCompressor == .localLLM {
                GroupBox("Local LLM Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if isLocalLLMAvailable {
                                Label("Model ready", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                                Spacer()
                                Text("Qwen2.5-3B (~2.1 GB)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                Label("Model not downloaded", systemImage: "arrow.down.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                        }
                        
                        if !isLocalLLMAvailable {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Download Model")
                                    .font(.system(size: 12, weight: .medium))
                                
                                if isDownloading {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: downloadProgress, total: 1.0)
                                            .progressViewStyle(.linear)
                                        
                                        Text("\(Int(downloadProgress * 100))% - \(formatBytes(Int(Double(2147483648) * downloadProgress))) / 2.1 GB")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Button("Download Qwen2.5-3B (2.1 GB)") {
                                        Task {
                                            isDownloading = true
                                            do {
                                                try await compressionService.downloadLocalLLMModel()
                                                isLocalLLMAvailable = true
                                            } catch {
                                                print("Failed to download model: \(error)")
                                            }
                                            isDownloading = false
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    
                                    Text("Recommended for best quality. Requires ~2GB storage.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .onAppear {
                    Task {
                        isLocalLLMAvailable = await compressionService.availableCompressors[.localLLM] ?? false
                    }
                }
            }
            
            if selectedCompressor == .openRouter {
                GroupBox("OpenRouter Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                            SecureField("Enter your OpenRouter API key", text: $openRouterApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model")
                                .font(.system(size: 12, weight: .medium))
                            TextField("Model name", text: $openRouterModel)
                                .textFieldStyle(.roundedBorder)
                            Text("Default: glm-5 (cheap, fast)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    compressionService.saveSelectedCompressor(selectedCompressor)
                    
                    if selectedCompressor == .openRouter && !openRouterApiKey.isEmpty {
                        compressionService.setOpenRouterApiKey(openRouterApiKey, model: openRouterModel)
                    }
                    
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
