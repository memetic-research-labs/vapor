import Foundation
import AppKit

struct ClipboardService {
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    func paste() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
