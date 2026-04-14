import Foundation

extension Notification.Name {
    static let vaporCopyOriginal = Notification.Name("vaporCopyOriginal")
    static let vaporCompressAndCopy = Notification.Name("vaporCompressAndCopy")
    static let vaporCopyAndClear = Notification.Name("vaporCopyAndClear")
    static let vaporShowHistory = Notification.Name("vaporShowHistory")
    static let vaporShowHelp = Notification.Name("vaporShowHelp")
    /// Posted to send the current prompt text to the browser extension.
    static let vaporSendToBrowser = Notification.Name("vaporSendToBrowser")
    /// Posted when the local LLM is downloaded (e.g. during onboarding) so the main window can reload.
    static let vaporLLMDownloadCompleted = Notification.Name("vaporLLMDownloadCompleted")
}
