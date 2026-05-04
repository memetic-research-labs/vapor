import Foundation

enum EntityKind: String, Codable, CaseIterable {
    case person
    case organization
    case product
    case location
    case date
    case url
    case number
    case code
    case concept
    case model
    case tool
    case library
    case api
    case file
    case error
    case decision
}

struct ExtractedEntity: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var text: String
    var kind: EntityKind
    var confidence: Double
}
