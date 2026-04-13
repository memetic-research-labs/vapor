import Foundation

struct CompressionTiming: Identifiable {
    let id = UUID()
    let timestamp: Date
    let backend: CompressorType
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let ratio: Double
    let duration: TimeInterval
    let isFirstInference: Bool
    let success: Bool
    let errorMessage: String?
}

enum ServiceEvent: Identifiable {
    case daemonStart(duration: TimeInterval, id: UUID = UUID())
    case modelLoad(backend: String, model: String, duration: TimeInterval, id: UUID = UUID())

    var id: String {
        switch self {
        case .daemonStart(_, let id): return id.uuidString
        case .modelLoad(_, _, _, let id): return id.uuidString
        }
    }

    var label: String {
        switch self {
        case .daemonStart:
            return "Ollama daemon start"
        case .modelLoad(let backend, let model, _, _):
            return "\(backend) model load (\(model))"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .daemonStart(let duration, _): return duration
        case .modelLoad(_, _, let duration, _): return duration
        }
    }
}

@MainActor
@Observable
final class CompressionTelemetry {
    static let shared = CompressionTelemetry()

    var recordings: [CompressionTiming] = []
    var serviceEvents: [ServiceEvent] = []

    private var seenModels: Set<String> = []

    var hasSeenModels: Bool { !seenModels.isEmpty }

    func record(_ timing: CompressionTiming) {
        recordings.insert(timing, at: 0)
        if recordings.count > 100 {
            recordings.removeLast()
        }
    }

    func recordServiceEvent(_ event: ServiceEvent) {
        serviceEvents.insert(event, at: 0)
        if serviceEvents.count > 50 {
            serviceEvents.removeLast()
        }
    }

    func isFirstInference(for modelKey: String) -> Bool {
        let first = !seenModels.contains(modelKey)
        if first {
            seenModels.insert(modelKey)
        }
        return first
    }

    func resetColdStartMarkers() {
        seenModels.removeAll()
    }

    func clear() {
        recordings.removeAll()
        serviceEvents.removeAll()
        seenModels.removeAll()
    }

    var backendStats: [CompressorType: BackendStats] {
        var stats: [CompressorType: BackendStats] = [:]
        for recording in recordings.reversed() {
            let current = stats[recording.backend] ?? BackendStats()
            stats[recording.backend] = BackendStats(
                callCount: current.callCount + 1,
                totalTime: current.totalTime + recording.duration,
                bestTime: min(current.bestTime, recording.duration),
                worstTime: max(current.worstTime, recording.duration),
                lastDuration: recording.duration,
                lastTimestamp: recording.timestamp,
                firstInferenceDuration: recording.isFirstInference
                    ? min(current.firstInferenceDuration, recording.duration)
                    : current.firstInferenceDuration,
                successCount: recording.success ? current.successCount + 1 : current.successCount,
                failureCount: recording.success ? current.failureCount : current.failureCount + 1
            )
        }
        return stats
    }
}

struct BackendStats {
    var callCount: Int = 0
    var totalTime: TimeInterval = 0
    var bestTime: TimeInterval = .infinity
    var worstTime: TimeInterval = 0
    var lastDuration: TimeInterval = 0
    var lastTimestamp: Date = .distantPast
    var firstInferenceDuration: TimeInterval = .infinity
    var successCount: Int = 0
    var failureCount: Int = 0

    var avgTime: TimeInterval {
        callCount > 0 ? totalTime / Double(callCount) : 0
    }
}
