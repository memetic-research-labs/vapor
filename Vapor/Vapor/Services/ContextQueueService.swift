import Foundation
import SwiftData
import OSLog

nonisolated private let logger = Logger(subsystem: "lol.mrl.app.Vapor", category: "ContextQueue")

struct BrowserContextPayload: Sendable {
    var kind: String
    var jobId: String
    var url: String
    var title: String
    var textContent: String?
    var mimeType: String?
    var dataURL: String?
    var capturedAt: String?
}

@MainActor
@Observable
final class ContextQueueService {
    var queue: [ContextItem] = []
    var processing: [ContextItem] = []
    var ready: [ContextItem] = []
    var failed: [ContextItem] = []

    private var blobStore = BlobStore.shared
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func status(for jobId: String) -> String? {
        let all = queue + processing + ready + failed
        return all.first { $0.id.uuidString == jobId }?.status.rawValue
    }

    func ingest(_ payload: BrowserContextPayload) async throws -> ContextItem {
        guard let kind = ContextItemKind(rawValue: payload.kind) else {
            throw ContextQueueError.invalidKind(payload.kind)
        }

        var blobPath: String?
        if let dataURL = payload.dataURL, dataURL.hasPrefix("data:") {
            guard let commaIdx = dataURL.firstIndex(of: ",") else {
                throw ContextQueueError.invalidDataURL
            }
            let header = String(dataURL[..<commaIdx])
            let base64Str = String(dataURL[dataURL.index(after: commaIdx)...])
            guard let data = Data(base64Encoded: base64Str) else {
                throw ContextQueueError.invalidDataURL
            }
            let mimeType = parseMimeFromDataURLHeader(header)
            blobPath = try blobStore.store(data: data, mimeType: mimeType)
        }

        let item = ContextItem(
            sourceURL: payload.url,
            sourceTitle: payload.title,
            kind: kind,
            textContent: payload.textContent,
            blobPath: blobPath,
            blobMimeType: payload.mimeType
        )

        queue.append(item)
        logger.info("Ingested context item: \(item.id) kind=\(payload.kind)")

        await processNext()

        return item
    }

    func processNext() async {
        guard !queue.isEmpty else { return }
        let item = queue.removeFirst()
        item.status = .processing
        processing.append(item)

        do {
            if let ctx = modelContext {
                ctx.insert(item)
                try ctx.save()
            }
            processing.removeAll { $0.id == item.id }
            item.status = .ready
            ready.append(item)
            logger.info("Context item ready: \(item.id)")
        } catch {
            processing.removeAll { $0.id == item.id }
            item.status = .failed
            failed.append(item)
            logger.error("Context item failed: \(item.id) — \(error.localizedDescription)")
        }
    }

    func remove(_ item: ContextItem) {
        queue.removeAll { $0.id == item.id }
        processing.removeAll { $0.id == item.id }
        ready.removeAll { $0.id == item.id }
        failed.removeAll { $0.id == item.id }
    }

    func clearCompleted() {
        ready.removeAll()
        failed.removeAll()
    }

    private func parseMimeFromDataURLHeader(_ header: String) -> String {
        guard let semicolonIdx = header.firstIndex(of: ";") else { return "application/octet-stream" }
        let mime = String(header[header.index(after: header.firstIndex(of: ":")!)..<semicolonIdx])
        return mime.trimmingCharacters(in: .whitespaces)
    }
}

enum ContextQueueError: LocalizedError {
    case invalidKind(String)
    case invalidDataURL

    var errorDescription: String? {
        switch self {
        case .invalidKind(let kind): "Invalid context item kind: \(kind)"
        case .invalidDataURL: "Invalid data URL encoding"
        }
    }
}
