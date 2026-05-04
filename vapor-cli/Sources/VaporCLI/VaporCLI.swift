import Foundation
import ArgumentParser

@main
struct VaporCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vapor",
        abstract: "Search and manage Vapor AI session context",
        subcommands: [
            SearchCommand.self,
            SessionsCommand.self,
            EntitiesCommand.self,
            ProjectsCommand.self,
            StatusCommand.self,
            ImportCommand.self,
        ]
    )
}

extension VaporCLI {
    static let appSupportURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first!.appendingPathComponent("lol.mrl.app.Vapor", isDirectory: true)

    static let storeURL = appSupportURL.appendingPathComponent("Vapor.store")
    static let vectorsDir = appSupportURL
}

enum VaporCLIError: Error, LocalizedError {
    case databaseNotFound(String)
    case databaseOpenFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path): "Database not found: \(path)"
        case .databaseOpenFailed(let path): "Failed to open database: \(path)"
        case .queryFailed(let msg): "Query failed: \(msg)"
        }
    }
}
