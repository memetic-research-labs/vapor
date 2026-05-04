import Foundation
import OSLog

nonisolated private let openCodeLogger = Logger(subsystem: "lol.mrl.app.Vapor", category: "OpenCodeAdapter")

@MainActor
final class OpenCodeAdapter: SessionCaptureAdapter {
    let toolName = "opencode"

    private(set) var isRunning = false
    private var _onTurnCaptured: (@Sendable (CapturedTurn) async -> Void)?

    var onTurnCaptured: (@Sendable (CapturedTurn) async -> Void)? {
        get { _onTurnCaptured }
        set { _onTurnCaptured = newValue }
    }

    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileHandle: FileHandle?
    private var logFilePath: String?
    private var lastReadOffset: UInt64 = 0

    func isAvailable() async -> Bool {
        let path = resolveLogPath()
        if path != nil {
            logFilePath = path
            return true
        }
        return false
    }

    func startCapture() async throws {
        guard !isRunning else { return }

        let path = logFilePath ?? resolveLogPath()
        guard let path, FileManager.default.fileExists(atPath: path) else {
            throw OpenCodeAdapterError.logFileNotFound
        }

        logFilePath = path
        let fileURL = URL(fileURLWithPath: path)

        let fd = open(path, O_RDONLY)
        guard fd >= 0 else {
            throw OpenCodeAdapterError.failedToOpenLogFile
        }

        fileHandle = FileHandle(fileDescriptor: fd)
        if let handle = fileHandle {
            try? handle.seekToEnd()
            lastReadOffset = handle.offsetInFile
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue(label: "lol.mrl.app.Vapor.opencode-watcher", qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.readNewLines()
            }
        }

        source.setCancelHandler { [weak self] in
            close(fd)
            self?.isRunning = false
        }

        source.resume()
        dispatchSource = source
        isRunning = true

        openCodeLogger.info("OpenCode adapter watching: \(path, privacy: .public)")
        StatusBarService.shared.log("Watching OpenCode log: \(path)", domain: .system, level: .info)
    }

    func stopCapture() async {
        dispatchSource?.cancel()
        dispatchSource = nil
        try? fileHandle?.closeFile()
        fileHandle = nil
        isRunning = false
    }

    private func readNewLines() async {
        guard let handle = fileHandle, let path = logFilePath else { return }

        let currentSize = getFileSize(at: path)
        guard currentSize > lastReadOffset else { return }

        do {
            try handle.seek(toOffset: lastReadOffset)
            let newData = handle.readData(ofLength: Int(currentSize - lastReadOffset))
            lastReadOffset = handle.offsetInFile

            guard !newData.isEmpty, let text = String(data: newData, encoding: .utf8) else { return }

            let lines = text.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                parseAndEmit(jsonLine: trimmed)
            }
        } catch {
            openCodeLogger.error("Error reading log file: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private func parseAndEmit(jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8) else {
            Task { @MainActor in
                StatusBarService.shared.log(
                    "OpenCode: non-UTF8 line skipped",
                    domain: .system,
                    level: .error
                )
            }
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Task { @MainActor in
                StatusBarService.shared.log(
                    "OpenCode: malformed JSONL line skipped",
                    domain: .system,
                    level: .error
                )
            }
            return
        }

        guard let role = json["role"] as? String,
              let content = json["content"] as? String else {
            return
        }

        let timestamp: Date = if let ts = json["timestamp"] as? String {
            ISO8601DateFormatter().date(from: ts) ?? Date()
        } else {
            Date()
        }

        let modelID = json["model"] as? String
        let turn = CapturedTurn(
            role: role,
            content: content,
            capturedAt: timestamp,
            modelID: modelID,
            toolName: "opencode",
            durationSeconds: nil
        )

        Task { @MainActor in
            SessionCaptureFacade.shared.handleCapturedTurn(turn)
        }
    }

    private func resolveLogPath() -> String? {
        let candidates: [String] = [
            ProcessInfo.processInfo.environment["OPENCODE_LOG_DIR"].map { "\($0)/conversations.jsonl" } ?? "",
            ProcessInfo.processInfo.environment["XDG_DATA_HOME"].map { "\($0)/opencode/conversations.jsonl" } ?? "",
            "\(NSHomeDirectory())/Library/Application Support/opencode/conversations.jsonl",
            "\(NSHomeDirectory())/.local/share/opencode/conversations.jsonl",
            "\(NSHomeDirectory())/.config/opencode/conversations.jsonl",
        ]

        for path in candidates {
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { continue }
            return path
        }

        let configPaths: [String] = [
            ProcessInfo.processInfo.environment["OPENCODE_CONFIG_DIR"] ?? "",
            "\(NSHomeDirectory())/.config/opencode/",
        ]

        for configDir in configPaths {
            guard !configDir.isEmpty else { continue }
            let configPath = "\(configDir)config.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let logDir = json["logDir"] as? String else { continue }

            let logPath = "\(logDir)/conversations.jsonl"
            if FileManager.default.fileExists(atPath: logPath) {
                return logPath
            }
        }

        return nil
    }

    private func getFileSize(at path: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else { return 0 }
        return size
    }
}

enum OpenCodeAdapterError: Error, LocalizedError {
    case logFileNotFound
    case failedToOpenLogFile

    var errorDescription: String? {
        switch self {
        case .logFileNotFound: "OpenCode log file not found"
        case .failedToOpenLogFile: "Failed to open OpenCode log file"
        }
    }
}
