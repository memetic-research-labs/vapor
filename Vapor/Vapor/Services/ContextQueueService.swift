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
    var markdownContent: String?
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
    private let vectorizationService = VectorizationService.shared
    private var isProcessing = false

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadPersistedItems()
        Task { @MainActor in
            await vectorizationService.backfillMissingContextEmbeddings(in: context)
        }
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
        return all.first { $0.captureJobId == jobId }?.status.rawValue
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

        let capturedAt: Date = {
            guard let dateStr = payload.capturedAt else { return Date() }
            let formatters: [ISO8601DateFormatter] = {
                let base = ISO8601DateFormatter()
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return [fractional, base]
            }()
            for formatter in formatters {
                if let date = formatter.date(from: dateStr) { return date }
            }
            return Date()
        }()

        let canonicalSourceURL = URLCanonicalizer.canonicalize(payload.url)?.canonicalURL ?? payload.url

        let item = ContextItem(
            sourceURL: canonicalSourceURL,
            sourceTitle: payload.title,
            sourceAuthor: payload.author,
            sourcePublishedDate: parsedDate,
            sourceSiteName: payload.siteName,
            capturedAt: capturedAt,
            kind: kind,
            textContent: payload.textContent,
            markdownContent: payload.markdownContent,
            blobPath: blobPath,
            blobMimeType: payload.mimeType
        )
        item.captureJobId = payload.jobId

        queue.append(item)
        logger.info("Ingested context item: \(item.id) kind=\(payload.kind)")

        await processNext()

        return item
    }

    func processNext() async {
        guard !isProcessing else { return }
        isProcessing = true
        StatusBarService.shared.beginContextProcessing()
        defer {
            isProcessing = false
            StatusBarService.shared.endContextProcessing()
            refreshContextIndicator()
        }

        while !queue.isEmpty {
            let item = queue.removeFirst()
            item.status = .processing
            processing.append(item)
            persist(item, insertingIfNeeded: true)
            syncNormalizedMetadata(for: item)
            refreshContextIndicator()

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
                        let extractedEntities = filteredEntities(from: result.entities)
                        logger.info("Extraction complete for \(item.id): \(extractedEntities.count) entities via \(result.backend.displayName)")
                        item.extractionBackendRaw = result.backend.rawValue
                        syncNormalizedMetadata(for: item, extractedEntities: extractedEntities)
                        persist(item)

                        if let summary = await summaryResult {
                            logger.info("Summarization complete for \(item.id): abstract=\(summary.abstract.prefix(100))")
                            item.summary = summary
                            persist(item)
                            StatusBarService.shared.setContextStatus("\(extractedEntities.count) entities · summary ready")
                        } else {
                            logger.warning("Summarization returned nil for \(item.id)")
                            StatusBarService.shared.setContextStatus("\(extractedEntities.count) entities extracted")
                        }

                        let tags = tagger.tag(contextItem: item)
                        item.tags = tags
                        persist(item)
                        logger.info("Tagging complete for \(item.id): \(item.tags.count) tags")
                    }

                    if let citation = citationBuilder.build(for: item) {
                        item.citation = citation
                        persist(item)
                        logger.info("Citation built for \(item.id): format=\(citation.format.rawValue)")
                    }

                    if let ctx = modelContext {
                        do {
                            StatusBarService.shared.setContextStatus("Generating embeddings...")
                            if let embeddingID = try await vectorizationService.ensureEmbedding(for: item) {
                                try ctx.save()
                                logger.info("Vectorization complete for \(item.id): embeddingID=\(embeddingID)")
                            } else {
                                logger.info("Vectorization skipped for \(item.id): no searchable text")
                            }
                        } catch {
                            logger.error("Vectorization failed for \(item.id): \(error.localizedDescription)")
                        }
                    }
                    processing.removeAll { $0.id == item.id }
                    item.status = .ready
                    persist(item)
                    ready.insert(item, at: 0)
                    let backendName = item.extractionBackendRaw ?? "unknown"
                    logger.info("Context item ready: \(item.id) with \(item.tags.count) tags, \(item.entityCount) entities (via \(backendName)), summary=\(item.summary != nil ? "yes" : "no")")
                    refreshContextIndicator()
            } catch {
                processing.removeAll { $0.id == item.id }
                item.status = .failed
                persist(item)
                failed.append(item)
                logger.error("Context item failed: \(item.id) — \(error.localizedDescription)")
                StatusBarService.shared.setContextStatus("Processing failed: \(error.localizedDescription)")
                refreshContextIndicator()
            }
        }
    }

    private func persist(_ item: ContextItem, insertingIfNeeded: Bool = false) {
        guard let ctx = modelContext else { return }

        if insertingIfNeeded {
            ctx.insert(item)
        }

        do {
            try ctx.save()
        } catch {
            logger.error("Failed to persist context item \(item.id): \(error.localizedDescription)")
        }
    }

    private func refreshContextIndicator() {
        StatusBarService.shared.updateContextIndicator(count: ready.count, hasProcessing: !processing.isEmpty || isProcessing)
    }

    @discardableResult
    private func syncNormalizedMetadata(for item: ContextItem, extractedEntities: [ExtractedEntity] = []) -> Bool {
        guard let ctx = modelContext else { return false }

        var didChange = false

        if let canonicalSource = URLCanonicalizer.canonicalize(item.sourceURL) {
            if item.sourceURL != canonicalSource.canonicalURL {
                item.sourceURL = canonicalSource.canonicalURL
                didChange = true
            }
        }

        let desiredURLs = desiredURLEntries(for: item)
        let desiredURLKeys = Set(desiredURLs.map { "\($0.role.rawValue):\($0.canonical.urlHash)" })

        for link in item.urlLinks {
            let existingKey = "\(link.role.rawValue):\((link.urlRecord?.urlHash ?? ""))"
            if !desiredURLKeys.contains(existingKey) {
                link.urlRecord?.links.removeAll { $0.id == link.id }
                ctx.delete(link)
                didChange = true
            }
        }
        if didChange {
            item.urlLinks.removeAll { link in
                let existingKey = "\(link.role.rawValue):\((link.urlRecord?.urlHash ?? ""))"
                return !desiredURLKeys.contains(existingKey)
            }
        }

        for entry in desiredURLs {
            let urlRecord = fetchOrCreateURLRecord(entry.canonical, in: ctx, seenAt: item.capturedAt)
            let alreadyLinked = item.urlLinks.contains {
                $0.role == entry.role && $0.urlRecord?.urlHash == urlRecord.urlHash
            }

            if !alreadyLinked {
                let link = ContextItemURLLink(role: entry.role, contextItem: item, urlRecord: urlRecord, createdAt: item.capturedAt)
                ctx.insert(link)
                item.urlLinks.append(link)
                urlRecord.links.append(link)
                didChange = true
            }
        }

        let filtered = filteredEntities(from: extractedEntities)

        let desiredEntityHashes = Set(filtered.map {
            URLCanonicalizer.entityHash(kind: $0.kind, normalizedText: URLCanonicalizer.normalizeEntityText($0.text))
        })

        for link in item.entityLinks {
            let existingHash = link.entityRecord?.entityHash ?? ""
            if !desiredEntityHashes.contains(existingHash) {
                link.entityRecord?.links.removeAll { $0.id == link.id }
                ctx.delete(link)
                didChange = true
            }
        }
        if didChange {
            item.entityLinks.removeAll { link in
                let existingHash = link.entityRecord?.entityHash ?? ""
                return !desiredEntityHashes.contains(existingHash)
            }
        }

        for entity in filtered {
            let normalizedText = URLCanonicalizer.normalizeEntityText(entity.text)
            guard !normalizedText.isEmpty else { continue }

            let entityHash = URLCanonicalizer.entityHash(kind: entity.kind, normalizedText: normalizedText)
            let entityRecord = fetchOrCreateEntityRecord(
                entityHash: entityHash,
                kind: entity.kind,
                normalizedText: normalizedText,
                displayText: entity.text,
                seenAt: item.capturedAt,
                in: ctx
            )

            if let existingLink = item.entityLinks.first(where: { $0.entityRecord?.entityHash == entityHash }) {
                if existingLink.confidence != entity.confidence || existingLink.surfaceText != entity.text {
                    existingLink.confidence = entity.confidence
                    existingLink.surfaceText = entity.text
                    didChange = true
                }
            } else {
                let link = ContextItemEntityLink(
                    confidence: entity.confidence,
                    surfaceText: entity.text,
                    contextItem: item,
                    entityRecord: entityRecord,
                    createdAt: item.capturedAt
                )
                ctx.insert(link)
                item.entityLinks.append(link)
                entityRecord.links.append(link)
                didChange = true
            }
        }

        return didChange
    }

    private func desiredURLEntries(for item: ContextItem) -> [(canonical: CanonicalURL, role: ContextURLRole)] {
        var ordered: [(CanonicalURL, ContextURLRole)] = []
        var seen = Set<String>()

        if let source = URLCanonicalizer.canonicalize(item.sourceURL), seen.insert("\(ContextURLRole.source.rawValue):\(source.urlHash)").inserted {
            ordered.append((source, .source))
        }

        let textSources = [item.textContent, item.markdownContent].compactMap { $0 }
        for text in textSources {
            for detected in URLCanonicalizer.extractURLs(from: text) {
                let key = "\(ContextURLRole.mentioned.rawValue):\(detected.urlHash)"
                if seen.insert(key).inserted {
                    ordered.append((detected, .mentioned))
                }
            }
        }

        return ordered
    }

    private func filteredEntities(from entities: [ExtractedEntity]) -> [ExtractedEntity] {
        var seen = Set<String>()

        return entities.compactMap { entity in
            guard entity.kind != .url else { return nil }
            let normalized = URLCanonicalizer.normalizeEntityText(entity.text)
            guard !normalized.isEmpty else { return nil }

            let key = "\(entity.kind.rawValue):\(normalized)"
            guard seen.insert(key).inserted else { return nil }
            return ExtractedEntity(text: entity.text.trimmingCharacters(in: .whitespacesAndNewlines), kind: entity.kind, confidence: entity.confidence)
        }
    }

    private func fetchOrCreateURLRecord(_ canonical: CanonicalURL, in context: ModelContext, seenAt: Date) -> URLRecord {
        let urlHash = canonical.urlHash
        let descriptor = FetchDescriptor<URLRecord>(predicate: #Predicate { $0.urlHash == urlHash })
        if let existing = try? context.fetch(descriptor).first {
            existing.lastSeenAt = max(existing.lastSeenAt, seenAt)
            return existing
        }

        let record = URLRecord(
            urlHash: canonical.urlHash,
            canonicalURL: canonical.canonicalURL,
            domain: canonical.domain,
            scheme: canonical.scheme,
            path: canonical.path,
            query: canonical.query,
            firstSeenAt: seenAt,
            lastSeenAt: seenAt
        )
        context.insert(record)
        return record
    }

    private func fetchOrCreateEntityRecord(
        entityHash: String,
        kind: EntityKind,
        normalizedText: String,
        displayText: String,
        seenAt: Date,
        in context: ModelContext
    ) -> EntityRecord {
        let targetHash = entityHash
        let descriptor = FetchDescriptor<EntityRecord>(predicate: #Predicate { $0.entityHash == targetHash })
        if let existing = try? context.fetch(descriptor).first {
            existing.lastSeenAt = max(existing.lastSeenAt, seenAt)
            if existing.displayText.count < displayText.count {
                existing.displayText = displayText
            }
            return existing
        }

        let record = EntityRecord(
            entityHash: entityHash,
            kind: kind,
            normalizedText: normalizedText,
            displayText: displayText,
            firstSeenAt: seenAt,
            lastSeenAt: seenAt
        )
        context.insert(record)
        return record
    }

    func remove(_ item: ContextItem) {
        queue.removeAll { $0.id == item.id }
        processing.removeAll { $0.id == item.id }
        ready.removeAll { $0.id == item.id }
        failed.removeAll { $0.id == item.id }

        if let blobPath = item.blobPath {
            try? blobStore.delete(relativePath: blobPath)
        }
        if let embeddingID = item.embeddingID {
            Task { @MainActor in
                await vectorizationService.removeEmbedding(id: embeddingID)
            }
        }
        if let ctx = modelContext {
            ctx.delete(item)
            try? ctx.save()
        }
    }

    func clearCompleted() {
        let toRemove = ready + failed
        ready.removeAll()
        failed.removeAll()

        if let ctx = modelContext {
            for item in toRemove {
                if let blobPath = item.blobPath {
                    try? blobStore.delete(relativePath: blobPath)
                }
                if let embeddingID = item.embeddingID {
                    Task { @MainActor in
                        await vectorizationService.removeEmbedding(id: embeddingID)
                    }
                }
                ctx.delete(item)
            }
            try? ctx.save()
        }
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
