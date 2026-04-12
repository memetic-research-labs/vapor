# Plan: Screenshot Awareness

## Overview

**Screenshot Awareness** is a feature that makes Vapor automatically detect new screenshots on the user's Mac and surface them as selectable thumbnails that can be attached to an LLM prompt. The goal is to eliminate the friction of manually locating, opening, and describing a screenshot — instead, Vapor watches for new images, shows a thumbnail strip, and lets the user add one or more images to their current prompt with a single click.

Combined with a multimodal local LLM (e.g., Gemma 4 via Ollama), Vapor can then **describe the image in natural language, generate a prompt pre-filled from the screenshot content, or compress a vision-enriched prompt** before sending it to a cloud LLM.

---

## User Story

> As a developer, when I take a screenshot of an error, a UI bug, or a code snippet, I want Vapor to automatically notice it and offer it as a one-click attachment to my next prompt — so that I can immediately ask an LLM "what's wrong here?" without switching apps or copy-pasting paths.

---

## Feature Concept

```
┌──────────────────────────────────────────────────┐
│  Vapor (expanded view)                           │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │  Type your prompt here...                │   │
│  │  (or hold Fn to dictate)                 │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  📷 Recent Screenshots                [Clear]   │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐                   │
│  │ ✓  │ │    │ │    │ │    │  ← thumbnails      │
│  │ img│ │ img│ │ img│ │ +  │     (4 most recent)│
│  └────┘ └────┘ └────┘ └────┘                   │
│   selected                                       │
│                                                  │
│  [🎤] [🖼️ Describe] [Compress & Copy] [⚙️]      │
│└─────────────────────────────────────────────────┘
```

**Key interactions:**
- Thumbnail strip appears automatically when a new screenshot is detected (or when expanded view is opened with recent screenshots present).
- Clicking a thumbnail selects/deselects it (multiple selection supported).
- **"Describe"** button sends selected images to the local vision LLM and inserts a natural-language description into the prompt editor.
- Selected images can also be included verbatim in the final prompt sent to a cloud model (as base64 or Markdown image references).

---

## Technical Design

### 1. Screenshot Watcher Service

`ScreenshotWatcherService` monitors for new screenshots using **Spotlight's `NSMetadataQuery`** with the `kMDItemIsScreenCapture` attribute. macOS Screenshot.app sets this attribute on every image it creates, regardless of where the user has configured screenshots to be saved. This means the service works correctly whether screenshots go to `~/Desktop`, `~/Pictures/Screenshots`, or any custom path — with no need to read the user's configured save location or watch a specific directory.

**Implementation:**

```swift
final class ScreenshotWatcherService: ObservableObject {
    @Published var recentScreenshots: [ScreenshotItem] = []

    private var metadataQuery: NSMetadataQuery?
    private let maxItems = 6

    func start() {
        // NSMetadataQuery — Spotlight watches for files with kMDItemIsScreenCapture == 1
        // (set automatically by Screenshot.app on every capture).
        // No directory path or user defaults reading needed.
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.sortDescriptors = [
            NSSortDescriptor(key: "kMDItemContentCreationDate", ascending: false)
        ]
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        // Register for NSMetadataQueryDidUpdateNotification to update recentScreenshots
        self.metadataQuery = query
        query.start()
    }

    func stop() {
        metadataQuery?.stop()
    }
}
```

**Why `NSMetadataQuery` + `kMDItemIsScreenCapture`?**
- Zero false positives — `kMDItemIsScreenCapture` is only set by Screenshot.app, not by arbitrary PNG saves.
- Location-agnostic — works regardless of where macOS is configured to save screenshots.
- No polling or kqueue file-descriptor watching needed.
- Spotlight indexes new screenshots within seconds on a typical Mac.

> **Note:** Because the app sandbox is disabled, no special entitlement is needed to read files returned by the Spotlight query. File access is subject only to normal macOS user-space permissions (i.e., files the user owns are readable without further prompting). An `NSOpenPanel` bookmark is still recommended the first time the feature is enabled, to make the permission intent explicit to the user.

---

