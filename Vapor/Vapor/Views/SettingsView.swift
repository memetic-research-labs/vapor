import SwiftUI
import KeyboardShortcuts
import OSLog

private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "Settings")

struct SettingsView: View {
    let compressionService: CompressionService
    let preferences: UserPreferences
    @Environment(BrowserBridge.self) private var browserBridge
    @Environment(VectorizationService.self) private var vectorizationService
    @State private var openRouterModelService = OpenRouterModelService()
    @State private var openRouterApiKey: String = ""
    @State private var compressionOpenRouterModel: String = "glm-5"
    @State private var useCustomCompressionOpenRouterModel: Bool = false
    @State private var customCompressionOpenRouterModel: String = ""
    @State private var isLocalLLMAvailable: Bool = false
    @State private var isOllamaAvailable: Bool = false
    @State private var ollamaError: String = ""
    @State private var pullModelName: String = ""
    @State private var showCustomPull: Bool = false
    @State private var isConnecting: Bool = false
    @State private var selectedTab: SettingsTab = .compression
    @State private var displayedAuthToken: String = ""
    @State private var embeddedServerPortText: String = ""
    @State private var extractionBackend: EntityExtractionBackend = .ollama
    @State private var extractionOpenRouterModel: String = NERModel.defaultModel
    @State private var useCustomExtractionOpenRouterModel: Bool = false
    @State private var customExtractionOpenRouterModel: String = ""
    @State private var summarizationBackend: SummarizationBackendPreference = .sameAsEntityExtraction
    @State private var summarizationOpenRouterModel: String = NERModel.defaultModel
    @State private var useCustomSummarizationOpenRouterModel: Bool = false
    @State private var customSummarizationOpenRouterModel: String = ""
    @State private var cloudModelSearchText: String = ""

