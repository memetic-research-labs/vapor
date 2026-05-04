import Foundation

struct VaporDatabase {
    let path: String

    static func open() throws -> VaporDatabase {
        let dbPath = VaporCLI.vectorsDir.appendingPathComponent("vectors.db").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw VaporCLIError.databaseNotFound(dbPath)
        }
        return VaporDatabase(path: dbPath)
    }

    func queryRows(sql: String, params: [String]) throws -> [[String: String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", path, sql] + params

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw VaporCLIError.queryFailed("sqlite3 exit code \(process.terminationStatus)")
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }

            return json.map { row in
                var result: [String: String] = [:]
                for (key, value) in row {
                    result[key] = String(describing: value)
                }
                return result
            }
        } catch {
            throw VaporCLIError.queryFailed(error.localizedDescription)
        }
    }
}