### 2. ScreenshotItem Model

```swift
struct ScreenshotItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let createdAt: Date
    var thumbnail: NSImage?
    var isSelected: Bool
}
```

Thumbnails are generated asynchronously using `QLThumbnailGenerator` (QuickLook) at 80×60 pt so they render crisply on Retina displays without blocking the main thread.

---

### 3. ScreenshotThumbnailStripView

A horizontal `ScrollView` of thumbnail cards shown below the main editor in the expanded view. Appears only when `recentScreenshots.count > 0`.

```
┌──────────────────────────────────────────────────────┐
│ 📷 Screenshots (3 new)                     [Clear]  │
│ ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐            │
│ │      │  │      │  │ ☑ ✓  │  │      │            │
│ │ img1 │  │ img2 │  │ img3 │  │  +   │            │
│ └──────┘  └──────┘  └──────┘  └──────┘            │
│  tap to select         selected     add more        │
└──────────────────────────────────────────────────────┘
```

Selection state is maintained in the view model (`EditorViewModel`) so that downstream services (vision LLM, clipboard export) know which images to act on.

---

### 4. Vision LLM Integration

When the user taps **"Describe"**, Vapor:

1. Reads the selected `ScreenshotItem.url` files from disk.
2. Encodes each image as base64 PNG.
3. Calls `OllamaVisionService.describe(images:context:)` with the current prompt text as context.
4. Streams the response and **appends** it to the prompt editor (preceded by a `---` divider so the user can easily delete it).

```swift
func describeSelectedScreenshots() async {
    let selectedURLs = selectedScreenshots.map(\.url)
    guard !selectedURLs.isEmpty else { return }

    let context = content.isEmpty ? nil : content
    let stream = try await visionService.describe(
        imageURLs: selectedURLs,
        userContext: context
    )
    for try await token in stream {
        content += token
    }
}
```

**Fallback:** If no local vision model is available, offer to call the OpenRouter API with an image-capable model (e.g., `google/gemma-3-27b-it`).

---

### 5. Prompt Export with Images

When compressing or copying, if images are selected, Vapor can:

- **Option A — Description only:** Replace image attachments with the LLM-generated description in the clipboard. Most compatible with cloud LLMs.
- **Option B — Markdown image links:** Export `![screenshot](file:///path/to/screenshot.png)` references. Useful when pasting into tools that can render local images.
- **Option C — Raw base64:** Include `data:image/png;base64,...` blocks. Supported by the OpenAI vision API.

The export format is configurable in **Settings > Screenshot Awareness**.

---

### 6. Settings

Add a **Screenshot Awareness** section to `SettingsView`:

| Setting | Type | Default |
|---|---|---|
| Enable Screenshot Awareness | Toggle | Off (opt-in) |
| Screenshots folder | Path picker | auto-detected via `kMDItemIsScreenCapture` |
| Max thumbnails to show | Stepper (1–10) | 4 |
| Auto-clear after use | Toggle | On |
| Vision model | Picker (Ollama models with vision) | `gemma4:4b` |
| Image export format | Picker (Description / Markdown / Base64) | Description |

---

## Permissions Required

The app sandbox is **disabled** (`com.apple.security.app-sandbox = false`), so no special entitlements are needed to read files returned by the Spotlight query.

| Action | Mechanism |
|---|---|
| Discover screenshot metadata | `NSMetadataQuery` — no permission prompt required |
| Read image file contents | Normal user-space file access (files owned by the user are readable directly) |
| User transparency (recommended) | Show an `NSOpenPanel` targeting the screenshots folder the first time the feature is enabled; persist the chosen URL as a security-scoped bookmark so the user's intent is explicit and the app can re-derive the path after a relaunch |
| Accessibility (optional) | Detect screenshot keyboard shortcut (`⌘ ⇧ 3/4/5`) to trigger an immediate watcher refresh — only needed for sub-second latency, the Spotlight-based approach already works without it |

> The app must **never** read image file contents without the user's knowledge. The Spotlight query surfaces only metadata (path, date) until the user selects a thumbnail or taps "Describe".

