import Foundation
import SwiftData
import OSLog

nonisolated private let sessionLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "AISession")

@MainActor
@Observable
final class AISessionService {
    static let shared = AISessionService()

    private var modelContext: ModelContext?

    private let vectorizationService = VectorizationService.shared

    private var activeSessions: [String: AISession] = [:]
    private var idleTimers: [String: Timer] = [:]

    var screenshotLinkWindow: TimeInterval = 30

    var idleTimeout: TimeInterval = 30 * 60

    private var isStarted = false

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        guard !isStarted else { return }
        isStarted = true
    }

    func handleTurn(_ turn: CapturedTurn) async {
        guard let modelContext else { return }

        let toolName = turn.toolName ?? "unknown"
        resetIdleTimer(for: toolName)

        if activeSessions[toolName] == nil {
            let session = openSession(toolName: toolName, firstTurn: turn)
            activeSessions[toolName] = session

            if let gitPath = currentWorkingDirectory() {
                if let project = ProjectService.shared.detectProject(from: gitPath) {
                    session.project = project
                    session.projectPath = project.gitLocalPath
                    session.projectName = project.name
                    session.branchName = project.gitCurrentBranch
                    session.prNumber = project.detectedPRNumber
                }
            }

            do {
                modelContext.insert(session)
                try modelContext.save()
                StatusBarService.shared.log("Session opened: \(session.title)", domain: .system, level: .success)
            } catch {
                sessionLogger.error("Failed to save new session: \(error.localizedDescription, privacy: .public)")
            }
        }

        guard let session = activeSessions[toolName] else { return }

        let turnIndex = session.turns.count
        let tokenEstimate = estimateTokenCount(turn.content)

        let aiTurn = AITurn(
            role: turn.role,
            content: turn.content,
            turnIndex: turnIndex,
            capturedAt: turn.capturedAt,
            contentTokenCount: tokenEstimate,
            modelID: turn.modelID,
            toolName: turn.toolName,
            durationSeconds: turn.durationSeconds
        )
        aiTurn.session = session

        modelContext.insert(aiTurn)

        session.totalTurns += 1
        session.totalTokensEstimated += tokenEstimate

        let urls = extractURLs(from: turn.content)
        if !urls.isEmpty {
            aiTurn.attachedURLs = urls
            session.totalAttachedURLs += urls.count
        }

        do {
            try modelContext.save()
        } catch {
            sessionLogger.error("Failed to save turn: \(error.localizedDescription, privacy: .public)")
        }

        Task { @MainActor in
            await SessionEntityService.shared.extractAndLinkEntities(for: aiTurn)
            if let _ = try? await vectorizationService.ensureEmbedding(for: aiTurn) {
                try? modelContext.save()
            }
        }
    }

    func closeSession(for toolName: String) async {
        guard var session = activeSessions[toolName] else { return }

        session.endedAt = Date()
        cancelIdleTimer(for: toolName)
        activeSessions.removeValue(forKey: toolName)

        do {
            try modelContext?.save()
            StatusBarService.shared.log("Session closed: \(session.title) (\(session.totalTurns) turns)", domain: .system, level: .info)
        } catch {
            sessionLogger.error("Failed to close session: \(error.localizedDescription, privacy: .public)")
        }

        Task { @MainActor in
            await generateSummary(for: session)
            SessionEntityService.shared.aggregateEntities(for: session)
            SessionEntityService.shared.aggregateTags(for: session)
            await SessionEntityService.shared.extractDecisions(from: session)
            await SessionEntityService.shared.generateSessionTags(for: session)
        }
    }

    func closeAllSessions() async {
        for toolName in activeSessions.keys {
            await closeSession(for: toolName)
        }
    }

    func manualClose(session: AISession) async {
        session.endedAt = Date()
        for (toolName, activeSession) in activeSessions {
            if activeSession.id == session.id {
                cancelIdleTimer(for: toolName)
                activeSessions.removeValue(forKey: toolName)
                break
            }
        }
        try? modelContext?.save()
        Task { @MainActor in
            await generateSummary(for: session)
            SessionEntityService.shared.aggregateEntities(for: session)
            SessionEntityService.shared.aggregateTags(for: session)
            await SessionEntityService.shared.extractDecisions(from: session)
            await SessionEntityService.shared.generateSessionTags(for: session)
        }
    }

    func linkScreenshot(_ asset: ImageAsset) {
        guard let modelContext else { return }
        let capturedAt = asset.importedAt

        for (_, session) in activeSessions {
            guard let mostRecentTurn = session.turns.max(by: { $0.capturedAt < $1.capturedAt }) else { continue }
            let delta = capturedAt.timeIntervalSince(mostRecentTurn.capturedAt)
            guard delta >= 0, delta <= screenshotLinkWindow else { continue }

            mostRecentTurn.attachedImageIDs.append(asset.id.uuidString)
            session.totalAttachedImages += 1
            asset.aiSession = session
            try? modelContext.save()
            sessionLogger.debug("Linked screenshot to turn \(mostRecentTurn.turnIndex) (delta: \(Int(delta))s)")
            return
        }
    }

    private func openSession(toolName: String, firstTurn: CapturedTurn) -> AISession {
        let title = deriveTitle(from: firstTurn.content)
        return AISession(
            title: title,
            tool: toolName
        )
    }

    private func generateSummary(for session: AISession) async {
        let turns = session.turns.sorted { $0.turnIndex < $1.turnIndex }
        guard turns.count >= 2 else { return }

        let turnSummaries = turns.prefix(10).map { "\($0.role): \($0.content.prefix(120))" }.joined(separator: "\n")
        let abstract = "Session with \(session.totalTurns) turns via \(session.tool). Key topics: \(turnSummaries.prefix(500))"
        session.summaryAbstract = abstract

        try? modelContext?.save()
    }

    private func resetIdleTimer(for toolName: String) {
        cancelIdleTimer(for: toolName)
        let timer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.closeSession(for: toolName)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimers[toolName] = timer
    }

    private func cancelIdleTimer(for toolName: String) {
        idleTimers[toolName]?.invalidate()
        idleTimers.removeValue(forKey: toolName)
    }

    private func deriveTitle(from content: String) -> String {
        let firstLine = content.prefix(80)
        let cleaned = firstLine
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Session" : String(cleaned)
    }

    private func estimateTokenCount(_ text: String) -> Int {
        text.count / 4
    }

    private func extractURLs(from text: String) -> [String] {
        let pattern = #"https?://[^\s<>\"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return []
        }
        var urls = [String]()
        for i in 0..<match.numberOfRanges {
            guard let range = Range(match.range(at: i), in: text) else { continue }
            urls.append(String(text[range]))
        }
        return urls
    }

    private func currentWorkingDirectory() -> String? {
        ProcessInfo.processInfo.environment["PWD"]
    }
}
