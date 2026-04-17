import Foundation
import CoreML
import OSLog

nonisolated private let miniLMLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "MiniLMEmbedding")

enum MiniLMEmbeddingError: LocalizedError {
    case modelNotFound
    case vocabularyNotFound
    case serviceNotReady
    case invalidModelInput
    case invalidModelOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            "MiniLM CoreML model not found in app bundle"
        case .vocabularyNotFound:
            "MiniLM tokenizer vocabulary not found in app bundle"
        case .serviceNotReady:
            "MiniLM embedding service is not ready"
        case .invalidModelInput:
            "Failed to build MiniLM model input"
        case .invalidModelOutput:
            "Failed to decode MiniLM model output"
        }
    }
}

final class MiniLMEmbeddingService {
    static let dimensions = 384
    static let identifier = "minilm_l12_multilingual_v2"

    private var model: MLModel?
    private let tokenizer = MiniLMTokenizer()

    var isReady: Bool {
        model != nil
    }

    func initialize() async throws {
        guard model == nil else { return }

        guard let modelURL = resolveModelURL() else {
            miniLMLogger.error("MiniLM model not found in bundle or fallback locations")
            throw MiniLMEmbeddingError.modelNotFound
        }

        model = try loadModel(from: modelURL)
        miniLMLogger.info("Loaded MiniLM model from \(modelURL.path, privacy: .public)")
    }

    private func resolveModelURL() -> URL? {
        let modelName = "paraphrase-multilingual-MiniLM-L12-v2-512tokens"

        if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            return compiledURL
        }

        if let sourceURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodel") {
            return sourceURL
        }

        return candidateModelURLs().first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func loadModel(from modelURL: URL) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        if modelURL.pathExtension == "mlmodel" {
            let compiledURL = try MLModel.compileModel(at: modelURL)
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }

        return try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    private func candidateModelURLs() -> [URL] {
        let modelName = "paraphrase-multilingual-MiniLM-L12-v2-512tokens"
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []

        if let overridePath = environment["MINILM_MODEL_PATH"], !overridePath.isEmpty {
            candidates.append(URL(fileURLWithPath: overridePath))
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let resourceDirectories = [
            Bundle.main.resourceURL,
            executableDirectory,
            executableDirectory?.appendingPathComponent("Resources", isDirectory: true),
            currentDirectory,
            currentDirectory.appendingPathComponent("Resources", isDirectory: true),
            currentDirectory.appendingPathComponent("Vapor/Vapor/Resources", isDirectory: true)
        ]

        for directory in resourceDirectories.compactMap({ $0 }) {
            candidates.append(directory.appendingPathComponent("\(modelName).mlmodelc", isDirectory: true))
            candidates.append(directory.appendingPathComponent("\(modelName).mlmodel"))
        }

        return candidates
    }

    func embed(text: String) async throws -> [Float] {
        guard let model else {
            throw MiniLMEmbeddingError.serviceNotReady
        }

        let normalizedText = preprocess(text)
        let inputTokens = tokenizer.buildModelTokens(sentence: normalizedText)
        let (inputIDs, attentionMask) = tokenizer.buildModelInputs(from: inputTokens)

        let inputFeatures: [String: Any] = [
            "input_ids": inputIDs,
            "attention_mask": attentionMask
        ]

        guard let featureProvider = try? MLDictionaryFeatureProvider(dictionary: inputFeatures) else {
            throw MiniLMEmbeddingError.invalidModelInput
        }

        let output = try await model.prediction(from: featureProvider)
        guard let embeddings = extractEmbeddings(from: output) else {
            miniLMLogger.error("Failed to decode MiniLM output. Available features: \(output.featureNames.sorted().joined(separator: ", "), privacy: .public)")
            throw MiniLMEmbeddingError.invalidModelOutput
        }

        return l2Normalize(floatArray(from: embeddings))
    }

    private func extractEmbeddings(from output: MLFeatureProvider) -> MLMultiArray? {
        if let embeddings = output.featureValue(for: "embeddings")?.multiArrayValue {
            return embeddings
        }

        for featureName in output.featureNames.sorted() {
            if let multiArray = output.featureValue(for: featureName)?.multiArrayValue {
                miniLMLogger.info("Using MiniLM output feature \(featureName, privacy: .public)")
                return multiArray
            }
        }

        return nil
    }

    private func preprocess(_ text: String) -> String {
        var processed = text
        processed = processed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "\\n+", with: " ", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "\\t+", with: " ", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "&nbsp;", with: " ")
        processed = processed.replacingOccurrences(of: "&amp;", with: "&")
        processed = processed.replacingOccurrences(of: "&lt;", with: "<")
        processed = processed.replacingOccurrences(of: "&gt;", with: ">")
        processed = processed.replacingOccurrences(of: "&quot;", with: "\"")
        processed = processed.replacingOccurrences(of: "&#39;", with: "'")
        processed = processed.precomposedStringWithCanonicalMapping
        processed = processed.trimmingCharacters(in: .whitespacesAndNewlines)

        if processed.count > 1000 {
            let truncated = String(processed.prefix(1000))
            if let lastSpace = truncated.lastIndex(of: " ") {
                processed = String(truncated[..<lastSpace])
            } else {
                processed = truncated
            }
        }

        return processed
    }

    private func floatArray(from multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        if multiArray.dataType == .float32 {
            let pointer = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
            return Array(UnsafeBufferPointer(start: pointer, count: count))
        }
        return (0..<count).map { Float(truncating: multiArray[$0]) }
    }

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float.zero) { $0 + ($1 * $1) })
        guard magnitude > Float.ulpOfOne else { return vector }
        return vector.map { $0 / magnitude }
    }
}

