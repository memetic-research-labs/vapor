import SwiftUI
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "StatusBar")

enum StatusBarIndicator: Equatable {
    case context(count: Int, hasProcessing: Bool)
    case browser(connected: Bool)
    case llm(available: Bool)
}

@MainActor
@Observable
final class StatusBarService {
    static let shared = StatusBarService()

    var statusMessage: String = "Ready" {
        didSet {
            let msg = statusMessage
            if msg != oldValue {
                logger.debug("Status: \(msg)")
            }
        }
    }

    var indicators: [StatusBarIndicator] = []

    private var clearTask: Task<Void, Never>?

    func setCompressionStatus(_ message: String) {
        statusMessage = message
        if message.hasPrefix("Done") || message.contains("failed") {
            scheduleClear()
        }
    }

    func setContextStatus(_ message: String) {
        statusMessage = message
        if message.contains("ready") || message.contains("failed") {
            scheduleClear()
        }
    }

    func setTransient(_ message: String) {
        statusMessage = message
        scheduleClear()
    }

    func setWarning(_ message: String) {
        statusMessage = message
        scheduleClear(after: 8)
    }

    func updateContextIndicator(count: Int, hasProcessing: Bool) {
        indicators.removeAll { if case .context = $0 { return true }; return false }
        indicators.append(.context(count: count, hasProcessing: hasProcessing))
    }

    func updateBrowserIndicator(connected: Bool) {
        indicators.removeAll { if case .browser = $0 { return true }; return false }
        indicators.append(.browser(connected: connected))
    }

    func updateLLMIndicator(available: Bool) {
        indicators.removeAll { if case .llm = $0 { return true }; return false }
        indicators.append(.llm(available: available))
    }

    private func scheduleClear(after seconds: TimeInterval = 5) {
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            statusMessage = "Ready"
        }
    }
}
