# Plan: Context Management System

## Overview

The Context Management System transforms Vapor from a single-prompt dictation tool into a **rich-context prompt composition environment**. Users can collect arbitrary text, images, video frames, structured data, and binary media from any browser tab — then bind those assets inline with dictated speech to compose large, multi-modal prompts with proper citations.

On top of raw collection, the system introduces **Glossaries**: curated, searchable libraries of reusable context items (text snippets, image sets, keyword clusters) that dramatically accelerate the creation of long, complex prompts. All collected items and composed prompts are vectorized for semantic search and autocomplete.

This document covers the backend architecture. See `docs/plan-context-ux.md` for UX flows and wireframes.

---

## High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                               Vapor Mac App                                  │
│                                                                              │
│  ┌─────────────────────────┐    ┌─────────────────────────────────────────┐ │
│  │   Context Tray          │    │          Prompt Composer                 │ │
│  │  (live collection view) │    │  (inline context + dictated segments)   │ │
│  └────────────┬────────────┘    └──────────────────────┬──────────────────┘ │
│               │                                        │                    │
│  ┌────────────▼────────────────────────────────────────▼──────────────────┐ │
│  │                      ContextQueueService                                │ │
│  │   ingest → deduplicate → enqueue → process → store                     │ │
│  └────────────────────────────────┬───────────────────────────────────────┘ │
│                                   │                                          │
│  ┌────────────────────────────────▼───────────────────────────────────────┐ │
│  │                      Processing Pipeline                                │ │
│  │                                                                         │ │
│  │  ┌──────────────────┐  ┌────────────────┐  ┌────────────────────────┐  │ │
│  │  │  VectorizeSvc    │  │ EntityExtract  │  │   TaggerService        │  │ │
│  │  │  (embeddings)    │  │ Service        │  │   (auto-tag + cite)    │  │ │
│  │  └──────────────────┘  └────────────────┘  └────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                   │                                          │
│  ┌────────────────────────────────▼───────────────────────────────────────┐ │
│  │                         Data Layer                                      │ │
│  │   SwiftData (metadata)  +  on-disk blob store  +  vector index         │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
          ▲                   ▲
          │  SSE/POST         │  SSE/POST
┌─────────┴─────────┐  ┌──────┴────────────────────────────┐
│  Chrome Extension  │  │  BrowserBridge (NIO server :8766)  │
│  (XHR intercept,  │  │  (already exists — Phase 4 web     │
│   DOM picker,     │  │   scraping hooks)                  │
│   image capture)  │  └───────────────────────────────────┘
└───────────────────┘
```

---

## Data Models

### ContextItem (SwiftData)

The atomic unit of collected context. Every piece of external content — a text snippet, an image, a video frame, a JSON payload — is a `ContextItem`.

```swift
@Model
final class ContextItem {
    var id: UUID
    var sourceURL: String          // canonical URL of the originating page/resource
    var sourceTitle: String        // page <title> or resource filename
    var capturedAt: Date
    var kind: ContextItemKind      // see enum below
    var status: ProcessingStatus   // pending → processing → ready | failed

    // Content
    var textContent: String?       // plain text (articles, XHR JSON, captions)
    var blobPath: String?          // relative path inside ~/Library/Application Support/Vapor/blobs/
    var blobMimeType: String?      // e.g. "image/webp", "image/gif", "video/mp4"
    var thumbnailPath: String?     // 256×256 JPEG thumbnail for images/video frames

    // Processed metadata
    var tags: [String]             // auto-generated + user-edited
    var entities: [ExtractedEntity]
    var citation: Citation?        // formatted citation (APA, MLA, URL-only)
    var embeddingID: String?       // reference into vector index

    // Glossary membership
    var glossaryItems: [GlossaryItem]  // items that include this ContextItem
}

enum ContextItemKind: String, Codable {
    case articleText   // Readability-extracted article body
    case selectedText  // user-selected DOM text
    case image         // raster image (PNG, JPEG, WebP, GIF frame)
    case animatedGif   // full animated GIF
    case videoClip     // MP4/WebM clip or frame sequence
    case xhrJSON       // intercepted XHR/fetch JSON payload
    case xhrBinary     // intercepted binary (e.g., image served via XHR)
    case pageSnapshot  // full page HTML/Markdown snapshot
    case manualText    // user-typed snippet (not from browser)
}

