import Foundation

enum CompressorType: String, CaseIterable, Codable, Identifiable {
    case foundationModels = "Apple Foundation Models"
    case localLLM = "Local LLM (On-Device)"
    case ollamaLLM = "Ollama (Local)"
    case openRouter = "OpenRouter"
    case ruleBased = "Rule-Based (Local)"

    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .foundationModels:
            return "Free, no download, requires macOS 26+ & Apple Intelligence"
        case .localLLM:
            return "Best compression quality. Free, ~5GB download"
        case .ollamaLLM:
            return "Local via Ollama. Pull any model (Gemma 4, Qwen, etc.)"
        case .openRouter:
            return "Cloud API, requires API key, ~$0.01/1M tokens"
        case .ruleBased:
            return "Free, always available, ~60-70% LLM quality"
        }
    }
}
