import SwiftUI

struct OpenRouterTestWindowView: View {
    @State private var apiKey: String = ""
    @State private var prompt: String = ""
    @State private var response: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        if !apiKey.isEmpty {
                            UserDefaults.standard.set(apiKey, forKey: "openRouterApiKey")
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                TextEditor(text: $prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()

                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKey.isEmpty || prompt.isEmpty || isLoading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Response")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(response)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 520)
        .onAppear {
            if let savedKey = UserDefaults.standard.string(forKey: "openRouterApiKey") {
                apiKey = savedKey
            }
        }
    }

    private func send() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var request = OpenRouterCompressor.buildBaseRequest(apiKey: apiKey)
            let body: [String: Any] = [
                "model": "glm-5",
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, urlResponse) = try await URLSession.shared.data(for: request)

            guard let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
                response = "Error: HTTP \(statusCode)"
                return
            }

            let result = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            response = result.choices.first?.message.content ?? "No response"
        } catch {
            response = "Error: \(error.localizedDescription)"
        }
    }
}