enum ProcessingStatus: String, Codable {
    case pending
    case processing
    case ready
    case failed
}
```

### ExtractedEntity

```swift
struct ExtractedEntity: Codable {
    var text: String        // "Swift NIO", "Apple Inc.", "2024-03-15"
    var kind: EntityKind    // person, org, product, date, url, number, code
    var confidence: Double
}

enum EntityKind: String, Codable {
    case person, organization, product, location, date, url, number, code, concept
}
```

### Citation

```swift
struct Citation: Codable {
    var url: String
    var title: String
    var author: String?
    var publishedDate: Date?
    var accessedDate: Date
    var format: CitationFormat  // urlOnly | apa | mla | chicago

    var rendered: String        // pre-rendered citation string for insertion
}
```

### GlossaryItem (SwiftData)

A `GlossaryItem` is a named, reusable handle on one or more `ContextItem`s. It can represent a single image, a cluster of keywords, or a rich multi-asset bundle.

```swift
@Model
final class GlossaryItem {
    var id: UUID
    var name: String               // user-assigned label, e.g. "SwiftNIO Docs"
    var shortCode: String          // fast-insert token, e.g. "@swiftnio"
    var kind: GlossaryItemKind
    var glossary: Glossary
    var contextItems: [ContextItem]
    var keywords: [String]         // keyword cluster (for keyword-type items)
    var createdAt: Date
    var modifiedAt: Date
    var usageCount: Int
    var embeddingID: String?       // embedding over name + keywords + text content
    var notes: String?             // user notes
}

enum GlossaryItemKind: String, Codable {
    case textSnippet    // single or multi-paragraph text
    case imageSet       // one or more images referenced together
    case keywordCluster // a set of keywords/phrases
    case mixed          // combination of text + images + keywords
}
```

### Glossary (SwiftData)

```swift
@Model
final class Glossary {
    var id: UUID
    var name: String               // e.g. "iOS Architecture Patterns"
    var description: String?
    var color: String              // hex color for UI differentiation
    var icon: String               // SF Symbol name
    var items: [GlossaryItem]
    var createdAt: Date
    var modifiedAt: Date
    var isDefault: Bool            // the Default glossary always exists
}
```

### ComposedPrompt (SwiftData)

Extends the existing `PromptRecord` concept to include inline context segments.

```swift
@Model
final class ComposedPrompt {
    var id: UUID
    var createdAt: Date
    var usedAt: Date?
    var segments: [PromptSegment]       // ordered list of mixed segments
    var rawText: String                 // plain-text serialisation for compression
    var compressedText: String?
    var compressionRatio: Double?
    var compressorUsed: String?
    var embeddingID: String?            // embedding of rawText
    var isFavorite: Bool
    var tags: [String]
    var title: String?                  // auto-generated or user-set
}

struct PromptSegment: Codable, Identifiable {
    var id: UUID
    var kind: SegmentKind
    var order: Int

    // Text segment
    var text: String?
    var isDictated: Bool?
    var noCompress: Bool = false    // when true, segment bypasses compression verbatim

    // Context item segment
    var contextItemID: UUID?

    // Glossary item segment
    var glossaryItemID: UUID?
}

enum SegmentKind: String, Codable {
    case dictatedText    // speech-to-text segment
    case typedText       // manually typed text
    case contextItem     // inline ContextItem (image, text snippet, etc.)
    case glossaryItem    // inline GlossaryItem shortcode expansion
    case citation        // auto-generated citation block
}
```

---

## Services

### ContextQueueService

Manages the lifecycle of `ContextItem`s from ingestion to ready state.

```swift
@MainActor
@Observable
final class ContextQueueService {
    var queue: [ContextItem] = []               // items awaiting processing
    var processing: [ContextItem] = []          // currently processing
    var ready: [ContextItem] = []               // processed and available

    // Called by BrowserBridge when extension sends captured content
    func ingest(_ payload: BrowserContextPayload) async throws -> ContextItem

    // Processing pipeline (runs items through all sub-services)
    func processNext() async

