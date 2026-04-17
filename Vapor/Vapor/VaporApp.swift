import SwiftUI
import SwiftData
import KeyboardShortcuts
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "App")

@main
struct VaporApp: App {
    private static let persistentSchemaVersion = 3
    private static let persistentSchemaVersionKey = "persistentSchemaVersion"

    @State private var preferences = UserPreferences()
    @State private var windowManager: WindowManager
    @State private var compressionService = CompressionService()
    @State private var browserBridge = BrowserBridge()
    @State private var contextQueueService = ContextQueueService()
    @State private var vectorizationService = VectorizationService.shared
    @State private var contextExplorerStore = ContextExplorerStore.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        let prefs = UserPreferences()
        WindowManager.configure(preferences: prefs)
        _preferences = State(initialValue: prefs)
        _windowManager = State(initialValue: WindowManager.shared)
        _browserBridge = State(initialValue: BrowserBridge())
        _contextQueueService = State(initialValue: ContextQueueService())
    }

    private static var hasSetupBrowserBridge = false

    private static func ensureFreshPersistentStores() {
        let defaults = UserDefaults.standard
        let storedVersion = defaults.integer(forKey: persistentSchemaVersionKey)
        guard storedVersion < persistentSchemaVersion else { return }

        logger.info("Resetting persistent stores for schema version \(persistentSchemaVersion)")

        do {
            try deleteSwiftDataStoreFiles()
        } catch {
            logger.error("Failed to reset SwiftData store: \(error.localizedDescription)")
        }

        do {
            try deleteVectorStoreFiles()
        } catch {
            logger.error("Failed to reset vector store: \(error.localizedDescription)")
        }

        do {
            try BlobStore.shared.clearAll()
        } catch {
            logger.error("Failed to clear blob store: \(error.localizedDescription)")
        }

        defaults.set(persistentSchemaVersion, forKey: persistentSchemaVersionKey)
    }

    private static func deleteSwiftDataStoreFiles() throws {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "lol.mrl.app.Vapor"
        let candidateStoreURLs = [
            appSupportURL.appendingPathComponent("default.store"),
            appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("default.store")
        ]

        for storeURL in candidateStoreURLs {
            let dirURL = storeURL.deletingLastPathComponent()
            let storeName = storeURL.lastPathComponent

            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: dirURL.appendingPathComponent(storeName + "-shm"))
            try? FileManager.default.removeItem(at: dirURL.appendingPathComponent(storeName + "-wal"))
        }
    }

    private static func deleteVectorStoreFiles() throws {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let vectorDirectory = appSupportURL.appendingPathComponent("Vapor", isDirectory: true)
        let vectorStoreURL = vectorDirectory.appendingPathComponent("vectors.db")

        try? FileManager.default.removeItem(at: vectorStoreURL)
        try? FileManager.default.removeItem(at: vectorDirectory.appendingPathComponent("vectors.db-shm"))
        try? FileManager.default.removeItem(at: vectorDirectory.appendingPathComponent("vectors.db-wal"))
    }

    private func setupBrowserBridge() {
        guard !Self.hasSetupBrowserBridge else { return }
        Self.hasSetupBrowserBridge = true

        let prefs = preferences
        let bridge = browserBridge

        NSApp.delegate = VaporAppDelegate(bridge: bridge)

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
        ensureFreshPersistentStores()

        let schema = Schema([
            PromptRecord.self,
            ContextItem.self,
            URLRecord.self,
            ContextItemURLLink.self,
            EntityRecord.self,
            ContextItemEntityLink.self
        ])
        do {
            let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [persistentConfig])
        } catch {
            logger.error("Could not create persistent ModelContainer (\(error)); deleting stale store and retrying.")
            try? deleteSwiftDataStoreFiles()
            do {
                let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                return try ModelContainer(for: schema, configurations: [persistentConfig])
            } catch {
                logger.error("Retry also failed (\(error)); falling back to in-memory storage.")
                let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: [inMemoryConfig])
                } catch {
                    fatalError("Cannot create ModelContainer: \(error)")
                }
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
                .environment(contextQueueService)
                .environment(vectorizationService)
                .environment(contextExplorerStore)
                .environment(StatusBarService.shared)
                .onAppear {
                    browserBridge.setContextQueueService(contextQueueService)
                    contextQueueService.setModelContext(sharedModelContainer.mainContext)
                    Task { @MainActor in await vectorizationService.initialize() }
                    setupBrowserBridge()
                    KeyboardShortcuts.onKeyUp(for: .toggleVapor) { windowManager.focus() }
                    windowManager.setupWindowOnAppear()
                    if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                        openWindow(id: "onboarding")
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 683, height: 540)
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

                Button("Choose Browser Target") {
                    NotificationCenter.default.post(name: .vaporChooseBrowserTarget, object: nil)
                }

                Button("Post to Selected Tab") {
                    NotificationCenter.default.post(name: .vaporSendToBrowser, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Copy & Clear") {
                    NotificationCenter.default.post(name: .vaporCopyAndClear, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Prompt History") {
                    openWindow(id: "prompt-history")
                }
                .keyboardShortcut("y", modifiers: .command)

                Button("Context Explorer") {
                    contextExplorerStore.openOverview()
                    openWindow(id: "context-explorer")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Activity Log") {
                    openWindow(id: "activity-log")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Keyboard Shortcuts") {
                    openWindow(id: "keyboard-shortcuts")
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            // Suppress the auto-generated View menu
            CommandGroup(replacing: .toolbar) { }

            // Add our items to the system Window menu instead of creating a duplicate
            CommandGroup(after: .windowArrangement) {
                Divider()

                Button("Context Explorer") {
                    contextExplorerStore.openOverview()
                    openWindow(id: "context-explorer")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

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
                    openWindow(id: "keyboard-shortcuts")
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

        WindowGroup("Prompt History", id: "prompt-history") {
            PromptHistoryView()
                .environment(vectorizationService)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .defaultSize(width: 400, height: 500)

        WindowGroup("Activity Log", id: "activity-log") {
            ActivityLogView()
                .environment(StatusBarService.shared)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 760, height: 420)

        WindowGroup("Keyboard Shortcuts", id: "keyboard-shortcuts") {
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
                .environment(vectorizationService)
        }

        WindowGroup("Context Item", for: ContextItemDetailPayload.self) { $payload in
            Group {
                if let payload, let itemID = $payload.wrappedValue?.itemID {
                    ContextItemDetailView(itemID: itemID)
                }
            }
        }
        .modelContainer(sharedModelContainer)
        .environment(contextExplorerStore)
        .windowStyle(.titleBar)
        .defaultSize(width: 560, height: 600)

        WindowGroup("Context Explorer", id: "context-explorer") {
            ContextExplorerView()
                .environment(contextExplorerStore)
                .environment(vectorizationService)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .defaultSize(width: 940, height: 720)

        MenuBarExtra("Vapor", systemImage: "waveform.circle") {
            MenuBarView()
        }
    }
}

final class VaporAppDelegate: NSObject, NSApplicationDelegate {
    private let bridge: BrowserBridge

    init(bridge: BrowserBridge) {
        self.bridge = bridge
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor [weak self] in
            guard let self else {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            await self.bridge.stop()
            await OllamaDaemonManager.shared.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
