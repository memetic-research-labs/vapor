import SwiftUI

/// Shared store for live transcript text, used to bridge between the main window and the transcript preview window.
@MainActor
@Observable
final class TranscriptStore {
    static let shared = TranscriptStore()
    var text: String = ""
    private init() {}
}
