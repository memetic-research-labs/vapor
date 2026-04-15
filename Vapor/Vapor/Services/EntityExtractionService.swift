import Foundation
import NaturalLanguage

enum EntityExtractionBackend {
    case nlTagger
}

@MainActor
final class EntityExtractionService {
    var backend: EntityExtractionBackend = .nlTagger

    func extract(from text: String) -> [ExtractedEntity] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var entities: [ExtractedEntity] = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            guard let tag else { return true }
            let entityText = String(text[tokenRange])
            let kind = mapNLTagToEntityKind(tag)

            let entity = ExtractedEntity(
                text: entityText,
                kind: kind,
                confidence: 0.8
            )
            entities.append(entity)
            return true
        }

        let codeEntities = extractCodeEntities(from: text)
        for codeEntity in codeEntities {
            if !entities.contains(where: { $0.text.lowercased() == codeEntity.text.lowercased() }) {
                entities.append(codeEntity)
            }
        }

        return entities
    }

    private func mapNLTagToEntityKind(_ tag: NLTag) -> EntityKind {
        switch tag {
        case .personalName: return .person
        case .organizationName: return .organization
        case .placeName: return .location
        default: return .concept
        }
    }

    private func extractCodeEntities(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []

        let swiftFuncPattern = #/\b(func|class|struct|protocol|enum|extension|var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\b/#
        for match in text.matches(of: swiftFuncPattern) {
            let keyword = String(match.1)
            let name = String(match.2)
            let kind: EntityKind
            switch keyword {
            case "func": kind = .code
            case "class", "struct", "protocol", "enum", "extension": kind = .code
            default: kind = .code
            }
            entities.append(ExtractedEntity(text: name, kind: kind, confidence: 0.9))
        }

        let urlPattern = #/https?:\/\/[^\s<>"]+/#
        for match in text.matches(of: urlPattern) {
            let url = String(match.output)
            if !entities.contains(where: { $0.text == url && $0.kind == .url }) {
                entities.append(ExtractedEntity(text: url, kind: .url, confidence: 0.95))
            }
        }

        let datePattern = #/\b\d{4}[-/]\d{2}[-/]\d{2}\b/#
        for match in text.matches(of: datePattern) {
            entities.append(ExtractedEntity(text: String(match.output), kind: .date, confidence: 0.85))
        }

        return entities
    }
}
