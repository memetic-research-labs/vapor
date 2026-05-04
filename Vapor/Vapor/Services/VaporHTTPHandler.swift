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

    private var requestHead: HTTPRequestHead?
    private var requestPath: String = ""
    private var bodyBuffer: ByteBuffer?
    private var isSSE = false

    init(
        sseHub: SSEHub,
        authTokenProvider: @escaping @Sendable () -> String,
        onExtensionResponse: @escaping @Sendable ([String: Any]) -> Void,
        onContextCapture: @escaping @Sendable ([String: Any]) -> Void,
        contextItemStatusProvider: @escaping @Sendable (String) -> String?
    ) {
        self.sseHub = sseHub
        self.authTokenProvider = authTokenProvider
        self.onExtensionResponse = onExtensionResponse
        self.onContextCapture = onContextCapture
        self.contextItemStatusProvider = contextItemStatusProvider
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
                    "connectedClients": sseHub.clientCount
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
                if requestPath.hasPrefix("/api/sessions") ||
                   requestPath.hasPrefix("/api/projects") ||
                   requestPath.hasPrefix("/api/search/") {
                    Task { @MainActor in
                        let query = Self.parseQueryParams(from: head.uri)
                        let response = SessionAPIRouter.shared.handle(method: head.method.rawValue, path: requestPath, query: query, body: nil)
                        if head.method == .GET {
                            self.sendJSON(context: context, status: HTTPResponseStatus(statusCode: response.status), body: response.body)
                        }
                    }
                    return
                }
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
                    if requestPath.hasPrefix("/api/sessions") ||
                       requestPath.hasPrefix("/api/projects") ||
                       requestPath.hasPrefix("/api/search/") ||
                       requestPath.hasPrefix("/api/export") {
                        handleSessionAPI(context: context)
                    }
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
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, PUT, DELETE, OPTIONS")
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

    private func handleSessionAPI(context: ChannelHandlerContext) {
        let bytes = bodyBuffer?.readableBytes ?? 0
        let bodyStr = bodyBuffer.map { $0.getString(at: 0, length: bytes) } ?? nil
        var bodyJSON: [String: Any]?
        if let str = bodyStr, let data = str.data(using: .utf8) {
            bodyJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        Task { @MainActor in
            let query = self.requestHead.map { Self.parseQueryParams(from: $0.uri) } ?? [:]
            let path = self.requestPath
            let method = self.requestHead?.method.rawValue ?? "GET"
            let response = SessionAPIRouter.shared.handle(method: method, path: path, query: query, body: bodyJSON)
            self.sendJSON(context: context, status: HTTPResponseStatus(statusCode: response.status), body: response.body)
        }
    }

    nonisolated private static func parseQueryParams(from uri: String) -> [String: String] {
        guard let queryStart = uri.firstIndex(of: "?") else { return [:] }
        let query = String(uri[uri.index(after: queryStart)...])
        var params: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                params[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
            }
        }
        return params
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("HTTP handler error: \(error.localizedDescription)")
        context.close(promise: nil)
    }
}
