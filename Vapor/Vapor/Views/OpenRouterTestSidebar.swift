import SwiftUI

struct OpenRouterTestSidebar: View {
    @Binding var prompt: String
    
    @State private var apiKey: String = ""
    @State private var response: String = ""
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenRouter")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $prompt)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(height: 120)
                    .border(Color.gray.opacity(0.3))
            }
            .padding(.horizontal, 12)
            
            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 4) {
                    if isLoading { ProgressView().scaleEffect(0.6) }
                    Text("Send")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(apiKey.isEmpty || prompt.isEmpty || isLoading)
            .padding(.horizontal, 12)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Response")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                ScrollView {
                    Text(response)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
        }
        .onAppear {
            if let savedKey = KeychainService.load(key: "openRouterApiKey") {
                apiKey = savedKey
            }
        }
        .onChange(of: apiKey) { _, newValue in
            if !newValue.isEmpty {
                try? KeychainService.save(key: "openRouterApiKey", value: newValue)
            }
        }
    }
    
    private func send() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("https://github.com/memetic-research-labs-llc/comp-tok-stt", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "model": "glm-5",
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                response = "Error: HTTP error"
                return
            }
            
            let result = try JSONDecoder().decode(OpenRouterTestResponse.self, from: data)
            response = result.choices.first?.message.content ?? "No response"
        } catch {
            response = "Error: \(error.localizedDescription)"
        }
    }
}

struct OpenRouterTestResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let content: String
        }
    }
}