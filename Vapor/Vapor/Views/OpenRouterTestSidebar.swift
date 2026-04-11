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
                    .onSubmit {
                        if !apiKey.isEmpty {
                            UserDefaults.standard.set(apiKey, forKey: "openRouterApiKey")
                        }
                    }
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