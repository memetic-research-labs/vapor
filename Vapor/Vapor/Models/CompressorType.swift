import Foundation

enum CompressorType: String, CaseIterable, Codable {
    case foundationModels = "Apple Foundation Models"
    case localLLM = "Local LLM (On-Device)"
    case openRouter = "OpenRouter"
    case ruleBased = "Rule-Based (Local)"
    
    var description: String {
        switch self {
        case .foundationModels:
            return "Free, on-device, requires macOS 26+ & Apple Intelligence"
        case .localLLM:
            return "Free, on-device LLM via llama.cpp, ~2GB download"
        case .openRouter:
            return "Cloud API, requires API key, ~$0.01/1M tokens"
        case .ruleBased:
            return "Free, always available, ~60-70% LLM quality"
        }
    }
}
