import Foundation

nonisolated final class SSEHub: @unchecked Sendable {
    private var writers: [ObjectIdentifier: (String) -> Void] = [:]
    private var onCountChange: (@Sendable (Int) -> Void)?
    private let q = DispatchQueue(label: "lol.mrl.vapor.sse-hub")

    var clientCount: Int { q.sync { writers.count } }

    func onClientCountChange(_ callback: @escaping @Sendable (Int) -> Void) {
        q.sync { onCountChange = callback }
    }

    func add(_ id: ObjectIdentifier, writer: @escaping (String) -> Void) {
        let (count, callback) = q.sync { () -> (Int, (@Sendable (Int) -> Void)?) in
            writers[id] = writer
            return (writers.count, onCountChange)
        }
        callback?(count)
    }

    func remove(_ id: ObjectIdentifier) {
        let (count, callback) = q.sync { () -> (Int, (@Sendable (Int) -> Void)?) in
            writers.removeValue(forKey: id)
            return (writers.count, onCountChange)
        }
        callback?(count)
    }

    func broadcast(event: String? = nil, json obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let payload = String(data: data, encoding: .utf8) else { return }
        var line = ""
        if let eventName = event { line += "event: \(eventName)\n" }
        line += "data: \(payload)\n\n"
        let list = q.sync { Array(writers.values) }
        for writer in list { writer(line) }
    }
}
