import SwiftUI
import KeyboardShortcuts
import OSLog
#if DEBUG
import SwiftData
#endif

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Settings")

struct SettingsView: View {
    @Bindable var compressionService: CompressionService
    let preferences: UserPreferences
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(VectorizationService.self) private var vectorizationService
    #if DEBUG
    @Environment(\.modelContext) private var modelContext
    #endif
    @State private var openRouterModelService = OpenRouterModelService()
    @State private var openRouterApiKey: String = ""
    @State private var compressionOpenRouterModel: String = "glm-5"
    @State private var useCustomCompressionOpenRouterModel: Bool = false
    @State private var customCompressionOpenRouterModel: String = ""
    private var isLocalLLMAvailable: Bool { compressionService.isSelectedLocalModelDownloaded }
    @State private var selectedTab: SettingsTab = .compression
    @State private var displayedAuthToken: String = ""
    @State private var embeddedServerPortText: String = ""
    @State private var extractionBackend: EntityExtractionBackend = .nlTagger
    @State private var extractionOpenRouterModel: String = NERModel.defaultModel
    @State private var useCustomExtractionOpenRouterModel: Bool = false
    @State private var customExtractionOpenRouterModel: String = ""
    @State private var summarizationBackend: SummarizationBackendPreference = .sameAsEntityExtraction
    @State private var summarizationOpenRouterModel: String = NERModel.defaultModel
    @State private var useCustomSummarizationOpenRouterModel: Bool = false
    @State private var customSummarizationOpenRouterModel: String = ""
    @State private var cloudModelSearchText: String = ""
    #if DEBUG
    @State private var swiftDataClearStatus: String = ""
    @State private var vectorStoreClearStatus: String = ""
    @State private var blobStoreClearStatus: String = ""
    #endif

    private let validPortRange = 1...65_535

