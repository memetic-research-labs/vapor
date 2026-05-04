import Foundation
import ArgumentParser

struct EntitiesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "entities",
        abstract: "Search and graph entities across sessions"
    )

    @Option(name: .shortAndLong, help: "Filter by entity kind")
    var kind: String?

    @Option(name: .shortAndLong, help: "Maximum results")
    var limit: Int = 30

    @Option(name: .shortAndLong, help: "Output format (table, json)")
    var format: String = "table"

    func run() throws {
        let db = try VaporDatabase.open()

        do {
            let rows = try db.queryRows(
                sql: "SELECT entity_kinds FROM aisession_meta GROUP BY entity_kinds ORDER BY COUNT(*) DESC LIMIT ?",
                params: [String(limit * 2)]
            )

            var entityCounts: [String: Int] = [:]
            for row in rows {
                guard let kinds = row["entity_kinds"], !kinds.isEmpty else { continue }
                for kindStr in kinds.split(separator: ",") {
                    let normalized = kindStr.trimmingCharacters(in: .whitespaces)
                    guard !normalized.isEmpty else { continue }
                    if let kind, normalized.lowercased() != kind.lowercased() { continue }
                    entityCounts[normalized, default: 0] += 1
                }
            }

            let sorted = entityCounts.sorted { $0.value > $1.value }

            if format == "json" {
                let output = sorted.map { ["kind": $0.key, "count": String($0.value)] }
                let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("Entities\n")
                if sorted.isEmpty {
                    print("No entities found.")
                } else {
                    print(String(format: "| %-20s | %-8s |", "Kind", "Count"))
                    print(String(format: "|%s|%s|", String(repeating: "-", count: 22), String(repeating: "-", count: 10)))
                    for (entityKind, count) in sorted {
                        print(String(format: "| %-20s | %-8d |", entityKind, count))
                    }
                    print("\n\(sorted.count) entity type(s)")
                }
            }
        } catch {
            throw CleanExit.message("Database error: \(error.localizedDescription)")
        }
    }
}
