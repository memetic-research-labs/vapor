import Foundation
import ArgumentParser

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import exported sessions from .vapor-context/ directories"
    )

    @Option(name: .shortAndLong, help: "Path to project root containing .vapor-context/")
    var path: String?

    @Option(name: .shortAndLong, help: "Output format (table, json)")
    var format: String = "table"

    @Flag(name: .long, help: "Re-embed sessions that are missing embeddings")
    var reembed: Bool = false

    func run() throws {
        let projectRoot = path ?? FileManager.default.currentDirectoryPath
        let contextDir = URL(fileURLWithPath: projectRoot).appendingPathComponent(".vapor-context")

        guard FileManager.default.fileExists(atPath: contextDir.path) else {
            throw CleanExit.message("No .vapor-context/ directory found at \(projectRoot)")
        }

        let sessionsDir = contextDir.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            throw CleanExit.message("No sessions/ directory in .vapor-context/")
        }

        print("Scanning \(sessionsDir.path)...")

        let dateDirs = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ))?.filter { $0.hasDirectoryPath } ?? []

        var imported: [[String: String]] = []

        for dateDir in dateDirs {
            let sessionDirs = (try? FileManager.default.contentsOfDirectory(
                at: dateDir,
                includingPropertiesForKeys: nil
            ))?.filter { $0.hasDirectoryPath } ?? []

            for sessionDir in sessionDirs {
                let sessionID = sessionDir.lastPathComponent
                let metaURL = sessionDir.appendingPathComponent("meta.json")
                let transcriptURL = sessionDir.appendingPathComponent("transcript.md")

                guard FileManager.default.fileExists(atPath: metaURL.path) else { continue }

                var entry: [String: String] = [
                    "sessionId": sessionID,
                    "date": dateDir.lastPathComponent,
                    "path": sessionDir.path,
                ]

                if let meta = try? parseMetaJSON(at: metaURL) {
                    entry["title"] = meta["title"] ?? "Untitled"
                    entry["tool"] = meta["tool"] ?? "unknown"
                    entry["totalTurns"] = meta["totalTurns"] ?? "0"
                    entry["totalTokens"] = meta["totalTokensEstimated"] ?? "0"
                }

                if FileManager.default.fileExists(atPath: transcriptURL.path),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: transcriptURL.path),
                   let size = attrs[.size] as? Int64 {
                    entry["transcriptBytes"] = String(size)
                }

                imported.append(entry)
            }
        }

        imported.sort { $0["date"] ?? "" > $1["date"] ?? "" }

        if format == "json" {
            let data = try JSONSerialization.data(withJSONObject: imported, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            print("Imported Sessions\n")
            if imported.isEmpty {
                print("No session exports found.")
            } else {
                print(String(format: "| %-8s | %-30s | %-10s | %-8s |", "Date", "Session ID", "Tool", "Turns"))
                print(String(format: "|%s|%s|%s|%s|",
                    String(repeating: "-", count: 10),
                    String(repeating: "-", count: 32),
                    String(repeating: "-", count: 12),
                    String(repeating: "-", count: 10)))
                for entry in imported {
                    let date = entry["date"] ?? "?"
                    let sessionID = String(entry["sessionId", default: "?"].prefix(8))
                    let tool = entry["tool"] ?? "?"
                    let turns = entry["totalTurns"] ?? "?"
                    print(String(format: "| %-8s | %-30s | %-10s | %-8s |", date, sessionID, tool, turns))
                }
                print("\n\(imported.count) session(s) found")

                if reembed {
                    print("\nRe-embed flag is set. Note: re-embedding requires the Vapor app's embedding model.")
                    print("Start the Vapor app and use the backfill feature for full re-embedding.")
                }
            }
        }
    }

    private func parseMetaJSON(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var result: [String: String] = [:]
        for (key, value) in json {
            if let str = value as? String { result[key] = str }
            else if let num = value as? Int { result[key] = String(num) }
            else { result[key] = String(describing: value) }
        }
        return result
    }
}

enum CleanExit: Error {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}