    enum SettingsTab: String, Identifiable {
        case compression = "Compression"
        case contextProcessing = "Context Processing"
        case cloud = "Cloud"
        case general = "General"
        case browser = "Browser"
        case telemetry = "Telemetry"
        #if DEBUG
        case dataManagement = "Data Management"
        #endif

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .compression: return "arrow.left.arrow.right"
            case .contextProcessing: return "sparkles.rectangle.stack"
            case .browser: return "globe"
            case .cloud: return "cloud"
            case .general: return "gearshape.2"
            case .telemetry: return "chart.bar"
            #if DEBUG
            case .dataManagement: return "trash"
            #endif
            }
        }

        #if DEBUG
        static let allCases: [SettingsTab] = [
            .compression, .contextProcessing, .cloud,
            .general, .browser, .telemetry, .dataManagement
        ]
        #else
        static let allCases: [SettingsTab] = [
            .compression, .contextProcessing, .cloud,
            .general, .browser, .telemetry
        ]
        #endif
    }

    enum SettingsGroup: String, CaseIterable, Identifiable {
        case ai = "AI & Models"
        case app = "App"

        var id: String { rawValue }

        var tabs: [SettingsTab] {
            switch self {
            case .ai:
                let aiTabs: [SettingsTab] = [.compression, .contextProcessing, .cloud]
                return aiTabs
            case .app:
                var appTabs: [SettingsTab] = [.general, .browser, .telemetry]
                #if DEBUG
                appTabs.append(.dataManagement)
                #endif
                return appTabs
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsGroup.allCases) { group in
                    Section(group.rawValue) {
                        ForEach(group.tabs) { tab in
                            Label(tab.rawValue, systemImage: tab.icon)
                                .tag(tab)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            Group {
                switch selectedTab {
                case .compression:
                    compressionTab
                case .contextProcessing:
                    contextProcessingTab
                case .browser:
                    browserTab
                case .cloud:
                    cloudTab
                case .general:
                    generalTab
                case .telemetry:
                    telemetryTab
                #if DEBUG
                case .dataManagement:
                    dataManagementTab
                #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 650, minHeight: 400)
    }

    // MARK: - Browser Tab

    private var browserTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Browser Integration") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable browser integration", isOn: Binding(
                            get: { preferences.browserIntegrationEnabled },
                            set: { newValue in
                                preferences.browserIntegrationEnabled = newValue
                                if newValue {
                                    Task { await browserBridge.start() }
                                } else {
                                    Task { await browserBridge.stop() }
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.regular)

                        Text("Start the embedded server on launch and allow the Chrome extension to connect.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Divider()

                        Toggle("Auto-send to browser after compression", isOn: Binding(
                            get: { preferences.autoSendToBrowser },
                            set: { preferences.autoSendToBrowser = $0 }
                        ))
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                            .disabled(!preferences.browserIntegrationEnabled)

                        Text("After compressing, automatically inject the compressed prompt into the active AI chat tab.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Divider()

                        Toggle("Auto-submit to AI", isOn: Binding(
                            get: { preferences.autoSubmitToAI },
                            set: { preferences.autoSubmitToAI = $0 }
                        ))
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                            .disabled(!preferences.browserIntegrationEnabled || !preferences.autoSendToBrowser)

                        Text("Simulate Enter after injecting (requires auto-send).")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Divider()

                        HStack {
                            Text("Server port")
                                .font(.system(size: 12, weight: .medium))
                            TextField("", text: Binding(
                                get: {
                                    if embeddedServerPortText.isEmpty {
                                        return String(preferences.embeddedServerPort)
                                    }
                                    return embeddedServerPortText
                                },
                                set: { newValue in
                                    let digits = String(newValue.filter(\.isNumber).prefix(5))
                                    guard !digits.isEmpty else {
                                        embeddedServerPortText = ""
                                        return
                                    }

                                    if let port = Int(digits), validPortRange.contains(port) {
                                        embeddedServerPortText = digits
                                        preferences.embeddedServerPort = port
                                    } else {
                                        embeddedServerPortText = String(preferences.embeddedServerPort)
                                    }
                                }
                            ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .disabled(browserBridge.isRunning)
                                .onAppear {
                                    embeddedServerPortText = String(preferences.embeddedServerPort)
                                }
                                .onSubmit {
                                    embeddedServerPortText = String(preferences.embeddedServerPort)
                                }
                        }

                        HStack(spacing: 16) {
                            if browserBridge.isRunning {
                                Label("Server running", systemImage: "circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            } else if let error = browserBridge.lastError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }

                            if browserBridge.isExtensionConnected {
                                Label("\(browserBridge.connectedClientCount) client(s) connected", systemImage: "link")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            } else {
                                Label("No clients connected", systemImage: "circle.slash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Authentication") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bearer token (for Chrome extension setup)")
                            .font(.system(size: 12, weight: .medium))

                        HStack {
                            SecureField("Token", text: $displayedAuthToken)
                                .textFieldStyle(.roundedBorder)
                                .disabled(true)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(displayedAuthToken, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Reset") {
                                displayedAuthToken = browserBridge.resetAuthToken()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !browserBridge.isExtensionConnected && preferences.browserIntegrationEnabled {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Extension not connected. Copy the token above and paste it into the Chrome extension's Settings.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(6)
                        } else {
                            Text("Copy this token to the Chrome extension's settings to authenticate the connection.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
        .onAppear {
            displayedAuthToken = browserBridge.authToken()
        }
    }

    // MARK: - Telemetry Tab

    private var telemetryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                telemetryServiceEventsBox
                telemetryBackendPerformanceBox
                telemetryRecentHistoryBox
                telemetryActionsRow
            }
            .padding(20)
        }
        .onAppear {
            if selectedTab == .telemetry {
                Task { await compressionService.checkAvailability() }
            }
        }
    }

    private var telemetryServiceEventsBox: some View {
        let telemetry = CompressionTelemetry.shared
        return GroupBox("Service Events") {
            VStack(alignment: .leading, spacing: 8) {
                if telemetry.serviceEvents.isEmpty {
                    Text("No service events recorded yet this session.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(telemetry.serviceEvents) { event in
                        HStack {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(event.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(event.duration, format: .number)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var telemetryBackendPerformanceBox: some View {
        let telemetry = CompressionTelemetry.shared
        let stats = telemetry.backendStats
        return GroupBox("Backend Performance") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Calls: \(telemetry.recordings.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Divider()
                telemetryPerformanceHeader
                Divider()
                ForEach(Array(stats.keys).sorted(by: { $0.rawValue < $1.rawValue })) { backend in
                    if let stat = stats[backend] {
                        telemetryPerformanceRow(backend: backend, stat: stat)
                    }
                }
                Text("* First inference includes model load time")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    private var telemetryPerformanceHeader: some View {
        HStack {
            Text("Backend")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 160, alignment: .leading)
            Text("Calls")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 50, alignment: .trailing)
            Text("Avg")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 60, alignment: .trailing)
            Text("First*")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 60, alignment: .trailing)
            Text("Best")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 60, alignment: .trailing)
            Text("Last")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 60, alignment: .trailing)
        }
    }

    private func telemetryPerformanceRow(backend: CompressorType, stat: BackendStats) -> some View {
        HStack {
            Text(backend.rawValue)
                .font(.system(size: 11))
                .frame(width: 160, alignment: .leading)
            Text("\(stat.callCount)")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
            Text(stat.avgTime, format: .number)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
            Text(stat.firstInferenceDuration == .infinity ? "—" : String(format: "%.1f", stat.firstInferenceDuration))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
            Text(stat.bestTime == .infinity ? "—" : String(format: "%.1f", stat.bestTime))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
            Text(stat.lastDuration == 0 ? "—" : String(format: "%.1f", stat.lastDuration))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var telemetryRecentHistoryBox: some View {
        let telemetry = CompressionTelemetry.shared
        return GroupBox("Recent History (last 20)") {
            VStack(alignment: .leading, spacing: 4) {
                telemetryHistoryHeader
                Divider()
                ForEach(telemetry.recordings.prefix(20)) { timing in
                    telemetryHistoryRow(timing: timing)
                }
            }
            .padding(8)
        }
    }

    private var telemetryHistoryHeader: some View {
        HStack {
            Text("Backend")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 130, alignment: .leading)
            Text("Model")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 120, alignment: .leading)
            Text("In")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 40, alignment: .trailing)
            Text("Out")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 40, alignment: .trailing)
            Text("Ratio")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 50, alignment: .trailing)
            Text("Time")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 55, alignment: .trailing)
            Text("")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 15, alignment: .trailing)
        }
    }

    private func telemetryHistoryRow(timing: CompressionTiming) -> some View {
        HStack {
            Text(timing.backend.rawValue)
                .font(.system(size: 10))
                .frame(width: 130, alignment: .leading)
            Text(timing.modelName)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 120, alignment: .leading)
            Text("\(timing.inputTokens)")
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
            Text("\(timing.outputTokens)")
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
            Text(timing.ratio, format: .percent)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
            Text(timing.duration, format: .number)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 55, alignment: .trailing)
            Text(timing.isFirstInference ? "cold" : "")
                .font(.system(size: 9))
                .foregroundColor(.orange)
                .frame(width: 15, alignment: .trailing)
            Image(systemName: timing.success ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 9))
                .foregroundColor(timing.success ? .green : .red)
                .frame(width: 15, alignment: .trailing)
        }
    }

    private var telemetryActionsRow: some View {
        let telemetry = CompressionTelemetry.shared
        return HStack {
            Button("Reset Cold-Start Markers") {
                telemetry.resetColdStartMarkers()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!telemetry.hasSeenModels)
            Spacer()
            Button("Clear All") {
                telemetry.clear()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(.red)
            .disabled(telemetry.recordings.isEmpty)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Data Management Tab (DEBUG)

    #if DEBUG
    private var dataManagementTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("DEBUG — Clear all rows from persistent stores. This cannot be undone.")
                    .font(.system(size: 11))
                    .foregroundColor(.red)

                GroupBox("SwiftData Store") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deletes all rows from: PromptRecord, ContextItem, URLRecord, ContextItemURLLink, EntityRecord, ContextItemEntityLink, ImageAsset, ContextItemImageLink")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if !swiftDataClearStatus.isEmpty {
                            Text(swiftDataClearStatus)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(swiftDataClearStatus.hasPrefix("Error") ? .red : .green)
                        }

                        Button("Clear SwiftData") {
                            clearSwiftData()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                    .padding(8)
                }

                GroupBox("Vector Store") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deletes all embeddings from vectors.db (SQLiteVec table: \(VectorizationService.shared.providerDisplayName))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if !vectorStoreClearStatus.isEmpty {
                            Text(vectorStoreClearStatus)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(vectorStoreClearStatus.hasPrefix("Error") ? .red : .green)
                        }

                        Button("Clear Vector Store") {
                            clearVectorStore()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                    .padding(8)
                }

                GroupBox("Blob Store") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deletes all files from the blob storage directory (content-addressed assets, screenshots, etc.)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if !blobStoreClearStatus.isEmpty {
                            Text(blobStoreClearStatus)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(blobStoreClearStatus.hasPrefix("Error") ? .red : .green)
                        }

                        Button("Clear Blob Store") {
                            clearBlobStore()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
    }

    private func clearSwiftData() {
        swiftDataClearStatus = "Clearing..."
        do {
            let context = modelContext

            let promptRecords: [PromptRecord] = try context.fetch(FetchDescriptor())
            for record in promptRecords { context.delete(record) }

            let contextItems: [ContextItem] = try context.fetch(FetchDescriptor())
            for item in contextItems { context.delete(item) }

            let urlRecords: [URLRecord] = try context.fetch(FetchDescriptor())
            for record in urlRecords { context.delete(record) }

            let urlLinks: [ContextItemURLLink] = try context.fetch(FetchDescriptor())
            for link in urlLinks { context.delete(link) }

            let entityRecords: [EntityRecord] = try context.fetch(FetchDescriptor())
            for record in entityRecords { context.delete(record) }

            let entityLinks: [ContextItemEntityLink] = try context.fetch(FetchDescriptor())
            for link in entityLinks { context.delete(link) }

            let imageAssets: [ImageAsset] = try context.fetch(FetchDescriptor())
            for asset in imageAssets { context.delete(asset) }

            let imageLinks: [ContextItemImageLink] = try context.fetch(FetchDescriptor())
            for link in imageLinks { context.delete(link) }

            try context.save()
            swiftDataClearStatus = "All SwiftData rows deleted"
        } catch {
            swiftDataClearStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func clearVectorStore() {
        vectorStoreClearStatus = "Clearing..."
        Task {
            do {
                try await VectorizationService.shared.deleteAllEmbeddings()
                await MainActor.run {
                    vectorStoreClearStatus = "Cleared all vector embeddings"
                }
            } catch {
                await MainActor.run {
                    vectorStoreClearStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearBlobStore() {
        blobStoreClearStatus = "Clearing..."
        do {
            try BlobStore.shared.clearAll()
            blobStoreClearStatus = "Cleared all blobs"
        } catch {
            blobStoreClearStatus = "Error: \(error.localizedDescription)"
        }
    }
    #endif

    // MARK: - Compression Tab

    private var compressionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Compression Backend") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(CompressorType.allCases, id: \.self) { type in
                            HStack {
                                ZStack {
                                    Circle()
                                        .stroke(Color.secondary, lineWidth: 1.5)
                                        .frame(width: 16, height: 16)

                                    if compressionService.selectedCompressor == type {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 8, height: 8)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(type.rawValue)
                                            .font(.system(size: 13, weight: .medium))

                                        if type == .localLLM {
                                            if isLocalLLMAvailable {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.system(size: 10))
                                            } else {
                                                Image(systemName: "arrow.down.circle.fill")
                                                    .foregroundColor(.orange)
                                                    .font(.system(size: 10))
                                            }
                                        }
                                    }
                                    Text(type.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                compressionService.selectedCompressor = type
                                compressionService.saveSelectedCompressor(type)
                            }
                        }
                    }
                    .padding(8)
                }

                if compressionService.selectedCompressor == .localLLM {
                    GroupBox("Local LLM Configuration") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                if isLocalLLMAvailable {
                                    Label("Model ready", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Text("\(compressionService.selectedLocalModel.displayName) (\(String(format: "%.1f", compressionService.selectedLocalModel.sizeGB)) GB)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                } else if compressionService.downloadedModelID != nil {
                                    Label("Selected model not downloaded", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12))
                                    Spacer()
                                } else {
                                    Label("Model not downloaded", systemImage: "arrow.down.circle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12))
                                    Spacer()
                                }
                            }

                            Picker("Model", selection: $compressionService.selectedLocalModel) {
                                ForEach(LocalLLMModel.curatedModels) { model in
                                    HStack {
                                        Text(model.displayName)
                                        Spacer()
                                        Text(String(format: "%.1f GB", model.sizeGB))
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(model)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 360, alignment: .leading)

                            if isLocalLLMAvailable {
                                Divider()

                                HStack(spacing: 8) {
                                    Button("Re-download Model") {
                                        let model = compressionService.selectedLocalModel
                                        Task {
                                            do {
                                                try await compressionService.downloadLocalLLMModel(model)
                                            } catch {
                                                logger.error("Failed to download model: \(error)")
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Delete Model") {
                                        compressionService.deleteLocalLLMModel()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .foregroundColor(.red)
                                }

                                if compressionService.isDownloading {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: compressionService.modelDownloadProgress, total: 1.0)
                                            .progressViewStyle(.linear)

                                        let model = compressionService.selectedLocalModel
                                        Text("\(Int(compressionService.modelDownloadProgress * 100))% — \(String(format: "%.1f", compressionService.modelDownloadProgress * model.sizeGB)) / \(String(format: "%.1f", model.sizeGB)) GB")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Text("Re-download to update to the latest model version.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                Divider()

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Download Model")
                                        .font(.system(size: 12, weight: .medium))

                                    if compressionService.isDownloading {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ProgressView(value: compressionService.modelDownloadProgress, total: 1.0)
                                                .progressViewStyle(.linear)

                                            let model = compressionService.selectedLocalModel
                                            Text("\(Int(compressionService.modelDownloadProgress * 100))% — \(String(format: "%.1f", compressionService.modelDownloadProgress * model.sizeGB)) / \(String(format: "%.1f", model.sizeGB)) GB")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        Button("Download \(compressionService.selectedLocalModel.displayName) (\(String(format: "%.1f", compressionService.selectedLocalModel.sizeGB)) GB)") {
                                            let model = compressionService.selectedLocalModel
                                            Task {
                                                do {
                                                    try await compressionService.downloadLocalLLMModel(model)
                                                } catch {
                                                    logger.error("Failed to download model: \(error)")
                                                }
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)

                                        Text("Phi-4 Mini recommended for best speed. Larger models give better quality but use more RAM.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                }

                if compressionService.selectedCompressor == .openRouter {
                    GroupBox("OpenRouter Compression Model") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Compression uses its own cloud model so prompt compression stays separate from entity extraction and summarization.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            if !hasOpenRouterKey {
                                warningLabel("Add an OpenRouter API key in the Cloud tab to use cloud compression.")
                            }

                            Picker("Model", selection: $compressionOpenRouterModel) {
                                ForEach(compressionOpenRouterOptions) { option in
                                    Text(option.menuLabel)
                                        .tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 360, alignment: .leading)
                            .disabled(useCustomCompressionOpenRouterModel)
                            .onChange(of: compressionOpenRouterModel) { _, newValue in
                                guard !useCustomCompressionOpenRouterModel else { return }
                                saveCompressionOpenRouterModel(newValue)
                            }

                            Toggle("Use custom model ID", isOn: Binding(
                                get: { useCustomCompressionOpenRouterModel },
                                set: { enabled in
                                    useCustomCompressionOpenRouterModel = enabled
                                    if enabled {
                                        customCompressionOpenRouterModel = compressionOpenRouterModel
                                        saveCompressionOpenRouterModel(customCompressionOpenRouterModel)
                                    } else {
                                        saveCompressionOpenRouterModel(compressionOpenRouterModel)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .controlSize(.small)

                            if useCustomCompressionOpenRouterModel {
                                TextField("Custom compression model ID", text: $customCompressionOpenRouterModel)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: customCompressionOpenRouterModel) { _, newValue in
                                        saveCompressionOpenRouterModel(newValue)
                                    }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            loadOpenRouterSettings()
            if hasOpenRouterKey {
                refreshOpenRouterCatalogIfNeeded()
            }
        }
    }

    // MARK: - Context Processing Tab

    private var contextProcessingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Entity Extraction") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose how Vapor extracts entities from captured context. This backend is independent from prompt compression.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        ForEach(EntityExtractionBackend.allCases, id: \.rawValue) { backend in
                            selectableSettingsRow(
                                title: backend.displayName,
                                description: backendDescription(for: backend),
                                isSelected: extractionBackend == backend
                            )
                            .onTapGesture {
                                extractionBackend = backend
                                UserDefaults.standard.set(backend.rawValue, forKey: "entityExtractionBackend")
                            }
                        }

                        switch extractionBackend {
                        case .openRouter:
                            Divider()

                            if !hasOpenRouterKey {
                                warningLabel("Add an OpenRouter API key in the Cloud tab to use cloud entity extraction.")
                            }

                            Picker("OpenRouter entity model", selection: $extractionOpenRouterModel) {
                                ForEach(extractionOpenRouterOptions) { option in
                                    Text(option.menuLabel)
                                        .tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 360, alignment: .leading)
                            .disabled(useCustomExtractionOpenRouterModel)
                            .onChange(of: extractionOpenRouterModel) { _, newValue in
                                guard !useCustomExtractionOpenRouterModel else { return }
                                saveExtractionOpenRouterModel(newValue)
                            }

                            Toggle("Use custom model ID", isOn: Binding(
                                get: { useCustomExtractionOpenRouterModel },
                                set: { enabled in
                                    useCustomExtractionOpenRouterModel = enabled
                                    if enabled {
                                        customExtractionOpenRouterModel = extractionOpenRouterModel
                                        saveExtractionOpenRouterModel(customExtractionOpenRouterModel)
                                    } else {
                                        saveExtractionOpenRouterModel(extractionOpenRouterModel)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .controlSize(.small)

                            if useCustomExtractionOpenRouterModel {
                                TextField("Custom entity extraction model ID", text: $customExtractionOpenRouterModel)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: customExtractionOpenRouterModel) { _, newValue in
                                        saveExtractionOpenRouterModel(newValue)
                                    }
                            }
                        case .nlTagger:
                            Divider()
                            Text("Uses Apple's built-in NLTagger. No external model selection is required.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Summarization") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summaries can follow entity extraction or use their own OpenRouter model.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        ForEach(SummarizationBackendPreference.allCases, id: \.rawValue) { option in
                            selectableSettingsRow(
                                title: option.displayName,
                                description: option.description,
                                isSelected: summarizationBackend == option
                            )
                            .onTapGesture {
                                summarizationBackend = option
                                UserDefaults.standard.set(option.rawValue, forKey: "summarizationBackend")
                            }
                        }

                        switch summarizationBackend {
                        case .sameAsEntityExtraction:
                            Divider()
                            Text(effectiveSummarizationDescription)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        case .openRouter:
                            Divider()

                            if !hasOpenRouterKey {
                                warningLabel("Add an OpenRouter API key in the Cloud tab to use cloud summarization.")
                            }

                            Picker("OpenRouter summarization model", selection: $summarizationOpenRouterModel) {
                                ForEach(summarizationOpenRouterOptions) { option in
                                    Text(option.menuLabel)
                                        .tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 360, alignment: .leading)
                            .disabled(useCustomSummarizationOpenRouterModel)
                            .onChange(of: summarizationOpenRouterModel) { _, newValue in
                                guard !useCustomSummarizationOpenRouterModel else { return }
                                saveSummarizationOpenRouterModel(newValue)
                            }

                            Toggle("Use custom model ID", isOn: Binding(
                                get: { useCustomSummarizationOpenRouterModel },
                                set: { enabled in
                                    useCustomSummarizationOpenRouterModel = enabled
                                    if enabled {
                                        customSummarizationOpenRouterModel = summarizationOpenRouterModel
                                        saveSummarizationOpenRouterModel(customSummarizationOpenRouterModel)
                                    } else {
                                        saveSummarizationOpenRouterModel(summarizationOpenRouterModel)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .controlSize(.small)

                            if useCustomSummarizationOpenRouterModel {
                                TextField("Custom summarization model ID", text: $customSummarizationOpenRouterModel)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: customSummarizationOpenRouterModel) { _, newValue in
                                        saveSummarizationOpenRouterModel(newValue)
                                    }
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Fallback Chain") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fallbackDescription)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
        .onAppear {
            loadContextProcessingSettings()
            loadOpenRouterSettings()
            if hasOpenRouterKey {
                refreshOpenRouterCatalogIfNeeded()
            }
        }
    }

    private func backendDescription(for backend: EntityExtractionBackend) -> String {
        switch backend {
        case .openRouter: "Uses cheap cloud models. Fast, no local GPU needed."
        case .nlTagger: "Built-in macOS NLP. No setup, but lower accuracy."
        }
    }

    private var fallbackDescription: String {
        switch extractionBackend {
        case .openRouter:
            return "OpenRouter → NLTagger (fallback). If the cloud model returns no entities, the built-in tagger is used."
        case .nlTagger:
            return "NLTagger only. No fallback — uses Apple's built-in NLP for entity extraction."
        }
    }

    // MARK: - Cloud Tab

    private var cloudTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("OpenRouter API") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                            SecureField("Enter your OpenRouter API key", text: $openRouterApiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: openRouterApiKey) { _, newValue in
                                    compressionService.setOpenRouterApiKey(newValue, model: selectedCompressionOpenRouterModel)
                                }
                        }

                        Text("The Cloud tab only manages authentication and the live model catalog. Compression, entity extraction, and summarization each choose their own cloud model in their respective tabs.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button("Refresh Catalog") {
                                refreshOpenRouterCatalogIfNeeded(force: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if openRouterModelService.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Spacer()

                            if let lastUpdatedAt = openRouterModelService.lastUpdatedAt {
                                Text("Updated \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Model Catalog") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Search models", text: $cloudModelSearchText)
                            .textFieldStyle(.roundedBorder)

                        Text(modelCatalogStatusText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        if let lastError = openRouterModelService.lastError {
                            warningLabel(lastError)
                        }

                        if cloudCatalogModels.isEmpty {
                            Text("No cloud models loaded yet. Paste an API key and refresh the catalog.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(cloudCatalogModels.prefix(80)) { model in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.name)
                                                .font(.system(size: 12, weight: .medium))
                                            Text(model.id)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(model.contextLabel)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }

                                    Text("\(model.pricingLabel) · \(model.modalityLabel)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)

                                    if !model.description.isEmpty {
                                        Text(model.description)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
        .onAppear {
            loadOpenRouterSettings()
            refreshOpenRouterCatalogIfNeeded()
        }
    }

    private var hasOpenRouterKey: Bool {
        !openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var effectiveSummarizationDescription: String {
        switch extractionBackend {
        case .openRouter:
            return "Summarization will reuse the entity extraction OpenRouter backend and model: \(selectedExtractionModel)."
        case .nlTagger:
            if compressionService.isSelectedLocalModelDownloaded {
                return "Entity extraction uses NLTagger, which cannot summarize. Vapor will use the downloaded local model for summaries: \(compressionService.selectedLocalModel.displayName)."
            }
            return "Entity extraction uses NLTagger, which cannot summarize. Set up OpenRouter or download the selected local model for summarization support."
        }
    }

    private var selectedCompressionOpenRouterModel: String {
        normalizeModelID(useCustomCompressionOpenRouterModel ? customCompressionOpenRouterModel : compressionOpenRouterModel)
    }

    private var selectedExtractionModel: String {
        normalizeModelID(useCustomExtractionOpenRouterModel ? customExtractionOpenRouterModel : extractionOpenRouterModel)
    }

    private var selectedSummarizationModel: String {
        normalizeModelID(useCustomSummarizationOpenRouterModel ? customSummarizationOpenRouterModel : summarizationOpenRouterModel)
    }

    private var compressionOpenRouterOptions: [OpenRouterPickerOption] {
        openRouterPickerOptions(for: .compression, currentSelection: selectedCompressionOpenRouterModel)
    }

    private var extractionOpenRouterOptions: [OpenRouterPickerOption] {
        openRouterPickerOptions(for: .extraction, currentSelection: selectedExtractionModel)
    }

    private var summarizationOpenRouterOptions: [OpenRouterPickerOption] {
        openRouterPickerOptions(for: .summarization, currentSelection: selectedSummarizationModel)
    }

    private var cloudCatalogModels: [OpenRouterCatalogModel] {
        let query = cloudModelSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return openRouterModelService.models
            .filter { model in
                guard !query.isEmpty else { return true }
                return model.id.localizedCaseInsensitiveContains(query)
                    || model.name.localizedCaseInsensitiveContains(query)
                    || model.description.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                lhs.contextLength > rhs.contextLength
            }
    }

    private var modelCatalogStatusText: String {
        if openRouterModelService.isLoading {
            return "Loading the live OpenRouter catalog..."
        }
        if cloudCatalogModels.isEmpty {
            return "The catalog helps you pick task-specific cloud models for compression, entity extraction, and summarization."
        }
        return "Showing \(cloudCatalogModels.count) text-capable cloud models from OpenRouter."
    }

    @ViewBuilder
    private func selectableSettingsRow(title: String, description: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.gray.opacity(0.06))
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func warningLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func loadContextProcessingSettings() {
        if let raw = UserDefaults.standard.string(forKey: "entityExtractionBackend"),
           let value = EntityExtractionBackend(rawValue: raw) {
            extractionBackend = value
        } else if hasOpenRouterKey {
            extractionBackend = .openRouter
        } else {
            extractionBackend = .nlTagger
        }

        let savedExtractionModel = normalizeModelID(UserDefaults.standard.string(forKey: "entityExtractionModel") ?? NERModel.defaultModel)
        extractionOpenRouterModel = savedExtractionModel.isEmpty ? NERModel.defaultModel : savedExtractionModel
        useCustomExtractionOpenRouterModel = !knownOpenRouterModelIDs.contains(extractionOpenRouterModel)
        customExtractionOpenRouterModel = useCustomExtractionOpenRouterModel ? extractionOpenRouterModel : ""

        if let raw = UserDefaults.standard.string(forKey: "summarizationBackend"),
           let value = SummarizationBackendPreference(rawValue: raw) {
            summarizationBackend = value
        } else {
            summarizationBackend = .sameAsEntityExtraction
        }

        let savedSummarizationModel = normalizeModelID(UserDefaults.standard.string(forKey: "summarizationModel") ?? "")
        if savedSummarizationModel.isEmpty {
            summarizationOpenRouterModel = extractionOpenRouterModel
            useCustomSummarizationOpenRouterModel = false
            customSummarizationOpenRouterModel = ""
        } else {
            summarizationOpenRouterModel = savedSummarizationModel
            useCustomSummarizationOpenRouterModel = !knownOpenRouterModelIDs.contains(savedSummarizationModel)
            customSummarizationOpenRouterModel = useCustomSummarizationOpenRouterModel ? savedSummarizationModel : ""
        }
    }

    private func loadOpenRouterSettings() {
        openRouterApiKey = UserDefaults.standard.string(forKey: "openRouterApiKey") ?? ""

        let savedCompressionModel = normalizeModelID(UserDefaults.standard.string(forKey: "openRouterModel") ?? compressionService.openRouterModel)
        compressionOpenRouterModel = savedCompressionModel.isEmpty ? "glm-5" : savedCompressionModel
        useCustomCompressionOpenRouterModel = !knownOpenRouterModelIDs.contains(compressionOpenRouterModel)
        customCompressionOpenRouterModel = useCustomCompressionOpenRouterModel ? compressionOpenRouterModel : ""
    }

    private func saveCompressionOpenRouterModel(_ model: String) {
        let normalized = normalizeModelID(model)
        guard !normalized.isEmpty else { return }
        compressionOpenRouterModel = normalized
        compressionService.setOpenRouterApiKey(openRouterApiKey, model: normalized)
    }

    private func saveExtractionOpenRouterModel(_ model: String) {
        let normalized = normalizeModelID(model)
        guard !normalized.isEmpty else { return }
        extractionOpenRouterModel = normalized
        UserDefaults.standard.set(normalized, forKey: "entityExtractionModel")
    }

    private func saveSummarizationOpenRouterModel(_ model: String) {
        let normalized = normalizeModelID(model)
        guard !normalized.isEmpty else { return }
        summarizationOpenRouterModel = normalized
        UserDefaults.standard.set(normalized, forKey: "summarizationModel")
    }

    private func refreshOpenRouterCatalogIfNeeded(force: Bool = false) {
        Task {
            await openRouterModelService.refreshIfNeeded(apiKey: openRouterApiKey, force: force)
        }
    }

    private func openRouterPickerOptions(for purpose: OpenRouterModelPurpose, currentSelection: String) -> [OpenRouterPickerOption] {
        var options = openRouterModelService.models(for: purpose).map { OpenRouterPickerOption(model: $0) }
        if options.isEmpty {
            options = fallbackOpenRouterOptions(for: purpose)
        }

        let normalizedSelection = normalizeModelID(currentSelection)
        if !normalizedSelection.isEmpty && !options.contains(where: { $0.id == normalizedSelection }) {
            options.insert(OpenRouterPickerOption(id: normalizedSelection, title: normalizedSelection, detail: "Current saved model"), at: 0)
        }

        return options
    }

    private func fallbackOpenRouterOptions(for purpose: OpenRouterModelPurpose) -> [OpenRouterPickerOption] {
        switch purpose {
        case .compression:
            return [
                OpenRouterPickerOption(id: "glm-5", title: "GLM-5", detail: "Cheap and fast"),
                OpenRouterPickerOption(id: NERModel.defaultModel, title: "Gemma 3N E4B", detail: "Balanced general-purpose model")
            ]
        case .extraction, .summarization:
            return NERModel.curatedModels.map { model in
                OpenRouterPickerOption(id: model.id, title: model.displayName, detail: model.priceLabel)
            }
        }
    }

    private var knownOpenRouterModelIDs: Set<String> {
        Set(fallbackOpenRouterOptions(for: .compression).map(\.id))
            .union(fallbackOpenRouterOptions(for: .extraction).map(\.id))
            .union(openRouterModelService.models.map(\.id))
    }

    private func normalizeModelID(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Automation") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-compress when dictation ends", isOn: Binding(
                            get: { preferences.autoCompressEnabled },
                            set: {
                                preferences.autoCompressEnabled = $0
                                if $0 { preferences.autoCopyOriginalEnabled = false }
                            }
                        ))
                        .font(.system(size: 13))

                        Text("Automatically compress & copy when you stop speaking.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Toggle("Auto-copy original when dictation ends", isOn: Binding(
                            get: { preferences.autoCopyOriginalEnabled },
                            set: { preferences.autoCopyOriginalEnabled = $0 }
                        ))
                        .font(.system(size: 13))
                        .disabled(preferences.autoCompressEnabled)

                        Text("Copy the uncompressed dictated text to clipboard when you stop speaking. This does not create a prompt-history entry unless you explicitly use Copy Original.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Toggle("Auto-minimize after compress & copy", isOn: Binding(
                            get: { preferences.autoMinimizeEnabled },
                            set: { preferences.autoMinimizeEnabled = $0 }
                        ))
                        .font(.system(size: 13))

                        Text("Collapse window to pill after copying, so you can paste immediately.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("Advanced") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show experiments button in toolbar", isOn: Binding(
                            get: { preferences.showExperimentsButton },
                            set: { preferences.showExperimentsButton = $0 }
                        ))
                        .font(.system(size: 13))

                        Text("Show the OpenRouter test utility window button in the toolbar.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Toggle("Enable research workspace", isOn: Binding(
                            get: { preferences.researchToolsEnabled },
                            set: { preferences.researchToolsEnabled = $0 }
                        ))
                        .font(.system(size: 13))

                        Text("Show the Compose/Research workspace switcher while research tools are still under active design.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("Vectorization") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: vectorizationService.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(vectorizationService.isReady ? .green : .orange)
                            Text(vectorizationService.isReady ? "MiniLM embeddings ready" : "MiniLM embeddings unavailable")
                                .font(.system(size: 13, weight: .medium))
                        }

                        Text("Provider: \(vectorizationService.providerDisplayName)")
                            .font(.system(size: 12))

                        Text("Indexed vectors: \(vectorizationService.indexedVectorCount)")
                            .font(.system(size: 12))

                        if let lastError = vectorizationService.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Global Hotkey") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Activate Vapor from any app:")
                                .font(.system(size: 13))
                            KeyboardShortcuts.Recorder(for: .toggleVapor)
                                .frame(width: 150)
                        }

                        Text("Default: \u{2303}\u{2325}Space (Control+Option+Space). You can change it by clicking the recorder.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text("When you first set a hotkey, macOS will ask for Input Monitoring permission. Grant it to enable the global shortcut.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("Onboarding") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                            NSApp.activate(ignoringOtherApps: true)
                            NotificationCenter.default.post(name: .vaporShowOnboarding, object: nil)
                        } label: {
                            Label("Show Onboarding", systemImage: "hand.wave.fill")
                        }
                        .font(.system(size: 13))

                        Text("Replay the first-launch setup walkthrough.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct OpenRouterPickerOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String

    init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }

    init(model: OpenRouterCatalogModel) {
        id = model.id
        title = model.name
        detail = "\(model.pricingLabel) · \(model.contextLabel)"
    }

    var menuLabel: String {
        detail.isEmpty ? title : "\(title) · \(detail)"
    }
}
