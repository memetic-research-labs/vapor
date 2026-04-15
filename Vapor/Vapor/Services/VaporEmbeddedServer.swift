import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "EmbeddedServer")

nonisolated final class VaporEmbeddedServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _channel: Channel?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private let port: Int
    let sseHub = SSEHub()
    private var heartbeatTask: Task<Void, Never>?

    init(port: Int = 8766) {
        self.port = port
    }

    func start(
        authTokenProvider: @escaping @Sendable () -> String,
        onResponse: @escaping @Sendable ([String: Any]) -> Void,
        onContextCapture: @escaping @Sendable ([String: Any]) -> Void,
        contextItemStatusProvider: @escaping @Sendable (String) -> String?
    ) async throws {
        let alreadyStarted: Bool = lock.withLock {
            guard _channel == nil else { return true }
            return false
        }
        if alreadyStarted { return }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let hub = self.sseHub
        let serverPort = self.port

        let serverChannel: Channel
        do {
            serverChannel = try await ServerBootstrap(group: group)
                .childChannelInitializer { channel in
                    let handler = VaporHTTPHandler(
                        sseHub: hub,
                        authTokenProvider: authTokenProvider,
                        onExtensionResponse: onResponse,
                        onContextCapture: onContextCapture,
                        contextItemStatusProvider: contextItemStatusProvider
                    )
                    return channel.pipeline.configureHTTPServerPipeline(withPipeliningAssistance: true).flatMap { _ in
                        channel.pipeline.addHandler(handler)
                    }
                }
                .bind(host: "127.0.0.1", port: serverPort)
                .get()
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }

        lock.withLock {
            self._channel = serverChannel
            self.eventLoopGroup = group
        }

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                self?.sseHub.broadcast(event: "heartbeat", json: ["type": "ping", "ts": Int(Date().timeIntervalSince1970)])
            }
        }

        logger.info("Embedded server listening on 127.0.0.1:\(serverPort)")
    }

    func stop() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        var channelToClose: Channel?
        var groupToShutdown: MultiThreadedEventLoopGroup?
        lock.withLock {
            channelToClose = _channel
            groupToShutdown = eventLoopGroup
            _channel = nil
            eventLoopGroup = nil
        }

        if let channelToClose {
            try? await channelToClose.close()
            logger.info("Embedded server stopped")
        }
        try? await groupToShutdown?.shutdownGracefully()
    }

    func broadcast(event: String? = nil, json: [String: Any]) {
        sseHub.broadcast(event: event, json: json)
    }
}
