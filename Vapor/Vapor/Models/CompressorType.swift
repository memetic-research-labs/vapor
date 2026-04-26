import Foundation

enum CompressorType: String, CaseIterable, Codable, Identifiable {
    case localLLM = "Local LLM (On-Device)"
    case openRouter = "OpenRouter"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .localLLM:
            return "Best compression quality. Free, model download required"
        case .openRouter:
            return "Cloud API, requires API key, ~$0.01/1M tokens"
        }
    }
}
