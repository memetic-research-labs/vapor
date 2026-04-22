import AppKit
import Foundation
import SwiftUI

enum AppCommandSection: String, CaseIterable, Identifiable {
    case dictation = "Dictation"
    case compression = "Compression"
    case editing = "Editing"
    case focus = "Focus"
    case windows = "Windows"
    case help = "Help"

    var id: String { rawValue }
}

enum AppCommandID: String, CaseIterable, Identifiable {
    case undo
    case redo
    case copy
    case copyOriginal
    case paste
    case selectAll
    case compressAndCopy
    case chooseBrowserTarget
    case postToSelectedTab
    case copyAndClear
    case focusScreenshots
    case focusContext
    case focusTools
    case focusEditor
    case focusPromptHistory
    case promptHistory
    case contextExplorer
    case activityLog
    case openRouterTest
    case keyboardShortcuts
    case toggleCompactFull
    case minimizeToCompact
    case showOnboarding

    var id: String { rawValue }
}

enum AppCommandInvocation {
    case selector(Selector)
    case notification(Notification.Name)
    case openWindow(id: String, activate: Bool)
    case customWindowManager(WindowManagerAction)
    case none
}

enum WindowManagerAction {
    case toggleState
    case minimize
}

struct AppCommandDefinition: Identifiable {
    let id: AppCommandID
    let title: String
    let description: String
    let section: AppCommandSection
    let shortcutDisplay: String?
    let key: KeyEquivalent?
    let modifiers: EventModifiers
    let invocation: AppCommandInvocation
    let includeInHelp: Bool
    let includeInCommands: Bool

    var helpShortcutDisplay: String? {
        shortcutDisplay
    }
}

