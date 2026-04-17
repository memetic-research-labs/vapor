import Foundation

enum StatusEventDomain: String, CaseIterable, Identifiable {
    case browser = "Browser"
    case compression = "Compression"
    case context = "Context"
    case system = "System"
    case vectorization = "Vectorization"

    var id: String { rawValue }
}

enum StatusEventLevel: String, CaseIterable {
    case info
    case success
    case warning
    case error
}

struct StatusEvent: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let domain: StatusEventDomain
    let level: StatusEventLevel
    let message: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        domain: StatusEventDomain,
        level: StatusEventLevel,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.domain = domain
        self.level = level
        self.message = message
        self.metadata = metadata
    }
}