    // Cancel / remove
    func remove(_ item: ContextItem)
    func clearCompleted()
}
```

**Ingestion flow:**

1. `BrowserBridge` receives a `CONTEXT_CAPTURE` response from the extension.
2. Calls `ContextQueueService.ingest(_:)`.
3. Service creates a `ContextItem` with `status = .pending`, writes any binary to the blob store, and appends to `queue`.
4. `processNext()` picks up the item:
   - Runs `VectorizationService.embed(_:)`
   - Runs `EntityExtractionService.extract(_:)`
   - Runs `TaggerService.tag(_:)`
   - Builds `Citation`
   - Sets `status = .ready`
5. Item moves from `processing` to `ready` and triggers a UI refresh.

### VectorizationService

Generates embeddings for both `ContextItem`s and `ComposedPrompt`s. Used for semantic search and autocomplete.

```swift
final class VectorizationService {
    // Primary (text): HuggingFace ONNX model running on-device via CoreML conversion
    //   Recommended: all-MiniLM-L6-v2 (384-dim, fast) or nomic-embed-text-v1.5 (768-dim, higher quality)
    //   Models are bundled as .mlpackage assets converted with exportcoreml / apple/coremltools
    // Fallback (text): Apple NLEmbedding (available, but lower quality — use only if CoreML model unavailable)
    // Images: OpenAI CLIP ViT-B/32 — re-use CoreML port from the image-pipeline repo
    //   (image-pipeline/models/clip_image_encoder.mlpackage)

    func embed(contextItem: ContextItem) async throws -> [Float]
    func embed(text: String) async throws -> [Float]
    func embed(image: CGImage) async throws -> [Float]  // CLIP image encoder

    func similarity(_ a: [Float], _ b: [Float]) -> Float  // cosine similarity
}
```

**Vector Index:** Embeddings are stored in a lightweight SQLite database with a custom cosine-similarity query using SQLite's `json_each` or an optional `sqlite-vec` extension. The index file lives at `~/Library/Application Support/Vapor/vector.db`.

**Model sourcing:** Preferred text models are available on HuggingFace in ONNX format and can be converted to CoreML with `coremltools`. The CLIP image encoder is already ported in the `image-pipeline` repo and should be re-used directly. Apple `NLEmbedding` is kept as a zero-dependency fallback only.

### EntityExtractionService

Uses Apple's `NaturalLanguage` framework for NER (Named Entity Recognition) — no network required. On-device small LLMs (Gemma 2B, Qwen2-1.5B via CoreML) are viable alternatives for higher-quality extraction and should be evaluated once the embedding model integration is stable.

```swift
final class EntityExtractionService {
    // Backend options (configurable):
    //   .nlTagger   — Apple NLTagger, zero-config, instant, adequate quality
    //   .onDeviceLLM — Gemma 2B / Qwen2-1.5B via CoreML; higher recall for code entities
    var backend: EntityExtractionBackend = .nlTagger

    private let tagger = NLTagger(tagSchemes: [.nameType])

    func extract(from text: String) -> [ExtractedEntity]
}
```

Recognized entity types map to `EntityKind`: `NLTag.personalName` → `.person`, `NLTag.organizationName` → `.organization`, `NLTag.placeName` → `.location`.

For code entities (function names, APIs, package names), a regex-augmented pass runs after NER. When the on-device LLM backend is selected, a structured prompt instructs the model to return entities as JSON, which is parsed into `[ExtractedEntity]` directly.

### TaggerService

Auto-tags items using a combination of extracted entities, keyword frequency, and a small on-device classification model.

```swift
final class TaggerService {
    func tag(contextItem: ContextItem) async -> [String]
    func suggestTags(for text: String) async -> [String]
}
```

Tags are lower-case, single-word or hyphenated. Examples: `swift`, `networking`, `architecture`, `apple`, `wwdc`, `performance`.

### GlossarySearchService

Searches across all `GlossaryItem`s and `ContextItem`s using a combination of full-text search and vector similarity.

```swift
@MainActor
@Observable
final class GlossarySearchService {
    // Live search (debounced, used for autocomplete)
    func search(query: String, limit: Int = 10) async -> [SearchResult]

    // Semantic search (slower, used on demand)
    func semanticSearch(query: String, limit: Int = 20) async -> [SearchResult]
}

