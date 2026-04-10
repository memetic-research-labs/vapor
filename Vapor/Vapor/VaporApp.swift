import SwiftUI
import SwiftData
import KeyboardShortcuts
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "App")

@main
struct VaporApp: App {
    @State private var windowManager = WindowManager.shared
    @State private var preferences = UserPreferences()
    @Environment(\.openWindow) private var openWindow

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
                .onAppear {
                    KeyboardShortcuts.onKeyUp(for: .toggleVapor) {
                        windowManager.toggleState()
                    }
                    windowManager.setupWindowOnAppear()
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 400)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Window") {
                Button("Minimize to Pill") {
                    windowManager.minimize()
                }
                .keyboardShortcut(.escape)
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

        MenuBarExtra("Vapor", systemImage: "waveform.circle") {
            MenuBarView()
        }
    }
}