enum AppCommandRegistry {
    static let all: [AppCommandDefinition] = [
        AppCommandDefinition(
            id: .undo,
            title: "Undo",
            description: "Undo",
            section: .editing,
            shortcutDisplay: "⌘ Z",
            key: "z",
            modifiers: .command,
            invocation: .selector(Selector(("undo:"))),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .redo,
            title: "Redo",
            description: "Redo",
            section: .editing,
            shortcutDisplay: "⌘ ⇧ Z",
            key: "z",
            modifiers: [.command, .shift],
            invocation: .selector(Selector(("redo:"))),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .copy,
            title: "Copy",
            description: "Copy selected text",
            section: .editing,
            shortcutDisplay: "⌘ C",
            key: "c",
            modifiers: .command,
            invocation: .selector(#selector(NSText.copy(_:))),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .copyOriginal,
            title: "Copy Original",
            description: "Copy original text to clipboard",
            section: .compression,
            shortcutDisplay: "⌘ ⇧ C",
            key: "c",
            modifiers: [.command, .shift],
            invocation: .notification(.vaporCopyOriginal),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .paste,
            title: "Paste",
            description: "Paste",
            section: .editing,
            shortcutDisplay: "⌘ V",
            key: "v",
            modifiers: .command,
            invocation: .selector(#selector(NSText.paste(_:))),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .selectAll,
            title: "Select All",
            description: "Select all text",
            section: .editing,
            shortcutDisplay: "⌘ A",
            key: "a",
            modifiers: .command,
            invocation: .selector(#selector(NSText.selectAll(_:))),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .compressAndCopy,
            title: "Compress & Copy",
            description: "Compress and copy to clipboard",
            section: .compression,
            shortcutDisplay: "⌘ ↩",
            key: .return,
            modifiers: .command,
            invocation: .notification(.vaporCompressAndCopy),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .chooseBrowserTarget,
            title: "Choose Browser Target",
            description: "Choose browser tab target",
            section: .compression,
            shortcutDisplay: nil,
            key: nil,
            modifiers: [],
            invocation: .notification(.vaporChooseBrowserTarget),
            includeInHelp: false,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .postToSelectedTab,
            title: "Post to Selected Tab",
            description: "Post to selected browser tab",
            section: .compression,
            shortcutDisplay: "⌘ ⇧ P",
            key: "p",
            modifiers: [.command, .shift],
            invocation: .notification(.vaporSendToBrowser),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .copyAndClear,
            title: "Copy & Clear",
            description: "Copy original and clear editor",
            section: .compression,
            shortcutDisplay: "⌘ K",
            key: "k",
            modifiers: .command,
            invocation: .notification(.vaporCopyAndClear),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .focusScreenshots,
            title: "Focus Screenshots",
            description: "Focus screenshots shelf",
            section: .focus,
            shortcutDisplay: "⌘ ⇧ S",
            key: "s",
            modifiers: [.command, .shift],
            invocation: .notification(.vaporFocusScreenshots),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .focusContext,
            title: "Focus Context",
            description: "Focus context tray",
            section: .focus,
            shortcutDisplay: "⌘ ⌥ C",
            key: "c",
            modifiers: [.command, .option],
            invocation: .notification(.vaporFocusContextTray),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .focusTools,
            title: "Focus Tools",
            description: "Focus tool rail",
            section: .focus,
            shortcutDisplay: "⌘ ⇧ T",
            key: "t",
            modifiers: [.command, .shift],
            invocation: .notification(.vaporFocusToolRail),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .focusEditor,
            title: "Focus Editor",
            description: "Focus editor",
            section: .focus,
            shortcutDisplay: "⌘ ⇧ I",
            key: "i",
            modifiers: [.command, .shift],
            invocation: .notification(.vaporFocusEditor),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .focusPromptHistory,
            title: "Focus Prompt History",
            description: "Focus prompt history shelf",
            section: .focus,
            shortcutDisplay: "⌘ ⇧ H",
            key: "h",
            modifiers: [.command, .shift],
            invocation: .notification(.vaporFocusPromptHistory),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .promptHistory,
            title: "Prompt History",
            description: "Open prompt history",
            section: .windows,
            shortcutDisplay: "⌘ Y",
            key: "y",
            modifiers: .command,
            invocation: .openWindow(id: "prompt-history", activate: true),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .contextExplorer,
            title: "Context Explorer",
            description: "Open context explorer",
            section: .windows,
            shortcutDisplay: "⌘ ⇧ E",
            key: "e",
            modifiers: [.command, .shift],
            invocation: .none,
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .activityLog,
            title: "Activity Log",
            description: "Open activity log",
            section: .windows,
            shortcutDisplay: "⌘ ⇧ L",
            key: "l",
            modifiers: [.command, .shift],
            invocation: .openWindow(id: "activity-log", activate: false),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .openRouterTest,
            title: "OpenRouter Test",
            description: "Open OpenRouter test window",
            section: .windows,
            shortcutDisplay: nil,
            key: nil,
            modifiers: [],
            invocation: .openWindow(id: "openrouter-test", activate: true),
            includeInHelp: false,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .keyboardShortcuts,
            title: "Keyboard Shortcuts",
            description: "Show keyboard shortcuts help",
            section: .help,
            shortcutDisplay: "⌘ /",
            key: "/",
            modifiers: .command,
            invocation: .openWindow(id: "keyboard-shortcuts", activate: false),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .toggleCompactFull,
            title: "Toggle Compact / Full",
            description: "Toggle compact and full view",
            section: .windows,
            shortcutDisplay: "⌘ \\",
            key: "\\",
            modifiers: .command,
            invocation: .customWindowManager(.toggleState),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .minimizeToCompact,
            title: "Minimize to Compact",
            description: "Minimize to compact view",
            section: .windows,
            shortcutDisplay: "Escape",
            key: .escape,
            modifiers: [],
            invocation: .customWindowManager(.minimize),
            includeInHelp: true,
            includeInCommands: true
        ),
        AppCommandDefinition(
            id: .showOnboarding,
            title: "Show Onboarding",
            description: "Show onboarding window",
            section: .help,
            shortcutDisplay: nil,
            key: nil,
            modifiers: [],
            invocation: .openWindow(id: "onboarding", activate: true),
            includeInHelp: false,
            includeInCommands: true
        )
    ]

    static let dictationRows: [(shortcut: String, description: String)] = [
        ("Fn (hold)", "Start dictating"),
        ("Fn (release)", "Stop dictating, commit text")
    ]

    static func command(_ id: AppCommandID) -> AppCommandDefinition {
        guard let command = all.first(where: { $0.id == id }) else {
            fatalError("Missing AppCommandDefinition for \(id.rawValue)")
        }
        return command
    }

    static func helpSections() -> [(title: String, rows: [(shortcut: String, description: String)])] {
        var sections: [(title: String, rows: [(shortcut: String, description: String)])] = []

        sections.append((title: AppCommandSection.dictation.rawValue, rows: dictationRows))

        for section in [AppCommandSection.compression, .editing, .focus, .windows, .help] {
            let rows = all
                .filter { $0.includeInHelp && $0.section == section }
                .compactMap { command -> (shortcut: String, description: String)? in
                    guard let shortcut = command.helpShortcutDisplay else { return nil }
                    return (shortcut, command.description)
                }

            if !rows.isEmpty {
                sections.append((title: section.rawValue, rows: rows))
            }
        }

        return sections
    }
}