private final class MiniLMTokenizer {
    private let basicTokenizer = MiniLMBasicTokenizer()
    private let wordpieceTokenizer: MiniLMWordpieceTokenizer
    private let maxLength = 512
    private let vocabulary: [String: Int]

    init() {
        guard let url = Bundle.main.url(forResource: "bert_tokenizer_vocab", withExtension: "txt"),
              let vocabularyText = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("MiniLM tokenizer vocabulary not found in app bundle")
        }

        let tokens = vocabularyText.split(separator: "\n").map(String.init)
        var vocabulary: [String: Int] = [:]
        for (index, token) in tokens.enumerated() {
            vocabulary[token] = index
        }

        self.vocabulary = vocabulary
        self.wordpieceTokenizer = MiniLMWordpieceTokenizer(vocabulary: vocabulary)
    }

    func buildModelTokens(sentence: String) -> [Int] {
        var tokens = tokenizeToIDs(text: sentence)
        let clsSepTokenCount = 2

        if tokens.count + clsSepTokenCount > maxLength {
            tokens = Array(tokens.prefix(maxLength - clsSepTokenCount))
        }

        let paddingCount = maxLength - tokens.count - clsSepTokenCount
        return [tokenID(for: "[CLS]")] + tokens + [tokenID(for: "[SEP]")] + Array(repeating: 0, count: paddingCount)
    }

    func buildModelInputs(from inputTokens: [Int]) -> (MLMultiArray, MLMultiArray) {
        let inputIDs = MLMultiArray.from(inputTokens, dims: 2)
        let attentionMask = MLMultiArray.from(inputTokens.map { $0 == 0 ? 0 : 1 }, dims: 2)
        return (inputIDs, attentionMask)
    }

    private func tokenizeToIDs(text: String) -> [Int] {
        tokenize(text: text).compactMap { vocabulary[$0] }
    }

    private func tokenize(text: String) -> [String] {
        basicTokenizer.tokenize(text: text).flatMap { wordpieceTokenizer.tokenize(word: $0) }
    }

    private func tokenID(for token: String) -> Int {
        vocabulary[token] ?? vocabulary["[UNK]"] ?? 0
    }
}

private final class MiniLMBasicTokenizer {
    private let neverSplit: Set<String> = ["[UNK]", "[SEP]", "[PAD]", "[CLS]", "[MASK]"]

    func tokenize(text: String) -> [String] {
        text
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: .whitespaces)
            .flatMap { token -> [String] in
                guard !neverSplit.contains(token) else { return [token] }

                var fragments: [String] = []
                var current = ""

                for character in token.lowercased() {
                    if character.isLetter || character.isNumber || character == "°" {
                        current.append(character)
                    } else if !current.isEmpty {
                        fragments.append(current)
                        fragments.append(String(character))
                        current = ""
                    } else {
                        fragments.append(String(character))
                    }
                }

                if !current.isEmpty {
                    fragments.append(current)
                }

                return fragments
            }
            .filter { !$0.isEmpty }
    }
}

private final class MiniLMWordpieceTokenizer {
    private let unknownToken = "[UNK]"
    private let maxInputCharsPerWord = 100
    private let vocabulary: [String: Int]

    init(vocabulary: [String: Int]) {
        self.vocabulary = vocabulary
    }

    func tokenize(word: String) -> [String] {
        guard word.count <= maxInputCharsPerWord else { return [unknownToken] }

        var outputTokens: [String] = []
        var start = 0
        var isBad = false
        var subTokens: [String] = []

        while start < word.count {
            var end = word.count
            var currentSubstring: String?

            while start < end {
                var substring = String(word[word.index(word.startIndex, offsetBy: start)..<word.index(word.startIndex, offsetBy: end)])
                if start > 0 {
                    substring = "##\(substring)"
                }
                if vocabulary[substring] != nil {
                    currentSubstring = substring
                    break
                }
                end -= 1
            }

            if currentSubstring == nil {
                isBad = true
                break
            }

            subTokens.append(currentSubstring!)
            start = end
        }

        if isBad {
            outputTokens.append(unknownToken)
        } else {
            outputTokens.append(contentsOf: subTokens)
        }

        return outputTokens
    }
}

private extension MLMultiArray {
    static func from(_ values: [Int], dims: Int = 1) -> MLMultiArray {
        var shape = Array(repeating: 1, count: dims)
        shape[shape.count - 1] = values.count

        let multiArray: MLMultiArray
        do {
            multiArray = try MLMultiArray(shape: shape as [NSNumber], dataType: .int32)
        } catch {
            fatalError("Failed to create MLMultiArray for MiniLM input: \(error.localizedDescription)")
        }
        let pointer = UnsafeMutablePointer<Int32>(OpaquePointer(multiArray.dataPointer))
        for (index, value) in values.enumerated() {
            pointer[index] = Int32(value)
        }
        return multiArray
    }
}
