import Foundation
import OSLog

nonisolated private let openRouterModelLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "OpenRouterModels")

enum OpenRouterModelPurpose {
    case compression
    case extraction
    case summarization
}

struct OpenRouterCatalogModel: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let contextLength: Int
    let promptPrice: Double?
    let completionPrice: Double?
    let inputModalities: [String]
    let outputModalities: [String]
    let modality: String

    var supportsTextInput: Bool {
        inputModalities.contains("text") || modality.contains("text")
    }

    var supportsTextOutput: Bool {
        outputModalities.contains("text") || modality.contains("->text")
    }

    var isUsableForTextTasks: Bool {
        supportsTextInput && supportsTextOutput
    }

    var contextLabel: String {
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: contextLength), number: .decimal)
        return "\(formatted) ctx"
    }

    var pricingLabel: String {
        let input = priceLabel(for: promptPrice)
        let output = priceLabel(for: completionPrice)

        switch (input, output) {
        case let (input?, output?): return "\(input) in · \(output) out"
        case let (input?, nil): return "\(input) input"
        case let (nil, output?): return "\(output) output"
        case (nil, nil): return "Pricing unavailable"
        }
    }

    var modalityLabel: String {
        let inputs = inputModalities.isEmpty ? ["text"] : inputModalities
        let outputs = outputModalities.isEmpty ? ["text"] : outputModalities
        return "\(inputs.joined(separator: "+")) -> \(outputs.joined(separator: "+"))"
    }

    private func priceLabel(for value: Double?) -> String? {
        guard let value else { return nil }
        let perMillion = value * 1_000_000
        if perMillion < 0.01 {
            return String(format: "$%.4f/M", perMillion)
        }
        if perMillion < 0.1 {
            return String(format: "$%.3f/M", perMillion)
        }
        return String(format: "$%.2f/M", perMillion)
    }
}

@MainActor
@Observable
final class OpenRouterModelService {
    var models: [OpenRouterCatalogModel] = []
    var isLoading = false
    var lastError: String?
    var lastUpdatedAt: Date?

    private let endpoint = URL(string: "https://openrouter.ai/api/v1/models")!
    private let cacheTTL: TimeInterval = 300

    func refreshIfNeeded(apiKey: String, force: Bool = false) async {
        guard force || shouldRefresh else { return }
        await refresh(apiKey: apiKey)
    }

    func refresh(apiKey: String) async {
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastError = "OpenRouter model catalog failed with HTTP \(statusCode)."
                openRouterModelLogger.error("OpenRouter catalog request failed: HTTP \(statusCode)")
                return
            }

            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            let fetchedModels = decoded.data.map { OpenRouterCatalogModel(payload: $0) }
            models = fetchedModels.filter(\.isUsableForTextTasks)
            lastUpdatedAt = Date()
            lastError = nil
            openRouterModelLogger.info("Loaded \(self.models.count) OpenRouter models")
        } catch {
            lastError = "Failed to load OpenRouter models: \(error.localizedDescription)"
            openRouterModelLogger.error("Failed to load OpenRouter models: \(error.localizedDescription)")
        }
    }

    func models(for purpose: OpenRouterModelPurpose, searchText: String = "") -> [OpenRouterCatalogModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return models
            .filter { model in
                switch purpose {
                case .compression:
                    return model.contextLength >= 8_000
                case .extraction:
                    return model.contextLength >= 4_000
                case .summarization:
                    return model.contextLength >= 16_000
                }
            }
            .filter { model in
                guard !query.isEmpty else { return true }
                return model.id.localizedCaseInsensitiveContains(query)
                    || model.name.localizedCaseInsensitiveContains(query)
                    || model.description.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                score(for: lhs, purpose: purpose) > score(for: rhs, purpose: purpose)
            }
    }

    private var shouldRefresh: Bool {
        guard let lastUpdatedAt else { return true }
        return models.isEmpty || Date().timeIntervalSince(lastUpdatedAt) >= cacheTTL
    }

    private func score(for model: OpenRouterCatalogModel, purpose: OpenRouterModelPurpose) -> Double {
        let promptPrice = model.promptPrice ?? 1
        let completionPrice = model.completionPrice ?? 1
        let context = Double(model.contextLength)

        switch purpose {
        case .compression:
            return (1 / max(promptPrice, 0.000_001)) * 3 + context / 100_000
        case .extraction:
            return (1 / max(promptPrice, 0.000_001)) * 4 + context / 150_000
        case .summarization:
            return context / 20_000 + (1 / max(promptPrice + completionPrice, 0.000_001))
        }
    }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModelPayload]
}

private struct OpenRouterModelPayload: Decodable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int?
    let architecture: Architecture?
    let pricing: Pricing?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case contextLength = "context_length"
        case architecture
        case pricing
    }

    struct Architecture: Decodable {
        let modality: String?
        let inputModalities: [String]?
        let outputModalities: [String]?

        enum CodingKeys: String, CodingKey {
            case modality
            case inputModalities = "input_modalities"
            case outputModalities = "output_modalities"
        }
    }

    struct Pricing: Decodable {
        let prompt: String?
        let completion: String?
    }
}

private extension OpenRouterCatalogModel {
    init(payload: OpenRouterModelPayload) {
        id = payload.id
        name = payload.name
        description = payload.description ?? ""
        contextLength = payload.contextLength ?? 0
        promptPrice = Double(payload.pricing?.prompt ?? "")
        completionPrice = Double(payload.pricing?.completion ?? "")
        inputModalities = payload.architecture?.inputModalities ?? []
        outputModalities = payload.architecture?.outputModalities ?? []
        modality = payload.architecture?.modality ?? "text->text"
    }
}
