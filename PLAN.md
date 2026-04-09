# Vapor - Prompt Compression Editor

A macOS floating text editor that captures text via speech-to-text, compresses it using the prompt-cloud technique, and saves prompt history to SwiftData.

## Overview

Vapor is a lightweight macOS app designed for developers who frequently send prompts to LLMs and agentic systems. It reduces token usage by compressing prompts using the [prompt-cloud](https://github.com/swbratcher/prompt-cloud) technique, saving costs and context window space.

**Key Features:**
- Speech-to-text input (hold Fn key to dictate)
- Multiple compression backends (Apple Foundation Models, OpenRouter, rule-based)
- One-click "Compress & Copy" workflow
- Floating window for easy access alongside terminal/IDE
- Full prompt history with compression stats
- Toast notifications for feedback

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    VaporApp (SwiftUI)                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ EditorView  │  │ ToolbarView  │  │ HistoryListView │   │
│  └──────┬──────┘  └──────┬───────┘  └────────┬─────────┘   │
│         │                │                    │             │
│  ┌──────▼────────────────▼────────────────────▼─────────┐  │
│  │                  EditorViewModel                     │  │
│  │  - content: String                                   │  │
│  │  - compressedContent: String                         │  │
│  │  - compressionRatio: Double                          │  │
│  │  - isDictating: Bool                                  │  │
│  └──────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                       Services Layer                        │
│  ┌─────────────────┐  ┌─────────────────────────────────┐  │
│  │ SpeechDictation │  │     CompressionService          │  │
│  │    Service      │  │  ┌─────────────────────────────┐│  │
│  └─────────────────┘  │  │ FoundationModelsCompressor ││  │
│  ┌─────────────────┐  │  │ OpenRouterCompressor       ││  │
│  │ FnDictation     │  │  │ RuleBasedCompressor        ││  │
│  │    Monitor      │  │  └─────────────────────────────┘│  │
│  └─────────────────┘  └─────────────────────────────────┘  │
│  ┌─────────────────┐  ┌─────────────────────────────────┐  │
│  │ ClipboardService│  │      PromptHistoryService       │  │
│  └─────────────────┘  └─────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                      Data Layer                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SwiftData Models                        │   │
│  │  - PromptRecord (id, original, compressed, ratio...) │   │
│  │  - CompressionSettings                              │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Compression Backends

### 1. Apple Foundation Models (Primary)
- **Cost:** Free
- **Requirements:** macOS 26+ (Tahoe), Apple Intelligence enabled
- **Privacy:** All inference on-device, no data leaves device
- **Quality:** ~3B parameter model, good for compression tasks
- **Latency:** Sub-second

### 2. OpenRouter API (Secondary)
- **Cost:** ~$0.01/1M tokens (GLM-5)
- **Default Model:** `glm-5`
- **Requirements:** API key (stored in Keychain)
- **Quality:** Better semantic understanding
- **Latency:** Network-dependent (~1-2s)

### 3. Rule-Based (Fallback)
- **Cost:** Free
- **Requirements:** None (always available)
- **Quality:** ~60-70% of LLM quality
- **Latency:** Instant

**Fallback Chain:** Foundation Models → OpenRouter → Rule-Based

---

## Prompt-Cloud Compression Technique

Based on [prompt-cloud](https://github.com/swbratcher/prompt-cloud):

**Compression Rules:**
1. Strip articles: `a`, `an`, `the`
2. Strip prepositions: `in`, `on`, `at`, `to`, `for`, `of`, `with`, `by`, `from`, `into`, `onto`
3. Strip auxiliary verbs: `is`, `are`, `was`, `were`, `be`, `have`, `has`, `had`, `will`, `would`, `should`, `can`, `could`, `may`, `might`, `must`
4. Strip pronouns: `I`, `you`, `he`, `she`, `it`, `we`, `they`, `my`, `your`, `his`, `her`, `its`, `our`, `their`
5. Strip conjunctions: `and`, `or`, `but`, `so`, `yet`
6. **Preserve negations explicitly:** `not`, `never`, `don't`, `won't`, `can't`, `no`, `unless`
7. **Preserve exact values:** numbers, URLs, file paths, API endpoints
8. Fuse remaining words into lowercase compound strings

**Example:**
```
Original: "You are a senior backend engineer reviewing pull requests. Focus on correctness and performance. Be direct but not harsh."

Compressed: "seniorbackendengineer reviewingpullrequests focuscorrectnessperformance directnotharsh"
```

**Typical Results:**
- Behavioral prompts: 40-60% token reduction
- Technical specs: 10-20% token reduction
- Mixed content: 25-40% token reduction

---

## User Interface

### Main Window (Floating)

```
┌─────────────────────────────────────────┐
│  [🎤] [Compress & Copy] [Copy ▼] [⚙️]  │  ← Toolbar
├─────────────────────────────────────────┤
│                                         │
│     Original Text Editor                │
│     (NSTextView - editable)             │
│                                         │
├─────────────────────────────────────────┤
│  Ratio: 0.65 | Tokens: 234 → 152       │  ← Stats bar
├─────────────────────────────────────────┤
│                                         │
│     Compressed Preview                  │
│     (NSTextView - read-only)            │
│                                         │
└─────────────────────────────────────────┘
```

**Window Properties:**
- Size: 500×400 (default), resizable
- Level: Floating (always on top)
- Behavior: Can join all spaces, works in full-screen

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Compress & Copy | `⌘ + Return` |
| Copy Original Only | `⌘ + Shift + C` |
| Clear | `⌘ + N` |
| Toggle Dictation | `Fn` (hold) |

### Toast Notifications

- **Success:** "Compressed & copied (0.65 ratio)"
- **Error:** "Compression failed: [reason]"
- **Duration:** 2 seconds, auto-dismiss

---

## Data Models

### PromptRecord (SwiftData)

```swift
@Model
final class PromptRecord {
    var id: UUID
    var originalText: String
    var compressedText: String
    var originalTokenCount: Int
    var compressedTokenCount: Int
    var compressionRatio: Double
    var compressorUsed: String  // "foundationModels" | "openRouter" | "ruleBased"
    var createdAt: Date
    var modifiedAt: Date
    var isFavorite: Bool
    var tags: [String]
}
```

### CompressionSettings (SwiftData)

```swift
@Model
final class CompressionSettings {
    var selectedCompressor: String  // "foundationModels" | "openRouter" | "ruleBased"
    var openRouterApiKey: String?   // Stored in Keychain, this is reference
    var openRouterModel: String     // Default: "glm-5"
    var autoSavePrompts: Bool       // Default: true
    var showCompressionStats: Bool  // Default: true
}
```

---

## File Structure

```
Vapor/
├── VaporApp.swift
├── ContentView.swift
│
├── Models/
│   ├── PromptRecord.swift
│   ├── CompressionSettings.swift
│   └── CompressorType.swift
│
├── ViewModels/
│   └── EditorViewModel.swift
│
├── Views/
│   ├── NativeTextEditor.swift
│   ├── EditorTextViewRegistry.swift
│   ├── ToolbarView.swift
│   ├── StatsBarView.swift
│   ├── SettingsView.swift
│   ├── HistoryListView.swift
│   ├── DictationButton.swift
│   └── ToastView.swift
│
├── Services/
│   ├── SpeechDictationService.swift
│   ├── FnDictationMonitor.swift
│   ├── ClipboardService.swift
│   ├── PromptHistoryService.swift
│   ├── ToastService.swift
│   └── Compression/
│       ├── CompressorProtocol.swift
│       ├── CompressionService.swift
│       ├── FoundationModelsCompressor.swift
│       ├── OpenRouterCompressor.swift
│       └── RuleBasedCompressor.swift
│
└── Utils/
    ├── TokenEstimator.swift
    └── KeychainService.swift
```

---

## Implementation Phases

### Phase 1: Core Editor & STT (Week 1)

**Goal:** Basic text editor with speech-to-text

**Tasks:**
- [ ] Create NativeTextEditor (NSTextView wrapper)
- [ ] Implement EditorViewModel with basic state
- [ ] Add SpeechDictationService (from NativeEditor reference)
- [ ] Add FnDictationMonitor for Fn key detection
- [ ] Implement ClipboardService
- [ ] Basic ContentView with editor and toolbar placeholder

**Deliverable:** Working text editor with Fn-key dictation

---

### Phase 2: Compression Engine (Week 2)

**Goal:** All three compression backends working

**Tasks:**
- [ ] Define CompressorProtocol
- [ ] Implement RuleBasedCompressor (quick win, always available)
- [ ] Implement FoundationModelsCompressor (macOS 26+)
- [ ] Implement OpenRouterCompressor with GLM-5 default
- [ ] Create CompressionService coordinator with fallback logic
- [ ] Add TokenEstimator utility
- [ ] Add KeychainService for API key storage

**Deliverable:** Working compression with all backends

---

### Phase 3: Data & History (Week 3)

**Goal:** SwiftData persistence and history UI

**Tasks:**
- [ ] Create PromptRecord SwiftData model
- [ ] Create CompressionSettings SwiftData model
- [ ] Implement PromptHistoryService
- [ ] Add auto-save logic after compression
- [ ] Create HistoryListView with search
- [ ] Create SettingsView with compressor selection
- [ ] Add OpenRouter API key input in settings

**Deliverable:** Full history tracking and settings

---

### Phase 4: UI Polish & Floating Window (Week 4)

**Goal:** Production-ready UI

**Tasks:**
- [ ] Configure floating window properties
- [ ] Implement ToolbarView with all buttons
- [ ] Add StatsBarView with compression ratio
- [ ] Implement ToastService and ToastView
- [ ] Add keyboard shortcuts
- [ ] Polish animations and transitions
- [ ] Error handling and edge cases
- [ ] Testing on macOS 26+ and fallback testing

**Deliverable:** Production-ready app

---

## Phase 2 (Future): Vectorization & Semantic Search

**Goal:** Make prompt history searchable by meaning, not just text

**Planned Features:**
- Embedding generation for each saved prompt
- Vector storage in SwiftData or external DB
- Semantic search using cosine similarity
- Find similar prompts feature
- Clustering/grouping of related prompts

**Technologies to Consider:**
- Apple's on-device embedding models
- OpenAI embeddings API
- Local vector DB (SQLite with vector extension)

**Note:** This is deferred to Phase 2. Current implementation will use basic text search only.

---

## Technical Notes

### Apple Foundation Models Availability

```swift
// Check availability before use
switch SystemLanguageModel.default.availability {
case .available:
    // Ready to use
case .unavailable(.deviceNotEligible):
    // Hardware doesn't support - permanent
case .unavailable(.appleIntelligenceNotEnabled):
    // User needs to enable in Settings
case .unavailable(.modelNotReady):
    // Model downloading - transient
@unknown default:
    break
}
```

### OpenRouter API

**Endpoint:** `https://openrouter.ai/api/v1/chat/completions`

**Headers:**
```
Authorization: Bearer <api_key>
HTTP-Referer: https://github.com/memetic-research-labs-llc/comp-tok-stt
```

**Request Body:**
```json
{
  "model": "glm-5",
  "messages": [
    {"role": "system", "content": "<prompt-cloud directive>"},
    {"role": "user", "content": "<text to compress>"}
  ]
}
```

### Token Estimation

Approximate token count using word count:
- English: ~1.3 tokens per word
- Code: ~1.5 tokens per word
- Use cl100k_base tokenizer for accurate count (optional)

---

## Dependencies

**System Frameworks:**
- SwiftUI (macOS 14+)
- SwiftData (macOS 14+)
- Speech (for STT)
- AVFoundation (for audio capture)
- FoundationModels (macOS 26+, optional)

**External:**
- OpenRouter API (optional, requires API key)

**No third-party dependencies** - all native Apple frameworks

---

## Testing Strategy

### Unit Tests
- RuleBasedCompressor logic
- TokenEstimator accuracy
- Compression ratio calculations
- SwiftData CRUD operations

### Integration Tests
- Full compression flow with each backend
- Clipboard integration
- History auto-save
- Settings persistence

### Manual Testing
- Fn key dictation on various macOS versions
- Floating window behavior across spaces
- Apple Intelligence availability handling
- OpenRouter API error handling

---

## Success Metrics

- **Compression quality:** 40%+ token reduction on behavioral prompts
- **Latency:** <1s for Foundation Models, <2s for OpenRouter
- **Reliability:** 99%+ success rate with fallback chain
- **UX:** One-click workflow from text to compressed clipboard

---

## References

- [Prompt-Cloud Compression](https://github.com/swbratcher/prompt-cloud)
- [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels)
- [OpenRouter API](https://openrouter.ai/docs)

---

## License

MIT License - See LICENSE file for details