---

## Implementation Phases

### Phase 1 — Screenshot Detection (3–4 days)

- [ ] Implement `ScreenshotWatcherService` using `NSMetadataQuery` + `kMDItemIsScreenCapture`
- [ ] Generate `ScreenshotItem` entries with async QuickLook thumbnails
- [ ] Start watcher on app launch (from `VaporApp.init()` or main window `.onAppear`), stop on quit
- [ ] Manual test: take a screenshot → item appears in `recentScreenshots` within 5 seconds

### Phase 2 — Thumbnail Strip UI (2–3 days)

- [ ] Create `ScreenshotThumbnailStripView` (horizontal scroll, tap-to-select, multi-select)
- [ ] Integrate strip into `ContentView` expanded layout (below editor, above stats bar)
- [ ] Animate strip appearance/disappearance
- [ ] Add "Clear" button (clears selection and hides strip without deleting files)
- [ ] Badge count on Vapor menu-bar icon when new screenshots detected

### Phase 3 — Vision LLM Integration (3–4 days)

- [ ] Create `OllamaVisionService` (depends on multimodal LLM upgrade plan)
- [ ] Add "Describe" toolbar button (visible only when screenshots selected and vision model available)
- [ ] Stream description into editor with separator
- [ ] Fallback to OpenRouter vision model if no local model configured

### Phase 4 — Settings & Permissions (1–2 days)

- [ ] Add Screenshot Awareness section to `SettingsView`
- [ ] Persist settings in `CompressionSettings` SwiftData model (add new fields)
- [ ] Implement scoped bookmark for screenshots folder
- [ ] Onboarding prompt: request folder access when feature first enabled

### Phase 5 — Export & Polish (2 days)

- [ ] Implement the three export formats (Description / Markdown / Base64)
- [ ] Respect export format setting when building clipboard content
- [ ] Accessibility: VoiceOver labels for thumbnail strip
- [ ] UI test: select thumbnail → tap Describe → description appears in editor

---

## UX Considerations

- **Non-intrusive by default:** Feature is off by default. Users enable it in Settings. The thumbnail strip never appears for users who haven't opted in.
- **Privacy first:** Vapor does not upload screenshots anywhere. All processing is local (vision LLM via Ollama). Cloud export only happens if the user explicitly chooses OpenRouter.
- **Quick clear:** One tap removes the strip — useful if a screenshot contains sensitive content the user does not want to accidentally include.
- **Instant hit:** The moment a user takes a screenshot of an error, the thumbnail appears in Vapor. They hold Fn to dictate "what is causing this error?" and tap Describe — within seconds they have a vision-grounded prompt ready to compress and send to Claude or GPT.

---

## Dependencies

- **Multimodal LLM Upgrade** (see `plan-multimodal-llm-upgrade.md`) — `OllamaVisionService` requires Ollama ≥ 0.6.5 and a vision-capable model like `gemma4:4b`.
- **`QLThumbnailGenerator`** — available macOS 10.15+, no extra entitlements needed.
- **`NSMetadataQuery`** — available macOS 10.4+, Spotlight must be enabled (it is by default).

---

## Success Metrics

| Metric | Target |
|---|---|
| Time from screenshot taken to thumbnail visible in Vapor | < 5 seconds |
| Time from "Describe" tap to first token in editor | < 3 seconds (local) |
| User retention after enabling feature | > 80% keep it enabled after 7 days *(requires analytics instrumentation — currently unmeasurable; treat as a design goal, not a launch gate)* |
| False positive rate (non-screenshot images surfaced) | 0% — `kMDItemIsScreenCapture` filter is precise |

---

## References

- [NSMetadataQuery Programming Guide](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/Introduction.html)
- [kMDItemIsScreenCapture Spotlight attribute](https://developer.apple.com/documentation/coreservices/kmditemisscreencapture)
- [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)
- [Ollama multimodal API](https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-chat-completion)
- [Gemma 4 vision capabilities](https://huggingface.co/collections/google/gemma-4-release-67f8f55b4b23a5abe2cce75b)
