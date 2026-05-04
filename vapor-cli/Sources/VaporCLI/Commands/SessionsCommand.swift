import Foundation
import ArgumentParser

struct SessionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List and view AI sessions"
    )

    @Option(name: .shortAndLong, help: "Maximum results")
    var limit: Int = 20

    @Option(name: .long, help: "Show session with ID")
    var show: String?

    @Option(name: .long, help: "Filter by tool")
    var tool: String?

    @Option(name: .shortAndLong, help: "Output format (table, json)")
    var format: String = "table"

    func run() throws {
        let db = try VaporDatabase.open()

        if let showID = show {
            return try showSession(db: db, id: showID, format: format)
        }

        let condition = tool.map { " WHERE tool = '\($0)'" } ?? ""

        do {
            let rows = try db.queryRows(
                sql: "SELECT DISTINCT session_id, tool, MIN(captured_at) as started_at, COUNT(*) as turn_count FROM aisession_meta\(condition) GROUP BY session_id ORDER BY started_at DESC LIMIT ?",
                params: [String(limit)]
            )

            if format == "json" {
                let output = rows.map { row in
                    ["sessionId": row["session_id"] ?? "", "tool": row["tool"] ?? "", "turnCount": row["turn_count"] ?? "0"]
                }
                let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("AI Sessions\n")
                if rows.isEmpty {
                    print("No sessions found.")
                } else {
                    print(String(format: "| %-36s | %-12s | %-10s |", "Session ID", "Tool", "Turns"))
                    print(String(format: "|%s|%s|%s|", String(repeating: "-", count: 38), String(repeating: "-", count: 14), String(repeating: "-", count: 12)))
                    for row in rows {
                        let sessionID = String(row["session_id", default: "?"].prefix(8))
                        let tool = row["tool"] ?? ""
                        let turns = row["turn_count"] ?? "0"
                        print(String(format: "| %-36s | %-12s | %-10s |", sessionID, tool, turns))
                    }
                    print("\n\(rows.count) session(s)")
                }
            }
        } catch {
            throw CleanExit.message("Database error: \(error.localizedDescription)")
        }
    }

    private func showSession(db: VaporDatabase, id: String, format: String) throws {
        let rows = try db.queryRows(
            sql: "SELECT role, tool, model_id, captured_at FROM aisession_meta WHERE session_id = ? ORDER BY captured_at ASC",
            params: [id]
        )

        if rows.isEmpty {
            throw CleanExit.message("Session not found: \(id)")
        }

        if format == "json" {
            let output = rows.map { row in
                ["role": row["role"] ?? "", "tool": row["tool"] ?? "", "modelId": row["model_id"] ?? ""]
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            print("Session \(id)\n")
            for row in rows {
                let role = (row["role"] ?? "?").uppercased()
                let model = row["model_id"] ?? ""
                print("[\(role)] \(model)")
            }
            print("\n\(rows.count) turn(s)")
        }
    }
}
