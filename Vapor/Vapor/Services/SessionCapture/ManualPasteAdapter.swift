import Foundation
import OSLog

nonisolated private let pasteLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "ManualPasteAdapter")

@MainActor
final class ManualPasteAdapter: SessionCaptureAdapter {
    let toolName = "manual-paste"

    private(set) var isRunning = false
    var onTurnCaptured: (@Sendable (CapturedTurn) async -> Void)?

    private let defaultToolName = "manual"

    func isAvailable() async -> Bool { true }

    func startCapture() async throws {
        isRunning = true
    }

    func stopCapture() async {
        isRunning = false
    }

    func submitPastedText(_ text: String, toolName: String? = nil) {
        guard isRunning, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let segments = segmentIntoTurns(text)

        for segment in segments {
            let turn = CapturedTurn(
                role: segment.role,
                content: segment.content,
                capturedAt: Date(),
                modelID: nil,
                toolName: toolName ?? defaultToolName,
                durationSeconds: nil
            )
            SessionCaptureFacade.shared.handleCapturedTurn(turn)
        }

        pasteLogger.info("Manual paste: \(segments.count) turn(s) from \(segments.count) segment(s)")
    }

    private func segmentIntoTurns(_ text: String) -> [(role: String, content: String)] {
        let lines = text.components(separatedBy: "\n")
        var segments: [(role: String, content: String)] = []
        var currentRole: String?
        var currentContent: [String] = []

        let rolePrefixes: [(String, String)] = [
            (">> ", "assistant"),
            ("**Assistant:**", "assistant"),
            ("**User:**", "user"),
            ("> ", "assistant"),
            ("You:", "user"),
            ("AI:", "assistant"),
        ]

        func flush() {
            let content = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                segments.append((role: currentRole ?? "user", content: content))
            }
            currentContent = []
        }

        for line in lines {
            var matched = false
            for (prefix, role) in rolePrefixes {
                if line.hasPrefix(prefix) {
                    flush()
                    currentRole = role
                    let remainder = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if !remainder.isEmpty {
                        currentContent.append(remainder)
                    }
                    matched = true
                    break
                }
            }
            if !matched {
                currentContent.append(line)
            }
        }
        flush()

        if segments.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append((role: "user", content: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return segments
    }
}