    enum SettingsTab: String, CaseIterable, Identifiable {
        case compression = "Compression"
        case contextProcessing = "Context Processing"
        case cloud = "Cloud"
        case ollama = "Ollama Models"
        case general = "General"
        case browser = "Browser"
        case telemetry = "Telemetry"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .compression: return "arrow.left.arrow.right"
            case .contextProcessing: return "sparkles.rectangle.stack"
            case .browser: return "globe"
            case .ollama: return "cpu"
            case .cloud: return "cloud"
            case .general: return "gearshape.2"
            case .telemetry: return "chart.bar"
            }
        }
    }

    enum SettingsGroup: String, CaseIterable, Identifiable {
        case ai = "AI & Models"
        case app = "App"

        var id: String { rawValue }

        var tabs: [SettingsTab] {
            switch self {
            case .ai:
                [.compression, .contextProcessing, .cloud, .ollama]
            case .app:
                [.general, .browser, .telemetry]
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
                case .ollama:
                    ollamaTab
                case .cloud:
                    cloudTab
                case .general:
                    generalTab
                case .telemetry:
                    telemetryTab
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
                                    embeddedServerPortText = digits
                                    if let port = Int(digits), !digits.isEmpty {
                                        preferences.embeddedServerPort = port
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

                        Text("Copy this token to the Chrome extension's settings to authenticate the connection.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
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

    // MARK: - Compression Tab

    private var compressionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Compression Backend") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(CompressorType.allCases.filter { $0 != .ruleBased }, id: \.self) { type in
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

                                        if type == .ollamaLLM {
                                            if isOllamaAvailable {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.system(size: 10))
                                            } else {
                                                Image(systemName: "circle.dashed")
                                                    .foregroundColor(.secondary)
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
                                    Text("Qwen2.5-7B Q4_K_M (~4.7 GB)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                } else {
                                    Label("Model not downloaded", systemImage: "arrow.down.circle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 12))
                                    Spacer()
                                }
                            }

                            if isLocalLLMAvailable {
                                Divider()

                                HStack(spacing: 8) {
                                    Button("Re-download Model") {
                                        compressionService.deleteLocalLLMModel()
                                        isLocalLLMAvailable = false
                                        Task {
                                            do {
                                                try await compressionService.downloadLocalLLMModel()
                                                isLocalLLMAvailable = true
                                            } catch {
                                                logger.error("Failed to download model: \(error)")
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Delete Model") {
                                        compressionService.deleteLocalLLMModel()
                                        isLocalLLMAvailable = false
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .foregroundColor(.red)
                                }

                                if compressionService.isDownloading {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: compressionService.modelDownloadProgress, total: 1.0)
                                            .progressViewStyle(.linear)

                                        Text("\(Int(compressionService.modelDownloadProgress * 100))% - \(formatBytes(Int(Double(4_900_000_000) * compressionService.modelDownloadProgress))) / 4.7 GB")
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

                                            Text("\(Int(compressionService.modelDownloadProgress * 100))% - \(formatBytes(Int(Double(4_900_000_000) * compressionService.modelDownloadProgress))) / 4.7 GB")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        Button("Download Qwen2.5-7B (4.7 GB)") {
                                            Task {
                                                do {
                                                    try await compressionService.downloadLocalLLMModel()
                                                    isLocalLLMAvailable = true
                                                } catch {
                                                    logger.error("Failed to download model: \(error)")
                                                }
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)

                                        Text("Recommended for best quality. Requires ~5GB storage.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onAppear {
                        Task {
                            isLocalLLMAvailable = compressionService.availableCompressors[.localLLM] ?? false
                        }
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

    // MARK: - Ollama Tab

    private var ollamaTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !ollamaError.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text(ollamaError)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Retry") {
                            Task { await startOllamaDaemon() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if isConnecting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Starting Ollama daemon...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else if compressionService.ollamaModels.isEmpty && ollamaError.isEmpty {
                    Text("No models installed yet. Choose one below.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text("Available Models")
                    .font(.system(size: 12, weight: .medium))

                ForEach(Self.recommendedModels) { model in
                    let isInstalled = compressionService.ollamaModels.contains(where: { $0.name == model.tag || $0.name == "library/\(model.tag)" })
                    let selectedModelTag = compressionService.ollamaSelectedModel.hasPrefix("library/")
                        ? String(compressionService.ollamaSelectedModel.dropFirst("library/".count))
                        : compressionService.ollamaSelectedModel
                    let isSelected = selectedModelTag == model.tag

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(model.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(isSelected ? .accentColor : .primary)

                                    if isInstalled && isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 10))
                                    } else if isInstalled {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 10))
                                    }
                                }

                                Text("\(model.size) · \(model.ram) RAM · \(model.modality)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            if compressionService.ollamaPullInProgress == model.tag {
                                ProgressView()
                                    .controlSize(.small)
                            } else if isInstalled {
                                Button("Select") {
                                    compressionService.setOllamaModel(model.tag)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .opacity(isSelected ? 0.3 : 1)
                                .disabled(isSelected)
                            } else {
                                Button("Pull") {
                                    pullRecommendedModel(model.tag)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }

                        if compressionService.ollamaPullInProgress == model.tag {
                            VStack(alignment: .leading, spacing: 4) {
                                if let pct = pullPercentage(from: compressionService.ollamaPullProgress) {
                                    ProgressView(value: pct, total: 100)
                                        .progressViewStyle(.linear)
                                        .frame(maxWidth: 250)
                                } else {
                                    ProgressView()
                                        .progressViewStyle(.linear)
                                        .frame(maxWidth: 250)
                                }
                                Text(compressionService.ollamaPullProgress)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if !compressionService.ollamaModels.isEmpty {
                    let customModels = compressionService.ollamaModels.filter { model in
                        let normalized = model.name.hasPrefix("library/")
                            ? String(model.name.dropFirst("library/".count))
                            : model.name
                        return !Self.recommendedModels.contains(where: { $0.tag == normalized })
                    }

                    if !customModels.isEmpty {
                        Divider()
                        Text("Other Installed Models")
                            .font(.system(size: 12, weight: .medium))

                        ForEach(customModels, id: \.name) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.system(size: 12))
                                        .foregroundColor(
                                            model.name == compressionService.ollamaSelectedModel
                                                ? .accentColor : .primary
                                        )
                                    if let size = model.size {
                                        Text(formatBytes(Int(size)))
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()

                                if model.name == compressionService.ollamaSelectedModel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 10))
                                }

                                Button {
                                    compressionService.setOllamaModel(model.name)
                                } label: {
                                    Text("Select")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .opacity(model.name == compressionService.ollamaSelectedModel ? 0.3 : 1)
                                .disabled(model.name == compressionService.ollamaSelectedModel)

                                Button {
                                    Task {
                                        try? await compressionService.deleteOllamaModel(model.name)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.red)
                            }
                        }
                    }
                }

                Divider()

                Button {
                    withAnimation { showCustomPull.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCustomPull ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                        Text("Pull custom model...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if showCustomPull {
                    HStack(spacing: 8) {
                        TextField("e.g. llama3:70b", text: $pullModelName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit { pullModel() }

                        if compressionService.isOllamaPulling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Pull") {
                                pullModel()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(pullModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    if compressionService.isOllamaPulling && compressionService.ollamaPullInProgress == nil {
                        VStack(alignment: .leading, spacing: 4) {
                            if let pct = pullPercentage(from: compressionService.ollamaPullProgress) {
                                ProgressView(value: pct, total: 100)
                                    .progressViewStyle(.linear)
                            } else {
                                ProgressView()
                                    .progressViewStyle(.linear)
                            }
                            Text(compressionService.ollamaPullProgress)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            Task { await startOllamaDaemon() }
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
                        case .ollama:
                            Divider()
                            Text("Shared local model: \(currentOllamaModel)")
                                .font(.system(size: 12, weight: .medium))
                            Text("Entity extraction uses the same Ollama model managed in the Ollama Models tab.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
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
                        Text("Summaries can either follow entity extraction, use their own OpenRouter model, or use the shared local Ollama model.")
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
                        case .ollama:
                            Divider()
                            Text("Shared local model: \(currentOllamaModel)")
                                .font(.system(size: 12, weight: .medium))
                            Text("Summarization uses the same Ollama model managed in the Ollama Models tab.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
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
        case .ollama: "Uses your local Ollama instance. Free but requires GPU."
        case .openRouter: "Uses cheap cloud models. Fast, no local GPU needed."
        case .nlTagger: "Built-in macOS NLP. No setup, but lower accuracy."
        }
    }

    private var fallbackDescription: String {
        switch extractionBackend {
        case .openRouter:
            return "OpenRouter → Ollama (fallback) → NLTagger (last resort). If the cloud model returns no entities, Ollama is tried, then the built-in tagger."
        case .ollama:
            return "Ollama → NLTagger (fallback). If Ollama returns no entities or is unavailable, the built-in tagger is used."
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

    private var currentOllamaModel: String {
        let saved = UserDefaults.standard.string(forKey: "ollamaSelectedModel")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty {
            return saved
        }
        return compressionService.ollamaSelectedModel
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

    private var effectiveSummarizationDescription: String {
        switch extractionBackend {
        case .openRouter:
            return "Summarization will reuse the entity extraction OpenRouter backend and model: \(selectedExtractionModel)."
        case .ollama:
            return "Summarization will reuse the shared Ollama model: \(currentOllamaModel)."
        case .nlTagger:
            return "Entity extraction uses NLTagger, which cannot summarize. Vapor will fall back to the shared Ollama model: \(currentOllamaModel)."
        }
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
            extractionBackend = .ollama
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

                        Text("Copy the uncompressed dictated text to clipboard when you stop speaking.")
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

                        Text("Show the OpenRouter test sidebar button in the expanded toolbar.")
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
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    private func startOllamaDaemon() async {
        ollamaError = ""
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await OllamaDaemonManager.shared.start()
        } catch OllamaDaemonError.binaryNotFound {
            ollamaError = "Ollama binary not found. Rebuild the project to download it."
            return
        } catch OllamaDaemonError.startupTimeout {
            ollamaError = "Ollama failed to start. Check Console.app for details."
            return
        } catch {
            ollamaError = "Failed to start Ollama: \(error.localizedDescription)"
            return
        }
        await compressionService.refreshOllamaModels()
        isOllamaAvailable = compressionService.availableCompressors[.ollamaLLM] ?? false
    }

    private func pullRecommendedModel(_ tag: String) {
        ollamaError = ""
        Task {
            do {
                try await compressionService.pullOllamaModel(tag)
            } catch {
                if (error as NSError).code == -1004 {
                    ollamaError = "Ollama daemon is not running. Tap Retry to restart it."
                } else {
                    ollamaError = "Failed to pull model: \(error.localizedDescription)"
                }
                logger.error("Failed to pull model: \(error)")
            }
        }
    }

    private func pullModel() {
        let name = pullModelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        pullModelName = ""
        ollamaError = ""
        Task {
            do {
                try await compressionService.pullOllamaModel(name)
            } catch {
                if (error as NSError).code == -1004 {
                    ollamaError = "Ollama daemon is not running. Tap Retry to restart it."
                } else {
                    ollamaError = "Failed to pull model: \(error.localizedDescription)"
                }
                logger.error("Failed to pull model: \(error)")
            }
        }
    }

    private func pullPercentage(from status: String) -> Double? {
        guard let range = status.range(of: #"\d+(?:\.\d+)?%"#, options: .regularExpression) else { return nil }
        let numStr = status[range].dropLast()
        return Double(numStr)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct RecommendedModel: Identifiable {
    let id = UUID()
    let tag: String
    let name: String
    let size: String
    let ram: String
    let modality: String

    static let all = [
        RecommendedModel(tag: "gemma4:e4b", name: "Gemma 4 E4B", size: "3.2 GB", ram: "~5 GB", modality: "Text, Image, Audio"),
        RecommendedModel(tag: "gemma4:e2b", name: "Gemma 4 E2B", size: "1.8 GB", ram: "~3 GB", modality: "Text, Image, Audio"),
        RecommendedModel(tag: "gemma4:26b", name: "Gemma 4 26B MoE", size: "9.6 GB", ram: "~12 GB", modality: "Text, Image"),
        RecommendedModel(tag: "gemma4:31b", name: "Gemma 4 31B", size: "18 GB", ram: "~20 GB", modality: "Text, Image"),
        RecommendedModel(tag: "qwen3:4b", name: "Qwen 3 4B", size: "2.5 GB", ram: "~4 GB", modality: "Text only"),
        RecommendedModel(tag: "qwen3:8b", name: "Qwen 3 8B", size: "5.2 GB", ram: "~7 GB", modality: "Text only"),
        RecommendedModel(tag: "qwen3:30b", name: "Qwen 3 30B MoE", size: "19 GB", ram: "~22 GB", modality: "Text only"),
        RecommendedModel(tag: "qwen2.5:7b", name: "Qwen 2.5 7B", size: "4.7 GB", ram: "~6 GB", modality: "Text only"),
        RecommendedModel(tag: "qwen2.5:14b", name: "Qwen 2.5 14B", size: "9.0 GB", ram: "~12 GB", modality: "Text only"),
        RecommendedModel(tag: "phi4:mini", name: "Phi-4 Mini", size: "1.5 GB", ram: "~2 GB", modality: "Text only")
    ]
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

extension SettingsView {
    static let recommendedModels = RecommendedModel.all
}
