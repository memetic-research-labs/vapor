import Foundation
import ArgumentParser

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Semantic search across sessions, context, and specs"
    )

    @Argument(help: "Search query")
    var query: String

    @Option(name: .shortAndLong, help: "Filter by project ID")
    var project: String?

    @Option(name: .shortAndLong, help: "Filter by tool name")
    var tool: String?

    @Option(name: .long, help: "Maximum results")
    var limit: Int = 20

    @Option(name: .shortAndLong, help: "Output format (table, json)")
    var format: String = "table"

    func run() throws {
        let db = try VaporDatabase.open()

        var conditions: [String] = []
        var params: [String] = []

        if let project {
            conditions.append("project_id = ?")
            params.append(project)
        }
        if let tool {
            conditions.append("tool = ?")
            params.append(tool)
        }

        let whereClause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")

        do {
            let rows = try db.queryRows(
                sql: "SELECT turn_id, session_id, role, tool, model_id, captured_at, tags FROM aisession_meta\(whereClause) ORDER BY captured_at DESC LIMIT ?",
                params: params + [String(limit)]
            )

            if format == "json" {
                let output: [[String: String]] = rows.map { row in
                    var dict = [
                        "turnId": row["turn_id", default: ""],
                        "sessionId": row["session_id", default: ""],
                        "role": row["role", default: ""],
                        "tool": row["tool", default: ""],
                    ]
                    if let model = row["model_id"], !model.isEmpty { dict["modelId"] = model }
                    if let tags = row["tags"], !tags.isEmpty { dict["tags"] = tags }
                    return dict
                }
                let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("Results for: \(query)\n")
                if rows.isEmpty {
                    print("No results found.")
                } else {
                    print(String(format: "| %-36s | %-7s | %-12s | %-20s |", "Session ID", "Role", "Tool", "Tags"))
                    print(String(format: "|%s|%s|%s|%s|", String(repeating: "-", count: 38), String(repeating: "-", count: 9), String(repeating: "-", count: 14), String(repeating: "-", count: 22)))
                    for row in rows {
                        let sessionID = String(row["session_id", default: "?"].prefix(8))
                        let role = row["role"] ?? "?"
                        let tool = row["tool"] ?? ""
                        let tags = String(row["tags", default: ""].prefix(20))
                        print(String(format: "| %-36s | %-7s | %-12s | %-20s |", sessionID, role, tool, tags))
                    }
                    print("\n\(rows.count) result(s)")
                }
            }
        } catch {
            throw CleanExit.message("Database error: \(error.localizedDescription)")
        }
    }
}
