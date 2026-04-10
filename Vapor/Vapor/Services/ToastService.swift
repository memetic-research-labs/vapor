import Foundation

@MainActor
@Observable
final class ToastService {
    var message: String = ""
    var isShowing: Bool = false
    var isError: Bool = false
    var isInfo: Bool = false

    private var hideTask: Task<Void, Never>?

    func show(_ message: String, isError: Bool = false, isInfo: Bool = false) {
        hideTask?.cancel()

        self.message = message
        self.isError = isError
        self.isInfo = isInfo
        self.isShowing = true

        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                await MainActor.run {
                    self.isShowing = false
                }
            }
        }
    }

    func showSuccess(_ message: String) {
        show(message, isError: false, isInfo: false)
    }

    func showError(_ message: String) {
        show(message, isError: true, isInfo: false)
    }

    func showInfo(_ message: String) {
        show(message, isError: false, isInfo: true)
    }

    func hide() {
        hideTask?.cancel()
        isShowing = false
    }
}