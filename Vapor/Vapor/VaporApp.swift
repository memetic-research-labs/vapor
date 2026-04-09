import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "App")

@main
struct VaporApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PromptRecord.self
        ])
        do {
            let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [persistentConfig])
        } catch {
            // Persistent storage failed; fall back to in-memory so the app remains usable.
            // Prompt history will not persist across sessions.
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
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 400)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

