import SwiftUI
import SwiftData
import KeyboardShortcuts
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "App")

@main
struct VaporApp: App {
    @State private var preferences = UserPreferences()
    @State private var windowManager: WindowManager
    @State private var compressionService = CompressionService()
    @State private var browserBridge = BrowserBridge()
    @Environment(\.openWindow) private var openWindow

    init() {
        let prefs = UserPreferences()
        WindowManager.configure(preferences: prefs)
        _preferences = State(initialValue: prefs)
        _windowManager = State(initialValue: WindowManager.shared)
        _browserBridge = State(initialValue: BrowserBridge())
    }

    private static var hasSetupBrowserBridge = false

    private func setupBrowserBridge() {
        guard !Self.hasSetupBrowserBridge else { return }
        Self.hasSetupBrowserBridge = true

        let prefs = preferences
        let bridge = browserBridge
        Task {
            do {
                try await OllamaDaemonManager.shared.start()
                if prefs.browserIntegrationEnabled {
                    await bridge.start()
                }
            } catch {
                logger.warning("Ollama daemon did not start: \(error.localizedDescription)")
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await OllamaDaemonManager.shared.stop() }
            Task { await bridge.stop() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await OllamaDaemonManager.shared.stop() }
            Task { await bridge.stop() }
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PromptRecord.self
        ])
        do {
            let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [persistentConfig])
        } catch {
            logger.error("Could not create persistent ModelContainer (\(error)); falling back to in-memory storage.")
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [inMemoryConfig])
            } catch {
                fatalError("Cannot create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        Window("Vapor", id: "main") {
            ContentView()
                .environment(windowManager)
                .environment(preferences)
                .environment(compressionService)
                .environment(browserBridge)
                .onAppear {
                    setupBrowserBridge()
                    KeyboardShortcuts.onKeyUp(for: .toggleVapor) { windowManager.focus() }
                    windowManager.setupWindowOnAppear()
                    if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                        openWindow(id: "onboarding")
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 500, height: 400)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Copy Original") {
                    NotificationCenter.default.post(name: .vaporCopyOriginal, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            CommandMenu("Actions") {
                Button("Compress & Copy") {
                    NotificationCenter.default.post(name: .vaporCompressAndCopy, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Copy & Clear") {
                    NotificationCenter.default.post(name: .vaporCopyAndClear, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Prompt History") {
                    NotificationCenter.default.post(name: .vaporShowHistory, object: nil)
                }
                .keyboardShortcut("y", modifiers: .command)

                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .vaporShowHelp, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            // Suppress the auto-generated View menu
            CommandGroup(replacing: .toolbar) { }

            // Add our items to the system Window menu instead of creating a duplicate
            CommandGroup(after: .windowArrangement) {
                Divider()

                Button("Toggle Compact / Full") {
                    windowManager.toggleState()
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Minimize to Compact") {
                    windowManager.minimize()
                }
                .keyboardShortcut(.escape)
            }

            CommandGroup(after: .help) {
                Button("Show Onboarding") {
                    openWindow(id: "onboarding")
                }

                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .vaporShowHelp, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }

        Window("Transcript Preview", id: "transcript-preview") {
            TranscriptPreviewView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 240)

        Window("Prompt History", id: "prompt-history") {
            PromptHistoryView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .defaultSize(width: 400, height: 500)

        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            KeyboardShortcutsHelpView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 340, height: 360)

        Window("Vapor Onboarding", id: "onboarding") {
            OnboardingView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 540)

        Settings {
            SettingsView(compressionService: compressionService, preferences: preferences)
                .environment(browserBridge)
        }

        MenuBarExtra("Vapor", systemImage: "waveform.circle") {
            MenuBarView()
        }
    }
}
