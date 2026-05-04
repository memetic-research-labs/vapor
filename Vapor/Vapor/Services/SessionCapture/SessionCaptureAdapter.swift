import Foundation

struct CapturedTurn: Sendable {
    let role: String
    let content: String
    let capturedAt: Date
    let modelID: String?
    let toolName: String?
    let durationSeconds: Double?
}

@MainActor
protocol SessionCaptureAdapter: AnyObject {
    var toolName: String { get }
    var isRunning: Bool { get }
    var onTurnCaptured: (@Sendable (CapturedTurn) async -> Void)? { get set }

    func isAvailable() async -> Bool
    func startCapture() async throws
    func stopCapture() async
}

extension SessionCaptureAdapter {
    func isAvailable() async -> Bool { true }
}