struct SearchResult {
    var item: GlossaryItem
    var score: Float        // relevance 0.0 – 1.0
    var matchedTerms: [String]
}
```

### PromptCompositionService

Manages the assembly of `ComposedPrompt`s from segments, handles serialisation to plain text for compression, and persists the final record.

```swift
@MainActor
@Observable
final class PromptCompositionService {
    var currentPrompt: ComposedPrompt?

    func addDictatedSegment(_ text: String)
    func addTypedSegment(_ text: String)
    func insertContextItem(_ item: ContextItem, at index: Int)
    func insertGlossaryItem(_ item: GlossaryItem, at index: Int)
    func removeSegment(id: UUID)
    func reorderSegments(from: Int, to: Int)

    func serialise() -> String      // render all segments to plain text
    func finalise() async -> ComposedPrompt    // compress + embed + save
}
```

---

## Browser Extension Changes

The extension gains three new capabilities beyond the existing `ACTIVATE_PICKER` / prompt injection flow:

### 1. Context Capture (Text)

A new toolbar button (or context-menu item) lets the user **capture selected text** or **capture the full article** (via Mozilla Readability) from the current tab. Sends a `CONTEXT_CAPTURE` POST to Vapor:

```json
{
  "type": "CONTEXT_CAPTURE",
  "kind": "articleText",
  "jobId": "ctx-001",
  "url": "https://example.com/article",
  "title": "My Article Title",
  "textContent": "Full extracted article text...",
  "capturedAt": "2025-04-14T02:00:00Z"
}
```

### 2. Image / Binary Capture

The extension intercepts `<img>` tags and XHR responses with binary payloads. The user can right-click an image (or select it via the existing DOM picker) and trigger capture. Large binaries are chunked and streamed to Vapor's `/api/blob` endpoint as multipart uploads.

```json
{
  "type": "CONTEXT_CAPTURE",
  "kind": "image",
  "jobId": "ctx-002",
  "url": "https://cdn.example.com/diagram.png",
  "title": "Architecture Diagram",
  "mimeType": "image/png",
  "dataURL": "data:image/png;base64,..."
}
```

### 3. XHR Interception

The extension's service worker can be instructed (via a `WATCH_XHR` SSE command from Vapor) to forward matching XHR/fetch responses. Vapor specifies URL patterns; the extension filters and forwards matching payloads.

```json
{
  "type": "CONTEXT_CAPTURE",
  "kind": "xhrJSON",
  "jobId": "ctx-003",
  "url": "https://api.example.com/data.json",
  "title": "API Response",
  "textContent": "{\"key\": \"value\"}"
}
```

---

## New API Endpoints (NIO Server)

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/context` | Ingest a text-based `ContextItem` |
| `POST` | `/api/blob` | Multipart upload for binary assets |
| `GET`  | `/api/context/status/:jobId` | Poll processing status |
| `POST` | `/api/watch-xhr` | Configure XHR watch patterns |

These are served by the existing `VaporEmbeddedServer` alongside the current `/api/stream` and `/api/response` endpoints.

---

## Vectorization Index Design

All embeddings are stored in a single SQLite file: `~/Library/Application Support/Vapor/vector.db`.

```sql
CREATE TABLE embeddings (
    id TEXT PRIMARY KEY,       -- UUID string matching embeddingID on the model
    kind TEXT NOT NULL,        -- 'context_item' | 'glossary_item' | 'composed_prompt'
    vector BLOB NOT NULL,      -- raw Float32 array (little-endian)
    dimension INTEGER NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE embedding_text_fts (
    id TEXT,
    content TEXT,
    FOREIGN KEY (id) REFERENCES embeddings(id)
) -- used with SQLite FTS5 for hybrid search
```

**Similarity search:** A Swift helper reads all embedding vectors from the DB (or a subset filtered by `kind`), computes cosine similarity in a tight loop using `vDSP`, and returns the top-K results. For collections up to ~100,000 items this is fast enough without an ANN index. If the collection grows, we can add `sqlite-vec` or an in-process HNSW index.

---

## Prompt Compression Integration

Every `ComposedPrompt` passes through the existing `CompressionService` when the user triggers `⌘↩`. The compression target is `serialise()` — the plain-text rendering of all segments, including inline text from context items.

### No-Compress Token

Some segments must reach the LLM verbatim — URLs, API endpoint paths, version numbers, package names, file paths, and other technical data where compression would destroy meaning. These segments are flagged with `noCompress = true` on `PromptSegment`.

