import SwiftUI
import SwiftData
import KeyboardShortcuts
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "App")

@main
struct VaporApp: App {
    private let sharedModelContainer: ModelContainer

    @State private var preferences = UserPreferences()
    @State private var windowManager: WindowManager
    @State private var compressionService = CompressionService()
    @State private var browserBridge = BrowserBridge()
    @State private var contextQueueService = ContextQueueService()
    @State private var vectorizationService = VectorizationService.shared
    @State private var contextExplorerStore = ContextExplorerStore.shared
    @State private var screenshotShelfStore = ScreenshotShelfStore.shared
    @State private var mainWindowFocusStore = MainWindowFocusStore()
    @State private var appDelegate: VaporAppDelegate?
    @State private var onboardingObserver: NSObjectProtocol?
    @Environment(\.openWindow) private var openWindow

    init() {
        let prefs = UserPreferences()
        WindowManager.configure(preferences: prefs)
        _preferences = State(initialValue: prefs)
        _windowManager = State(initialValue: WindowManager.shared)
        _browserBridge = State(initialValue: BrowserBridge())
        _contextQueueService = State(initialValue: ContextQueueService())

        do {
            self.sharedModelContainer = try Self.makeSharedModelContainer()
        } catch {
            logger.fault("Failed to open persistent ModelContainer: \(error.localizedDescription)")
            fatalError("Vapor could not open its persistent store. No automatic reset or in-memory fallback was performed. Underlying error: \(error.localizedDescription)")
        }
    }

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let storeDir = appSupport.appendingPathComponent("lol.mrl.app.Vapor", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        return storeDir.appendingPathComponent("Vapor.store")
    }

    private static func makeSharedModelContainer() throws -> ModelContainer {
        return try ModelContainer.forVapor(url: storeURL)
    }

    private static var hasSetupBrowserBridge = false

    private func setupBrowserBridge() {
        guard !Self.hasSetupBrowserBridge else { return }
        Self.hasSetupBrowserBridge = true

        let prefs = preferences
        let bridge = browserBridge

        if appDelegate == nil {
            let delegate = VaporAppDelegate(bridge: bridge)
            appDelegate = delegate
            NSApp.delegate = delegate
        }

        ProcessInfo.processInfo.disableAutomaticTermination("Browser bridge requires persistent process")

        Task {
            if prefs.browserIntegrationEnabled {
                await bridge.start()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await bridge.stop() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                guard prefs.browserIntegrationEnabled else { return }
                await bridge.stop()
                try? await Task.sleep(for: .seconds(1))
                await bridge.start()
            }
        }
    }

