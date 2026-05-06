import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "HTTPHandler")

nonisolated final class VaporHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    let sseHub: SSEHub
    let authTokenProvider: @Sendable () -> String
    let onExtensionResponse: @Sendable ([String: Any]) -> Void
    let onContextCapture: @Sendable ([String: Any]) -> Void
    let contextItemStatusProvider: @Sendable (String) -> String?
    let onSessionSearch: @Sendable () -> (String, String?, Int) async -> [[String: Any]]
    let onSessionContext: @Sendable () -> (String, String, Int, Int) async -> [String: Any]?

    private var requestHead: HTTPRequestHead?
    private var requestPath: String = ""
    private var bodyBuffer: ByteBuffer?
    private var isSSE = false

    init(
        sseHub: SSEHub,
        authTokenProvider: @escaping @Sendable () -> String,
        onExtensionResponse: @escaping @Sendable ([String: Any]) -> Void,
        onContextCapture: @escaping @Sendable ([String: Any]) -> Void,
        contextItemStatusProvider: @escaping @Sendable (String) -> String?,
        onSessionSearch: @escaping @Sendable () -> (String, String?, Int) async -> [[String: Any]] = { { _, _, _ in [] } },
        onSessionContext: @escaping @Sendable () -> (String, String, Int, Int) async -> [String: Any]? = { { _, _, _, _ in nil } }
    ) {
        self.sseHub = sseHub
        self.authTokenProvider = authTokenProvider
        self.onExtensionResponse = onExtensionResponse
        self.onContextCapture = onContextCapture
        self.contextItemStatusProvider = contextItemStatusProvider
        self.onSessionSearch = onSessionSearch
        self.onSessionContext = onSessionContext
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
            requestPath = head.uri.split(separator: "?", maxSplits: 1).first.map(String.init) ?? head.uri
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)

            if head.method == .OPTIONS {
                handlePreflight(context: context, head: head)
                return
            }

            guard checkAuth(head: head) else {
                sendJSON(context: context, status: .unauthorized, body: ["error": "Unauthorized"])
                return
            }

            if head.method == .GET && requestPath == "/api/status" {
                sendJSON(context: context, status: .ok, body: [
                    "status": "ok",
                    "version": "1.0",
                    "connectedClients": sseHub.clientCount,
                    "authEnabled": !authTokenProvider().isEmpty
                ])
                return
            }

            switch (head.method, requestPath) {
            case (.GET, "/api/stream"):
                isSSE = true
                handleSSEConnect(context: context, head: head)
            case (.POST, "/api/response"):
                break
            case (.POST, "/api/context"):
                break
            default:
                if head.method == .GET, requestPath.hasPrefix("/api/context/status/") {
                    let jobId = String(requestPath.dropFirst("/api/context/status/".count))
                    let status = contextItemStatusProvider(jobId)
                    if let status {
                        sendJSON(context: context, status: .ok, body: ["jobId": jobId, "status": status])
                    } else {
                        sendJSON(context: context, status: .notFound, body: ["error": "Not found"])
                    }
                    return
                }
                if head.method == .GET, requestPath.hasPrefix("/api/session/") {
                    let remainder = String(requestPath.dropFirst("/api/session/".count))
                    if remainder.hasPrefix("search") {
                        handleSessionSearchGET(context: context, head: head)
                        return
                    }
                    if remainder.contains("/context") {
                        handleSessionContextGET(context: context, head: head, sessionID: String(remainder.split(separator: "/").first ?? Substring(remainder)))
                        return
                    }
                }
                sendJSON(context: context, status: .notFound, body: ["error": "Not found"])
            }

        case .body(var bodyPart):
            if !isSSE {
                if var buf = bodyBuffer { buf.writeBuffer(&bodyPart); bodyBuffer = buf } else { bodyBuffer = bodyPart }
            }

        case .end:
            if !isSSE, let head = requestHead {
                switch (head.method, requestPath) {
                case (.POST, "/api/response"):
                    handlePostResponse(context: context)
                case (.POST, "/api/context"):
                    handleContextCapture(context: context)
                default:
                    break
                }
            }
            requestHead = nil
            bodyBuffer = nil
        }
    }

    private func handlePreflight(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let origin = head.headers.first(name: "origin") ?? ""
        guard isValidOrigin(origin) else {
            sendJSON(context: context, status: .forbidden, body: ["error": "Origin not allowed"])
            return
        }
        var headers = HTTPHeaders()
        headers.add(name: "Access-Control-Allow-Origin", value: origin)
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
        headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type, Authorization")
        headers.add(name: "Access-Control-Max-Age", value: "86400")
        headers.add(name: "Vary", value: "Origin")
        headers.add(name: "Content-Length", value: "0")

        let headPart = HTTPResponseHead(version: .http1_1, status: .noContent, headers: headers)
        context.write(wrapOutboundOut(.head(headPart)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func handleSSEConnect(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let origin = head.headers.first(name: "origin") ?? ""
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/event-stream")
        headers.add(name: "Cache-Control", value: "no-cache")
        headers.add(name: "Connection", value: "keep-alive")
        if isValidOrigin(origin) {
            headers.add(name: "Access-Control-Allow-Origin", value: origin)
            headers.add(name: "Vary", value: "Origin")
        }
        headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type, Authorization")

        let headPart = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(headPart)), promise: nil)
        let commentBuf = context.channel.allocator.buffer(string: ":\n\n")
        context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(commentBuf))), promise: nil)

        let key = ObjectIdentifier(context.channel)
        let handler = self
        let writer: (String) -> Void = { [weak context] line in
            guard let ctx = context else { return }
            ctx.eventLoop.execute {
                let buf = ctx.channel.allocator.buffer(string: line)
                ctx.writeAndFlush(handler.wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
            }
        }
        sseHub.add(key, writer: writer)
        context.channel.closeFuture.whenComplete { [weak sseHub] _ in sseHub?.remove(key) }

        logger.info("SSE client connected (total: \(self.sseHub.clientCount))")
    }

    private func handlePostResponse(context: ChannelHandlerContext) {
        let bytes = bodyBuffer?.readableBytes ?? 0
        guard let str = bodyBuffer?.getString(at: 0, length: bytes), !str.isEmpty else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Empty body"])
            return
        }
        guard let bodyData = str.data(using: .utf8) else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Invalid UTF-8"])
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Invalid JSON"])
            return
        }

        logger.debug("Extension response: \(json)")
        onExtensionResponse(json)
        sendJSON(context: context, status: .ok, body: ["status": "ok"])
    }

    private func checkAuth(head: HTTPRequestHead) -> Bool {
        let token = authTokenProvider()
        if token.isEmpty { return false }

        let auth = head.headers.first(name: "Authorization")
        if let auth, auth == "Bearer \(token)" { return true }

        let queryToken = head.uri.split(separator: "?", maxSplits: 1).last
            .flatMap { String($0).split(separator: "&").map(String.init) }
            .flatMap { parts -> String? in
                for part in parts {
                    if part.hasPrefix("token=") {
                        return String(part.dropFirst(6)).removingPercentEncoding
                    }
                }
                return nil
            }
        if let queryToken, !queryToken.isEmpty, queryToken == token { return true }

        return false
    }

    private func isValidOrigin(_ origin: String) -> Bool {
        guard !origin.isEmpty else { return false }
        if origin.hasPrefix("http://127.0.0.1") { return true }
        if origin.hasPrefix("chrome-extension://") { return true }
        return false
    }

    private func sendJSON(context: ChannelHandlerContext, status: HTTPResponseStatus, body: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }

        let origin = requestHead?.headers.first(name: "origin") ?? ""
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(json.utf8.count)")
        if isValidOrigin(origin) {
            headers.add(name: "Access-Control-Allow-Origin", value: origin)
            headers.add(name: "Vary", value: "Origin")
        }

        let headPart = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(headPart)), promise: nil)
        let buf = context.channel.allocator.buffer(string: json)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if isSSE {
            let key = ObjectIdentifier(context.channel)
            sseHub.remove(key)
            logger.info("SSE client disconnected (total: \(self.sseHub.clientCount))")
        }
        context.fireChannelInactive()
    }

    private func handleContextCapture(context: ChannelHandlerContext) {
        let bytes = bodyBuffer?.readableBytes ?? 0
        guard let str = bodyBuffer?.getString(at: 0, length: bytes), !str.isEmpty else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Empty body"])
            return
        }
        guard let bodyData = str.data(using: .utf8) else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Invalid UTF-8"])
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Invalid JSON"])
            return
        }
        guard json["type"] as? String == "CONTEXT_CAPTURE" else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Expected CONTEXT_CAPTURE type"])
            return
        }

        logger.debug("Context capture: \(json)")
        onContextCapture(json)
        let jobId = json["jobId"] as? String ?? "unknown"
        sendJSON(context: context, status: .ok, body: ["status": "accepted", "jobId": jobId])
    }

    private func handleSessionSearchGET(context: ChannelHandlerContext, head: HTTPRequestHead) {
        let queryItems = head.uri.split(separator: "?", maxSplits: 1).last
            .flatMap { URLComponents(string: "?\($0)") }?.queryItems ?? []
        let query = queryItems.first(where: { $0.name == "q" })?.value ?? ""
        let sessionID = queryItems.first(where: { $0.name == "session_id" })?.value
        let limitStr = queryItems.first(where: { $0.name == "limit" })?.value ?? "20"
        let limit = Int(limitStr) ?? 20

        guard !query.isEmpty else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Missing 'q' parameter"])
            return
        }

        Task {
            let searchFn = onSessionSearch()
            let results = await searchFn(query, sessionID, limit)
            sendJSON(context: context, status: .ok, body: ["results": results, "count": results.count])
        }
    }

    private func handleSessionContextGET(context: ChannelHandlerContext, head: HTTPRequestHead, sessionID: String) {
        let queryItems = head.uri.split(separator: "?", maxSplits: 1).last
            .flatMap { URLComponents(string: "?\($0)") }?.queryItems ?? []
        let query = queryItems.first(where: { $0.name == "q" })?.value ?? ""
        let contextTurnsStr = queryItems.first(where: { $0.name == "context_turns" })?.value ?? "2"
        let contextTurns = Int(contextTurnsStr) ?? 2

        guard !query.isEmpty else {
            sendJSON(context: context, status: .badRequest, body: ["error": "Missing 'q' parameter"])
            return
        }

        Task {
            let contextFn = onSessionContext()
            if let result = await contextFn(sessionID, query, contextTurns, 5) {
                sendJSON(context: context, status: .ok, body: result)
            } else {
                sendJSON(context: context, status: .notFound, body: ["error": "No results found"])
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("HTTP handler error: \(error.localizedDescription)")
        context.close(promise: nil)
    }
}