During serialisation, `PromptCompositionService` wraps no-compress segments in a sentinel token pair so the `CompressionService` can pass them through untouched:

```
{{RAW}}https://api.example.com/v2/infer?model=gpt-4o{{/RAW}}
```

The `CompressionService` pre-processes the input string to extract all `{{RAW}}…{{/RAW}}` spans, compresses the remaining text, then splices the raw spans back in at their original positions before returning the final string.

The compressed output therefore looks like:

```
seniorSwiftdev reviewNIOimpl endpoint{{RAW}}https://api.example.com/v2/infer?model=gpt-4o{{/RAW}} focuserrorhandling
```

LLMs already ignore unknown control tokens gracefully; in practice the `{{RAW}}` delimiters can be stripped as a post-processing step before dispatch if the target API is sensitive to them.

Media segments (images, videos) are excluded from the compression text but their citations are included as a compact reference list appended after the compressed text:

```
compressed-prompt-tokens

[1] https://example.com/article — "Article Title" (2025-04-14)
[2] https://cdn.example.com/diagram.png — "Architecture Diagram"
```

---

## Processing Pipeline — Sequence Diagram

```
Extension          BrowserBridge       ContextQueueSvc     Pipeline Services
   │                    │                    │                     │
   │── CONTEXT_CAPTURE ──►                   │                     │
   │                    │── ingest() ────────►                     │
   │                    │                    │── blob store ──────►│
   │                    │                    │                     │
   │                    │                    │── embed() ─────────►│
   │                    │                    │◄── [Float] ─────────│
   │                    │                    │                     │
   │                    │                    │── extract() ───────►│
   │                    │                    │◄── [Entity] ────────│
   │                    │                    │                     │
   │                    │                    │── tag() ───────────►│
   │                    │                    │◄── [String] ────────│
   │                    │                    │                     │
   │                    │                    │── buildCitation() ──►│
   │                    │                    │◄── Citation ─────────│
   │                    │                    │                     │
   │                    │                    │ status = .ready      │
   │                    │◄── UI update ───────│                     │
```

---

## Glossary System — Detailed Design

### Creation Flows

1. **From Context Tray:** Select one or more `ContextItem`s → right-click → "Add to Glossary…" → choose or create a `Glossary` → name the new `GlossaryItem` + optional short code.
2. **From Selection in Composer:** Select inline text or an inline context block in the prompt composer → right-click → "Save as Glossary Item…".
3. **Keyword Cluster:** In Glossary settings, create a `GlossaryItem` of kind `.keywordCluster` by manually entering keywords. Useful for domain-specific jargon.
4. **Auto-suggest:** After processing a batch of `ContextItem`s, Vapor may suggest grouping related items into a new `GlossaryItem` based on entity overlap.

### Short Codes

Each `GlossaryItem` has an optional `shortCode` (e.g., `@swiftnio`, `@my-arch-diagram`). When the user types `@` in the prompt composer, an autocomplete popover appears with matching `GlossaryItem`s.

Inserting a `GlossaryItem` via shortcode expands it **inline** as a `PromptSegment` of kind `.glossaryItem`. The expansion is rendered in the composer as a pill/chip showing the item's name and kind icon.

### Autocomplete Mechanism

Autocomplete is triggered in two ways:

1. **Shortcode trigger (`@`):** Immediate popover filtered by `name` and `shortCode` prefix.
2. **Semantic trigger (natural language):** After a 400ms debounce while the user is typing, `GlossarySearchService.search(query:)` runs against a live index. Top results appear in a non-intrusive suggestion strip below the cursor.

The semantic search combines:
- **FTS5 full-text search** on item names, keywords, and tag lists (high precision, instant)
- **Cosine similarity** over embeddings of the query vs. all `GlossaryItem` embeddings (high recall, ~50ms)
- **Recency + usage** boost: items used recently or frequently rank higher

Results are merged and re-ranked by a weighted score: `0.4 * fts_score + 0.4 * vector_score + 0.2 * usage_boost`.

---

## Files to Create

