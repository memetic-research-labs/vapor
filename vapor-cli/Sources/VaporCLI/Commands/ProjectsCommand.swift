import Foundation
import ArgumentParser

struct ProjectsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "projects",
        abstract: "List and manage projects"
    )

    @Option(name: .shortAndLong, help: "Maximum results")
    var limit: Int = 20

    @Option(name: .shortAndLong, help: "Output format (table, json)")
    var format: String = "table"

    func run() throws {
        let db = try VaporDatabase.open()

        do {
            let rows = try db.queryRows(
                sql: "SELECT DISTINCT project_id, tool, COUNT(*) as turn_count FROM aisession_meta WHERE project_id != '' GROUP BY project_id ORDER BY turn_count DESC LIMIT ?",
                params: [String(limit)]
            )

            if format == "json" {
                let output = rows.map { row in
                    ["projectId": row["project_id"] ?? "", "turnCount": row["turn_count"] ?? "0"]
                }
                let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("Projects\n")
                if rows.isEmpty {
                    print("No projects with session data.")
                } else {
                    print(String(format: "| %-36s | %-10s |", "Project ID", "Turns"))
                    print(String(format: "|%s|%s|", String(repeating: "-", count: 38), String(repeating: "-", count: 12)))
                    for row in rows {
                        let projectID = String(row["project_id", default: "?"].prefix(8))
                        let turns = row["turn_count"] ?? "0"
                        print(String(format: "| %-36s | %-10s |", projectID, turns))
                    }
                    print("\n\(rows.count) project(s)")
                }
            }
        } catch {
            throw CleanExit.message("Database error: \(error.localizedDescription)")
        }
    }
}