    var body: some Scene {
        mainAppScene

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

        WindowGroup("OpenRouter Test", id: "openrouter-test") {
            OpenRouterTestWindowView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 520, height: 620)

        WindowGroup("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            KeyboardShortcutsHelpView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 340, height: 360)

        WindowGroup("Vapor Onboarding", id: "onboarding") {
            OnboardingView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 580)

        Settings {
            SettingsView(compressionService: compressionService, preferences: preferences)
                .environment(browserBridge)
                .environment(vectorizationService)
                .modelContainer(sharedModelContainer)
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

    private var mainAppScene: some Scene {
        return Window("Vapor", id: "main") {
            ContentView()
                .environment(windowManager)
                .environment(preferences)
                .environment(compressionService)
                .environment(browserBridge)
                .environment(contextQueueService)
                .environment(vectorizationService)
                .environment(contextExplorerStore)
                .environment(screenshotShelfStore)
                .environment(mainWindowFocusStore)
                .environment(StatusBarService.shared)
                .onAppear {
                    browserBridge.setContextQueueService(contextQueueService)
                    contextQueueService.setModelContext(sharedModelContainer.mainContext)
                    screenshotShelfStore.setModelContext(sharedModelContainer.mainContext)
                    screenshotShelfStore.setContextQueueService(contextQueueService)
                    screenshotShelfStore.start()
                    Task { @MainActor in await vectorizationService.initialize() }
                    setupBrowserBridge()
                    KeyboardShortcuts.onKeyUp(for: .toggleVapor) { windowManager.focus() }
                    windowManager.setupWindowOnAppear()
                    if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                        openWindow(id: "onboarding")
                    }
                    if onboardingObserver == nil {
                        onboardingObserver = NotificationCenter.default.addObserver(forName: .vaporShowOnboarding, object: nil, queue: .main) { _ in
                            openWindow(id: "onboarding")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
                .onDisappear {
                    if let onboardingObserver {
                        NotificationCenter.default.removeObserver(onboardingObserver)
                        self.onboardingObserver = nil
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 780, height: 660)
        .commands { appCommands }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        let undoCommand = AppCommandRegistry.command(.undo)
        let redoCommand = AppCommandRegistry.command(.redo)
        let copyCommand = AppCommandRegistry.command(.copy)
        let copyOriginalCommand = AppCommandRegistry.command(.copyOriginal)
        let pasteCommand = AppCommandRegistry.command(.paste)
        let selectAllCommand = AppCommandRegistry.command(.selectAll)
        let compressCommand = AppCommandRegistry.command(.compressAndCopy)
        let chooseTargetCommand = AppCommandRegistry.command(.chooseBrowserTarget)
        let postToSelectedTabCommand = AppCommandRegistry.command(.postToSelectedTab)
        let copyAndClearCommand = AppCommandRegistry.command(.copyAndClear)
        let focusScreenshotsCommand = AppCommandRegistry.command(.focusScreenshots)
        let focusContextCommand = AppCommandRegistry.command(.focusContext)
        let focusToolsCommand = AppCommandRegistry.command(.focusTools)
        let focusEditorCommand = AppCommandRegistry.command(.focusEditor)
        let focusPromptHistoryCommand = AppCommandRegistry.command(.focusPromptHistory)
        let promptHistoryCommand = AppCommandRegistry.command(.promptHistory)
        let contextExplorerCommand = AppCommandRegistry.command(.contextExplorer)
        let activityLogCommand = AppCommandRegistry.command(.activityLog)
        let openRouterTestCommand = AppCommandRegistry.command(.openRouterTest)
        let keyboardShortcutsCommand = AppCommandRegistry.command(.keyboardShortcuts)
        let toggleCompactFullCommand = AppCommandRegistry.command(.toggleCompactFull)
        let minimizeToCompactCommand = AppCommandRegistry.command(.minimizeToCompact)
        let showOnboardingCommand = AppCommandRegistry.command(.showOnboarding)

        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .undoRedo) {
            Button(undoCommand.title) {
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            }
            .keyboardShortcut(undoCommand.key ?? "z", modifiers: undoCommand.modifiers)

            Button(redoCommand.title) {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            }
            .keyboardShortcut(redoCommand.key ?? "z", modifiers: redoCommand.modifiers)
        }

        CommandGroup(replacing: .pasteboard) {
            Button(copyCommand.title) {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut(copyCommand.key ?? "c", modifiers: copyCommand.modifiers)

            Button(copyOriginalCommand.title) {
                NotificationCenter.default.post(name: .vaporCopyOriginal, object: nil)
            }
            .keyboardShortcut(copyOriginalCommand.key ?? "c", modifiers: copyOriginalCommand.modifiers)

            Button(pasteCommand.title) {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut(pasteCommand.key ?? "v", modifiers: pasteCommand.modifiers)

            Button(selectAllCommand.title) {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut(selectAllCommand.key ?? "a", modifiers: selectAllCommand.modifiers)
        }

        CommandMenu("Actions") {
            Button(compressCommand.title) {
                NotificationCenter.default.post(name: .vaporCompressAndCopy, object: nil)
            }
            .keyboardShortcut(compressCommand.key ?? .return, modifiers: compressCommand.modifiers)

            Button(chooseTargetCommand.title) {
                NotificationCenter.default.post(name: .vaporChooseBrowserTarget, object: nil)
            }

            Button(postToSelectedTabCommand.title) {
                NotificationCenter.default.post(name: .vaporSendToBrowser, object: nil)
            }
            .keyboardShortcut(postToSelectedTabCommand.key ?? "p", modifiers: postToSelectedTabCommand.modifiers)

            Button(copyAndClearCommand.title) {
                NotificationCenter.default.post(name: .vaporCopyAndClear, object: nil)
            }
            .keyboardShortcut(copyAndClearCommand.key ?? "k", modifiers: copyAndClearCommand.modifiers)

            Button(focusScreenshotsCommand.title) {
                NotificationCenter.default.post(name: .vaporFocusScreenshots, object: nil)
            }
            .keyboardShortcut(focusScreenshotsCommand.key ?? "s", modifiers: focusScreenshotsCommand.modifiers)

            Button(focusContextCommand.title) {
                NotificationCenter.default.post(name: .vaporFocusContextTray, object: nil)
            }
            .keyboardShortcut(focusContextCommand.key ?? "c", modifiers: focusContextCommand.modifiers)

            Button(focusToolsCommand.title) {
                NotificationCenter.default.post(name: .vaporFocusToolRail, object: nil)
            }
            .keyboardShortcut(focusToolsCommand.key ?? "t", modifiers: focusToolsCommand.modifiers)

            Button(focusEditorCommand.title) {
                NotificationCenter.default.post(name: .vaporFocusEditor, object: nil)
            }
            .keyboardShortcut(focusEditorCommand.key ?? "i", modifiers: focusEditorCommand.modifiers)

            Button(focusPromptHistoryCommand.title) {
                NotificationCenter.default.post(name: .vaporFocusPromptHistory, object: nil)
            }
            .keyboardShortcut(focusPromptHistoryCommand.key ?? "h", modifiers: focusPromptHistoryCommand.modifiers)
        }

        CommandGroup(replacing: .toolbar) { }

        CommandGroup(after: .windowArrangement) {
            Divider()

            Button(promptHistoryCommand.title) {
                openWindow(id: "prompt-history")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(promptHistoryCommand.key ?? "y", modifiers: promptHistoryCommand.modifiers)

            Button(contextExplorerCommand.title) {
                contextExplorerStore.openOverview()
                openWindow(id: "context-explorer")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(contextExplorerCommand.key ?? "e", modifiers: contextExplorerCommand.modifiers)

            Button(activityLogCommand.title) {
                openWindow(id: "activity-log")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(activityLogCommand.key ?? "l", modifiers: activityLogCommand.modifiers)

            Button(openRouterTestCommand.title) {
                openWindow(id: "openrouter-test")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button(showOnboardingCommand.title) {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button(toggleCompactFullCommand.title) {
                windowManager.toggleState()
            }
            .keyboardShortcut(toggleCompactFullCommand.key ?? "\\", modifiers: toggleCompactFullCommand.modifiers)
        }

        CommandGroup(after: .help) {
            Button(keyboardShortcutsCommand.title) {
                openWindow(id: "keyboard-shortcuts")
            }
            .keyboardShortcut(keyboardShortcutsCommand.key ?? "/", modifiers: keyboardShortcutsCommand.modifiers)
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
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
