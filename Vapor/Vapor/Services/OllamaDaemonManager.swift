import Foundation
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "OllamaDaemon")

actor OllamaDaemonManager {
    static let shared = OllamaDaemonManager()

    private var process: Process?
    private var adoptedPid: Int32?
    private var port: UInt16

    private var pidFilePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vapor-ollama.pid")
    }

    private var ollamaBinaryPath: String {
        Bundle.main.resourceURL?
            .appendingPathComponent("ollama")
            .path ?? ""
    }

    private var endpoint: String {
        "http://127.0.0.1:\(port)"
    }

    private var tagsEndpoint: String {
        "\(endpoint)/api/tags"
    }

    init(port: UInt16 = 11434) {
        self.port = port
    }

    func start() async throws {
        guard !ollamaBinaryPath.isEmpty else {
            logger.error("Ollama binary not found in app bundle resources")
            throw OllamaDaemonError.binaryNotFound
        }

        if await isHealthy() {
            logger.info("Ollama daemon already running and healthy on port \(self.port)")
            adoptPidFromPidFile()
            return
        }

        await cleanupStaleProcess()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ollamaBinaryPath)
        proc.arguments = ["serve"]
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = "127.0.0.1:\(port)"
        env["OLLAMA_ORIGINS"] = "http://localhost,https://localhost,http://127.0.0.1,app://*"
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        try proc.run()
        self.process = proc

        logger.info("Launched ollama serve (PID \(proc.processIdentifier))")

        let start = CFAbsoluteTimeGetCurrent()
        let started = await waitForHealthy(timeout: 15)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        if started {
            writePidFile()
            logger.info("Ollama daemon ready on \(self.endpoint) (\(String(format: "%.1f", elapsed))s)")
            Task { @MainActor in
                CompressionTelemetry.shared.recordServiceEvent(.daemonStart(duration: elapsed))
            }
        } else {
            logger.error("Ollama daemon failed to become healthy within timeout")
            throw OllamaDaemonError.startupTimeout
        }
    }

    func stop() {
        if let proc = process, proc.isRunning {
            proc.terminate()
            logger.info("Sent SIGTERM to ollama serve (PID \(proc.processIdentifier))")
        } else if let pid = adoptedPid {
            kill(pid, SIGTERM)
            logger.info("Sent SIGTERM to adopted ollama process (PID \(pid))")
        }
        process = nil
        adoptedPid = nil
        removePidFile()
    }

    func isRunning() -> Bool {
        guard let proc = process else { return false }
        return proc.isRunning
    }

    func isHealthy() async -> Bool {
        guard let url = URL(string: tagsEndpoint) else { return false }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let healthy = (response as? HTTPURLResponse)?.statusCode == 200
            if !healthy {
                logger.debug("Health check: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            return healthy
        } catch {
            logger.debug("Health check failed: \(error.localizedDescription)")
            return false
        }
    }

    func setPort(_ newPort: UInt16) {
        self.port = newPort
    }

    // MARK: - Private

    private func waitForHealthy(timeout: TimeInterval) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(Int(timeout))
        while ContinuousClock.now < deadline {
            if await isHealthy() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    private func cleanupStaleProcess() async {
        guard let pidString = try? String(contentsOf: pidFilePath, encoding: .utf8),
              let stalePid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)),
              stalePid > 0
        else { return }

        let killResult = kill(stalePid, 0)
        if killResult == 0 {
            kill(stalePid, SIGTERM)
            logger.info("Killed stale ollama process (PID \(stalePid))")
            try? await Task.sleep(for: .milliseconds(500))
        }
        removePidFile()
    }

    private func adoptPidFromPidFile() {
        guard let pidString = try? String(contentsOf: pidFilePath, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0
        else { return }

        let killResult = kill(pid, 0)
        if killResult == 0 {
            logger.info("Adopted existing ollama process (PID \(pid))")
            self.adoptedPid = pid
        }
    }

    private func writePidFile() {
        let pid = process?.processIdentifier ?? 0
        guard pid > 0 else { return }
        try? String(pid).write(to: pidFilePath, atomically: true, encoding: .utf8)
    }

    private func removePidFile() {
        try? FileManager.default.removeItem(at: pidFilePath)
    }
}

enum OllamaDaemonError: LocalizedError {
    case binaryNotFound
    case startupTimeout

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "Ollama binary not found in app bundle. Run the download script first."
        case .startupTimeout:
            "Ollama daemon did not start within the expected timeout."
        }
    }
}
