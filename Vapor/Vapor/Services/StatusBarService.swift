import SwiftUI
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "StatusBar")

private struct QueuedStatusMessage {
    let event: StatusEvent
    let minimumDisplayDuration: Duration
}

enum StatusBarIndicator: Equatable {
    case context(count: Int, hasProcessing: Bool)
    case browser(connected: Bool)
    case llm(available: Bool)
}

@MainActor
@Observable
final class StatusBarService {
    static let shared = StatusBarService()

    private let readyMessage: String
    private let defaultMinimumDisplayDuration: Duration
    private let maximumRetainedEvents: Int

    var statusMessage: String {
        didSet {
            let msg = statusMessage
            if msg != oldValue {
                logger.debug("Status: \(msg)")
            }
        }
    }

    var indicators: [StatusBarIndicator] = []
    private(set) var events: [StatusEvent] = []

    private var footerQueue: [QueuedStatusMessage] = []
    private var footerTask: Task<Void, Never>?
    private var contextProcessingHoldCount = 0

    init(
        readyMessage: String = "Ready",
        minimumDisplayDuration: Duration = .seconds(1),
        maximumRetainedEvents: Int = 250
    ) {
        self.readyMessage = readyMessage
        self.defaultMinimumDisplayDuration = minimumDisplayDuration
        self.maximumRetainedEvents = maximumRetainedEvents
        self.statusMessage = readyMessage
    }

    func setCompressionStatus(_ message: String) {
        let level = compressionLevel(for: message)
        publish(
            StatusEvent(domain: .compression, level: level, message: message),
            includeInFooter: true,
            minimumDisplayDuration: footerDuration(for: level)
        )
    }

    func setContextStatus(_ message: String) {
        let level = contextLevel(for: message)
        publish(
            StatusEvent(domain: .context, level: level, message: message),
            includeInFooter: true,
            minimumDisplayDuration: footerDuration(for: level)
        )
    }

    func setTransient(
        _ message: String,
        domain: StatusEventDomain = .system,
        metadata: [String: String] = [:]
    ) {
        publish(
            StatusEvent(domain: domain, level: .info, message: message, metadata: metadata),
            includeInFooter: true,
            minimumDisplayDuration: defaultMinimumDisplayDuration
        )
    }

    func setWarning(
        _ message: String,
        domain: StatusEventDomain = .system,
        metadata: [String: String] = [:]
    ) {
        publish(
            StatusEvent(domain: domain, level: .warning, message: message, metadata: metadata),
            includeInFooter: true,
            minimumDisplayDuration: .seconds(3)
        )
    }

    func log(
        _ message: String,
        domain: StatusEventDomain,
        level: StatusEventLevel = .info,
        metadata: [String: String] = [:],
        includeInFooter: Bool = false,
        minimumDisplayDuration: Duration? = nil
    ) {
        publish(
            StatusEvent(domain: domain, level: level, message: message, metadata: metadata),
            includeInFooter: includeInFooter,
            minimumDisplayDuration: minimumDisplayDuration ?? defaultMinimumDisplayDuration
        )
    }

    func clearEvents() {
        events.removeAll()
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

    func beginContextProcessing() {
        contextProcessingHoldCount += 1
    }

    func endContextProcessing() {
        guard contextProcessingHoldCount > 0 else { return }
        contextProcessingHoldCount -= 1

        guard contextProcessingHoldCount == 0 else { return }

        if footerQueue.isEmpty {
            statusMessage = readyMessage
        } else {
            startFooterQueueIfNeeded()
        }
    }

    private func publish(
        _ event: StatusEvent,
        includeInFooter: Bool,
        minimumDisplayDuration: Duration
    ) {
        events.append(event)
        if events.count > maximumRetainedEvents {
            events.removeFirst(events.count - maximumRetainedEvents)
        }

        if includeInFooter {
            footerQueue.append(QueuedStatusMessage(event: event, minimumDisplayDuration: minimumDisplayDuration))
            startFooterQueueIfNeeded()
        }
    }

    private func startFooterQueueIfNeeded() {
        guard footerTask == nil else { return }
        footerTask = Task { @MainActor [weak self] in
            await self?.processFooterQueue()
        }
    }

    private func processFooterQueue() async {
        while !footerQueue.isEmpty {
            let nextMessage = footerQueue.removeFirst()
            statusMessage = nextMessage.event.message
            try? await Task.sleep(for: nextMessage.minimumDisplayDuration)
            guard !Task.isCancelled else {
                footerTask = nil
                return
            }
        }

        if contextProcessingHoldCount == 0 {
            statusMessage = readyMessage
        }
        footerTask = nil
    }

    private func compressionLevel(for message: String) -> StatusEventLevel {
        if message.localizedCaseInsensitiveContains("failed") {
            return .error
        }
        if message.hasPrefix("Done") {
            return .success
        }
        return .info
    }

    private func contextLevel(for message: String) -> StatusEventLevel {
        if message.localizedCaseInsensitiveContains("failed") {
            return .error
        }
        if message.localizedCaseInsensitiveContains("ready") {
            return .success
        }
        return .info
    }

    private func footerDuration(for level: StatusEventLevel) -> Duration {
        switch level {
        case .info, .success:
            defaultMinimumDisplayDuration
        case .warning:
            .seconds(3)
        case .error:
            .seconds(4)
        }
    }
}