| File | Purpose |
|---|---|
| `Vapor/Vapor/Models/ContextItem.swift` | SwiftData model for captured context |
| `Vapor/Vapor/Models/GlossaryItem.swift` | SwiftData model for glossary items |
| `Vapor/Vapor/Models/Glossary.swift` | SwiftData model for glossary collections |
| `Vapor/Vapor/Models/ComposedPrompt.swift` | SwiftData model for multi-segment prompts |
| `Vapor/Vapor/Services/ContextQueueService.swift` | Ingestion + processing queue |
| `Vapor/Vapor/Services/VectorizationService.swift` | Embedding generation + vector index |
| `Vapor/Vapor/Services/EntityExtractionService.swift` | NER using NaturalLanguage |
| `Vapor/Vapor/Services/TaggerService.swift` | Auto-tagging |
| `Vapor/Vapor/Services/GlossarySearchService.swift` | FTS + semantic search |
| `Vapor/Vapor/Services/PromptCompositionService.swift` | Segment assembly + serialisation |
| `Vapor/Vapor/Services/BlobStore.swift` | Binary asset storage (disk) |
| `Vapor/Vapor/Views/ContextTrayView.swift` | Live queue + ready items sidebar |
| `Vapor/Vapor/Views/PromptComposerView.swift` | Multi-segment prompt builder |
| `Vapor/Vapor/Views/GlossaryManagerView.swift` | Glossary CRUD + browser |
| `Vapor/Vapor/Views/GlossaryItemDetailView.swift` | Editing a single glossary item |
| `Vapor/Vapor/Views/AutocompletePopoverView.swift` | Shortcode + semantic suggestions |
| `vapor-extension/content-scripts/context-capture.js` | DOM text + image capture |
| `vapor-extension/content-scripts/xhr-interceptor.js` | XHR/fetch monitoring |

---

## Files to Modify

| File | Change |
|---|---|
| `Vapor/Vapor/Services/VaporEmbeddedServer.swift` | Add `/api/context` and `/api/blob` routes |
| `Vapor/Vapor/Services/BrowserBridge.swift` | Handle `CONTEXT_CAPTURE` payloads |
| `Vapor/Vapor/Models/PromptRecord.swift` | Migrate to / unify with `ComposedPrompt` |
| `Vapor/Vapor/Views/SettingsView.swift` | Add Context Management section |
| `Vapor/Vapor/Views/ToolbarView.swift` | Add Context Tray toggle button |
| `vapor-extension/background.js` | Route context capture messages |
| `vapor-extension/popup.html` | Show context capture status |

---

## Implementation Phases

### Phase 1 — Context Capture Pipeline

- [ ] `ContextItem` SwiftData model
- [ ] `BlobStore` for binary assets
- [ ] `/api/context` and `/api/blob` NIO endpoints
- [ ] `BrowserBridge` handling for `CONTEXT_CAPTURE`
- [ ] Extension `context-capture.js` content script
- [ ] `ContextQueueService` (ingest + status tracking only)
- [ ] Basic `ContextTrayView` (list of captured items, status badges)

**Deliverable:** Extension can send text and images to Vapor; items appear in the Context Tray.

### Phase 2 — Processing Pipeline

- [ ] `EntityExtractionService` (NaturalLanguage NER)
- [ ] `TaggerService` (frequency + classification)
- [ ] Citation builder
- [ ] `VectorizationService` (NLEmbedding for text; Vision FeaturePrint for images)
- [ ] Vector SQLite index
- [ ] `ContextQueueService` full pipeline integration
- [ ] Context Tray shows tags, entities, citations on processed items

**Deliverable:** Captured items are fully processed and searchable.

### Phase 3 — Prompt Composer

- [ ] `ComposedPrompt` + `PromptSegment` models
- [ ] `PromptCompositionService`
- [ ] `PromptComposerView` with drag-and-drop segment ordering
- [ ] Inline context item chips in the composer
- [ ] Serialise → compress integration with existing `CompressionService`
- [ ] Citation block appended to compressed output

**Deliverable:** Users can compose multi-segment prompts with inline context.

### Phase 4 — Glossary System

- [ ] `Glossary` + `GlossaryItem` SwiftData models
- [ ] `GlossaryManagerView` (CRUD)
- [ ] `GlossaryItemDetailView`
- [ ] "Add to Glossary" flow from Context Tray and Composer
- [ ] Short code assignment UI

**Deliverable:** Users can build and browse glossaries.

