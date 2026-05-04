import Foundation
import ArgumentParser

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show database stats and capture status"
    )

    func run() throws {
        let fm = FileManager.default
        let storeExists = fm.fileExists(atPath: VaporCLI.storeURL.path)

        var stats: [String: String] = [
            "storePath": VaporCLI.storeURL.path,
            "storeExists": storeExists ? "yes" : "no",
            "vectorsDir": VaporCLI.vectorsDir.path,
        ]

        if storeExists {
            let storeSize = (try? fm.attributesOfItem(atPath: VaporCLI.storeURL.path)[.size] as? Int64) ?? 0
            stats["storeSize"] = ByteCountFormatter.string(fromByteCount: storeSize, countStyle: .file)
        }

        let dbPath = VaporCLI.vectorsDir.appendingPathComponent("vectors.db").path
        if fm.fileExists(atPath: dbPath) {
            let vecSize = (try? fm.attributesOfItem(atPath: dbPath)[.size] as? Int64) ?? 0
            stats["vectorsSize"] = ByteCountFormatter.string(fromByteCount: vecSize, countStyle: .file)

            let db = try VaporDatabase.open()
            let vecRows = try db.queryRows(sql: "SELECT COUNT(*) as count FROM vec_items_minilm_l12_multilingual_v2", params: [])
            stats["vectorCount"] = vecRows.first?["count"] ?? "0"

            let metaRows = try db.queryRows(sql: "SELECT COUNT(*) as count FROM aisession_meta", params: [])
            stats["sessionMetaRows"] = metaRows.first?["count"] ?? "0"

            let projectRows = try db.queryRows(sql: "SELECT COUNT(DISTINCT project_id) as count FROM aisession_meta WHERE project_id != ''", params: [])
            stats["projectsWithData"] = projectRows.first?["count"] ?? "0"
        } else {
            stats["vectorCount"] = "0"
            stats["sessionMetaRows"] = "0"
        }

        print("Vapor Status\n")
        for (key, value) in stats {
            print(String(format: "  %-20s %s", key + ":", value))
        }
    }
}
