import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleVapor = Self(
        "toggleVapor",
        default: .init(.space, modifiers: [.control, .option])
    )
}