### Phase 5 — Autocomplete & Semantic Search

- [ ] `GlossarySearchService` (FTS5 + vector similarity)
- [ ] `@` trigger in `PromptComposerView`
- [ ] `AutocompletePopoverView` (shortcode + semantic)
- [ ] Semantic suggestion strip (debounced, while typing)
- [ ] XHR interception extension script

**Deliverable:** Full autocomplete experience; XHR data capture.

---

## Privacy & Performance Notes

- **All NLP processing is on-device** (HuggingFace CoreML models, Apple NLTagger, CLIP). No text or images are sent to a network for processing unless the user has configured OpenRouter.
- Binary blobs are stored in the app's sandboxed `Application Support` directory and are never uploaded anywhere.
- The vector index grows linearly. At 1,000 items, each with a 512-float embedding, the index is ~2 MB — trivially small.
- Blob storage is capped at a user-configurable limit (default: 500 MB). Eviction removes the oldest items first.
- XHR interception is **opt-in per-tab** and must be explicitly activated by the user from Vapor.

---

## Open Questions

1. **Multi-modal LLM integration:** Use OpenRouter's multi-modal endpoints as the primary destination for composed prompts containing image segments (OpenRouter supports GPT-4o, Claude 3.5 Sonnet, Gemini 1.5 Pro, etc.). Corporate or firewall-internal tools are addressed by designating any open browser tab and its prompt input element as a delivery destination via the existing bidirectional bridge — the extension injects the serialised prompt (and, where the UI supports it, inline images) directly. A browser-extension **plugin system** (custom destination adapters) is a natural follow-on that will make this extensible to arbitrary internal tools without shipping new app versions; tracked as a future issue.

2. **Video handling (low priority):** Full video clips can be very large. Preferred approach: embed `ffmpeg` (static binary or via Swift wrapper) to pre-process clips — reduce frame rate, lower resolution, and trim to a user-set max duration — before any frame extraction or transcription. Options: (a) extract key frames post-ffmpeg via `AVAssetImageGenerator`; (b) transcribe the audio track via `SFSpeechRecognizer` and capture as text. The ffmpeg path gives the most control over file size and keeps the blob store manageable. Low priority for now — design with this capability in mind but do not block Phase 1–3 on it.

3. **Sync / companion apps:** Design the data layer (SwiftData schema, blob store paths, vector index) to be iCloud Drive–compatible from the start, so a future iOS or Android companion app can sync context items and glossaries. iCloud-backing of the blob store is deferred (quota implications); text metadata and the vector index are lightweight enough to sync via iCloud Documents. A companion mobile app would make capturing context while on the go natural — not high priority now, but the schema should not make it hard later.

4. **Citation formats:** Generate two formats automatically: **URL-only** (always, zero-config) and **APA** (on demand, sufficient for most research and writing workflows). MLA and Chicago can be added later via a format-string template if demand warrants it.

5. **Glossary sharing:** Exportable/importable glossaries (JSON) would enable team-level shared glossary packs. Tracked as a follow-up issue — not in scope for the current implementation phases.

---

## References

- [HuggingFace ONNX models — all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2)
- [HuggingFace ONNX models — nomic-embed-text-v1.5](https://huggingface.co/nomic-ai/nomic-embed-text-v1.5)
- [Apple coremltools — ONNX conversion](https://coremltools.readme.io/docs/convert-learning-models)
- [OpenAI CLIP — CoreML port](https://github.com/openai/CLIP) (see also: `image-pipeline` repo)
- [Gemma 2B on CoreML](https://huggingface.co/google/gemma-2b)
- [Qwen2-1.5B on CoreML](https://huggingface.co/Qwen/Qwen2-1.5B)
- [Apple NaturalLanguage Framework](https://developer.apple.com/documentation/naturallanguage)
- [Mozilla Readability](https://github.com/mozilla/readability) — article extraction in extension
- [SQLite FTS5](https://www.sqlite.org/fts5.html)
- [sqlite-vec](https://github.com/asg017/sqlite-vec) — optional vector extension for SQLite
- `docs/plan-browser-extension.md` — existing NIO server + SSE architecture
- `docs/plan-web-scraping.md` — existing scrape command protocol
- `docs/plan-multimodal-llm-upgrade.md` — multi-modal LLM backend
