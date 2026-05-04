import AuthenticationServices
import CryptoKit
import Foundation

// MARK: - OAuth State

enum OpenRouterOAuthState: Equatable {
    case idle
    case inProgress
    case connected
    case error(String)
}

// MARK: - Service

@MainActor
@Observable
final class OpenRouterOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = OpenRouterOAuthService()

    var state: OpenRouterOAuthState = .idle
    private(set) var apiKey: String = ""

    private var activeSession: ASWebAuthenticationSession?
    private var currentAnchor: ASPresentationAnchor?

    private static let keyExchangeTimeout: TimeInterval = 20

    override private init() {
        super.init()
        loadSavedKey()
    }

    var isConnected: Bool {
        !apiKey.isEmpty
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationSession always calls this on the main thread.
        MainActor.assumeIsolated {
            currentAnchor ?? NSApplication.shared.windows.first ?? NSWindow()
        }
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        guard status == errSecSuccess else {
            // Fail loudly rather than silently degrade to weaker randomness.
            fatalError("SecRandomCopyBytes failed with status \(status); cannot generate secure PKCE verifier")
        }
        return Data(buffer).base64URLEncoded
    }

    private func codeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded
    }

    // MARK: - Connect

    func connect(presentationAnchor: ASPresentationAnchor) async {
        guard state != .inProgress else { return }
        state = .inProgress
        currentAnchor = presentationAnchor

        let verifier = generateCodeVerifier()
        let challenge = codeChallenge(from: verifier)
        let callbackScheme = "vaporapp"

        guard
            let encodedCallback = "vaporapp://openrouter/callback"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let authURL = URL(
                string: "https://openrouter.ai/auth?callback_url=\(encodedCallback)&code_challenge=\(challenge)"
            )
        else {
            state = .error("Failed to build auth URL")
            currentAnchor = nil
            return
        }

        do {
            let callbackURL = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: callbackScheme
                ) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: OAuthError.missingCallback)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.activeSession = session
                session.start()
            }

            guard
                let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                state = .error("No authorization code returned")
                cleanup()
                return
            }

            let key = try await exchangeCode(code, codeVerifier: verifier)
            persistKey(key)
            apiKey = key
            state = .connected
            NotificationCenter.default.post(name: .vaporOpenRouterKeyChanged, object: key)

        } catch let asError as ASWebAuthenticationSessionError
            where asError.code == .canceledLogin {
            state = apiKey.isEmpty ? .idle : .connected

        } catch {
            state = .error(error.localizedDescription)
        }

        cleanup()
    }

    // MARK: - Disconnect

    func disconnect() {
        apiKey = ""
        UserDefaults.standard.removeObject(forKey: "openRouterApiKey")
        try? KeychainService.delete(key: "openRouterApiKey")
        state = .idle
        NotificationCenter.default.post(name: .vaporOpenRouterKeyChanged, object: "")
    }

    // MARK: - Manual key entry

    func saveManualKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        persistKey(trimmed)
        apiKey = trimmed
        state = .connected
        NotificationCenter.default.post(name: .vaporOpenRouterKeyChanged, object: trimmed)
    }

    // MARK: - Code exchange

    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/keys") else {
            throw OAuthError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.keyExchangeTimeout

        let body = ["code": code, "code_verifier": codeVerifier]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw OAuthError.exchangeFailed(httpResponse.statusCode)
        }

        struct KeyResponse: Codable {
            let key: String
        }
        let result = try JSONDecoder().decode(KeyResponse.self, from: data)
        return result.key
    }

    // MARK: - Persistence

    private func persistKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "openRouterApiKey")
        try? KeychainService.save(key: "openRouterApiKey", value: key)
    }

    private func loadSavedKey() {
        let key = KeychainService.load(key: "openRouterApiKey")
            ?? UserDefaults.standard.string(forKey: "openRouterApiKey")
            ?? ""
        apiKey = key
        state = key.isEmpty ? .idle : .connected
    }

    // MARK: - Cleanup

    private func cleanup() {
        activeSession = nil
        currentAnchor = nil
    }
}

// MARK: - Errors

private enum OAuthError: Error, LocalizedError {
    case missingCallback
    case invalidConfiguration
    case exchangeFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingCallback: "No callback URL received from OpenRouter"
        case .invalidConfiguration: "Invalid OAuth configuration"
        case .exchangeFailed(let code): "Key exchange failed (HTTP \(code))"
        }
    }
}

// MARK: - Data+Base64URL

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
