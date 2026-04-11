import SwiftUI
import SwiftData

/// Shared store bridging the history window with the main app.
/// The history window writes restore/delete requests here; ContentView observes and acts on them.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    /// Set by the history window when a record is clicked to restore.
    var pendingRestore: PromptRecord?

    /// Set briefly after a delete to allow undo.
    var lastDeletedRecord: PromptRecord?
    var showUndoToast: Bool = false
    var undoToastMessage: String = ""

    private init() {}

    func requestRestore(_ record: PromptRecord) {
        pendingRestore = record
    }

    func requestDelete(record: PromptRecord, service: PromptHistoryService) {
        lastDeletedRecord = record
        undoToastMessage = "Deleted — tap Undo to restore"
        showUndoToast = true

        try? service.delete(record)

        // Auto-dismiss after 4 seconds
        Task {
            try? await Task.sleep(for: .seconds(4))
            if showUndoToast {
                showUndoToast = false
                lastDeletedRecord = nil
            }
        }
    }

    func undoDelete(service: PromptHistoryService) {
        guard let record = lastDeletedRecord else { return }
        try? service.save(record)
        lastDeletedRecord = nil
        showUndoToast = false
    }
}
