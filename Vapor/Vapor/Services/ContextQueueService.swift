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
    var author: String?
    var publishedDate: String?
    var siteName: String?
    var capturedAt: String?
}

@MainActor
@Observable
final class ContextQueueService {
    var queue: [ContextItem] = []
    var processing: [ContextItem] = []
    var ready: [ContextItem] = []
    var failed: [ContextItem] = []

    private let blobStore = BlobStore.shared
    private var modelContext: ModelContext?
    private let entityExtractor = EntityExtractionService()
    private let summarizer = SummarizationService()
    private let tagger = TaggerService()
    private let citationBuilder = CitationBuilder()
    private var isProcessing = false

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadPersistedItems()
    }

    private func loadPersistedItems() {
        guard let ctx = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<ContextItem>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            let items = try ctx.fetch(descriptor)
            for item in items {
                switch item.status {
                case .pending:
                    if !queue.contains(where: { $0.id == item.id }) { queue.append(item) }
                case .processing:
                    item.status = .ready
                    try ctx.save()
                    fallthrough
                case .ready:
                    if !ready.contains(where: { $0.id == item.id }) { ready.insert(item, at: 0) }
                case .failed:
                    if !failed.contains(where: { $0.id == item.id }) { failed.append(item) }
                }
            }
            if !items.isEmpty {
                logger.info("Loaded \(items.count) persisted context items")
            }
        } catch {
            logger.error("Failed to load persisted context items: \(error.localizedDescription)")
        }
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

        let parsedDate: Date? = {
            guard let dateStr = payload.publishedDate else { return nil }
            let formatters: [ISO8601DateFormatter] = {
                let f1 = ISO8601DateFormatter()
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return [f1, f2]
            }()
            for formatter in formatters {
                if let date = formatter.date(from: dateStr) { return date }
            }
            return nil
        }()

        let item = ContextItem(
            sourceURL: payload.url,
            sourceTitle: payload.title,
            sourceAuthor: payload.author,
            sourcePublishedDate: parsedDate,
            sourceSiteName: payload.siteName,
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
        guard !queue.isEmpty, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        let item = queue.removeFirst()
        item.status = .processing
        processing.append(item)

        let title = item.sourceTitle.isEmpty ? "Untitled" : item.sourceTitle
        logger.info("Processing context item: \(item.id) kind=\(item.kind.displayName) title=\(title.prefix(80)) textLen=\(item.textContent?.count ?? 0)")
        StatusBarService.shared.setContextStatus("Processing: \"\(title.prefix(60))\"")

        do {
            if let text = item.textContent, !text.isEmpty {
                logger.info("Starting parallel extraction + summarization for \(item.id)")
                StatusBarService.shared.setContextStatus("Extracting entities (\(entityExtractor.backend.displayName))...")

                async let extractionResult = entityExtractor.extract(from: text)
                async let summaryResult = summarizer.summarize(text: text)

                let result = await extractionResult
                logger.info("Extraction complete for \(item.id): \(result.entities.count) entities via \(result.backend.displayName)")
                item.entities = result.entities
                item.extractionBackendRaw = result.backend.rawValue

                if let summary = await summaryResult {
                    logger.info("Summarization complete for \(item.id): abstract=\(summary.abstract.prefix(100))")
                    item.summary = summary
                    StatusBarService.shared.setContextStatus("\(result.entities.count) entities · summary ready")
                } else {
                    logger.warning("Summarization returned nil for \(item.id)")
                    StatusBarService.shared.setContextStatus("\(result.entities.count) entities extracted")
                }

                let tags = tagger.tag(contextItem: item)
                item.tags = tags
                logger.info("Tagging complete for \(item.id): \(item.tags.count) tags")
            }

            if let citation = citationBuilder.build(for: item) {
                item.citation = citation
                logger.info("Citation built for \(item.id): format=\(citation.format.rawValue)")
            }

            if let ctx = modelContext {
                ctx.insert(item)
                try ctx.save()
            }
            processing.removeAll { $0.id == item.id }
            item.status = .ready
            ready.insert(item, at: 0)
            let backendName = item.extractionBackendRaw ?? "unknown"
            logger.info("Context item ready: \(item.id) with \(item.tags.count) tags, \(item.entities.count) entities (via \(backendName)), summary=\(item.summary != nil ? "yes" : "no")")
            StatusBarService.shared.updateContextIndicator(count: ready.count, hasProcessing: !processing.isEmpty)
        } catch {
            processing.removeAll { $0.id == item.id }
            item.status = .failed
            failed.append(item)
            logger.error("Context item failed: \(item.id) — \(error.localizedDescription)")
            StatusBarService.shared.setContextStatus("Processing failed: \(error.localizedDescription)")
            StatusBarService.shared.updateContextIndicator(count: ready.count, hasProcessing: !processing.isEmpty)
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
