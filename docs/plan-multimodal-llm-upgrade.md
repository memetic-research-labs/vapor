# Plan: Multimodal LLM Upgrade — Gemma 4 and Beyond

## Overview

Vapor uses **llama.cpp** (via the `swift-llama-cpp` Swift package) for on-device LLM inference. This plan covers what must change to add support for **Gemma 4** and other state-of-the-art models — particularly those with **vision/image input** capabilities that are needed for the Screenshot Awareness feature.

> **Status (PR #69):** The bundled `ollama-darwin` binary was removed. Ollama is no longer included in the app bundle or started/stopped by Vapor. The app detects a user-installed Ollama (`brew install ollama` / official installer) at runtime, but it is not yet surfaced as a selectable compression backend. The current compression defaults to on-device swift-llama-cpp (`.localLLM`).

---

## Background: llama.cpp vs. Ollama

| | llama.cpp | Ollama |
|---|---|---|
| **What it is** | Low-level C/C++ inference engine (runs GGUF models) | Higher-level model runner built on llama.cpp |
| **Bindings used by Vapor** | `swift-llama-cpp` Swift package | User-installed binary (detected via PATH) |
| **API surface** | C API wrapped in Swift | HTTP REST API (`/api/chat`, `/api/generate`) |
| **Model management** | Manual (GGUF file download) | `ollama pull <model>` CLI command |
| **Multimodal support** | Requires llava.cpp / clip model side-car | Native: `ollama run gemma4` handles vision automatically |

Vapor currently uses only the llama.cpp path:
- `LocalLLMCompressor.swift` calls `swift-llama-cpp` directly for text compression (`.localLLM` backend).
- A user-installed Ollama daemon can be detected but is not yet wired as a compression or vision backend.

**For multimodal (vision) input the Ollama path is strongly preferred** because Ollama handles the CLIP vision encoder and token interleaving internally. Calling llama.cpp directly for vision requires embedding two separate models and handling image patch tokenisation manually — far more work with no practical benefit.

---

## What Gemma 4 Brings

Google released **Gemma 4** (April 2025) with the following relevant properties:

| Property | Detail |
|---|---|
| Sizes | 1B, 4B, 12B, 27B parameters |
| Context window | Up to 128K tokens |
| Vision input | Yes — all sizes support image input (multimodal) |
| License | Gemma Terms of Use (permissive for local use) |
| GGUF availability | Available on Hugging Face (e.g., `lmstudio-community/gemma-4-12b-it-GGUF`) |
| Ollama support | `ollama run google/gemma4` (requires Ollama ≥ 0.6.x) |

The 12B Q4_K_M quantisation fits comfortably in 16 GB RAM (typical M-series MacBook Pro). The 4B variant runs on 8 GB RAM.

Other strong multimodal candidates to support alongside Gemma 4:

| Model | Sizes | Vision | RAM (Q4) |
|---|---|---|---|
| **LLaVA 1.6** | 7B, 13B, 34B | ✅ | 5–20 GB |
| **Qwen2.5-VL** | 3B, 7B, 72B | ✅ | 3–45 GB |
| **Phi-4 Multimodal** | 14B | ✅ | ~9 GB |
| **Mistral Small 3.1** | 24B | ✅ | ~15 GB |
| **Gemma 4** | 1B–27B | ✅ | 1–18 GB |

---

## Required Changes

### 1. Upgrade Ollama Version

The bundled `ollama-darwin` binary in `Vapor/scripts/download-ollama.sh` is pinned to **v0.5.7**, which predates Gemma 4 support.

**Action:** Bump `OLLAMA_VERSION` to **≥ 0.6.5** (first version with Gemma 4 GGUF support).

```bash
# Vapor/scripts/download-ollama.sh
OLLAMA_VERSION="0.6.5"   # was 0.5.7
```

Test that `ollama run google/gemma4:4b` succeeds on Apple Silicon before pinning to a specific release.

**Acceptance criteria:**
- `ollama --version` reports the bundled version `>= 0.6.5`.
- A simple `ollama run google/gemma4:4b` invocation (or equivalent local API call) succeeds inside the app sandbox.
- Existing models (Qwen2.5-7B, Llama 3) still work.

---

### 2. Add an OllamaCompressor Service

Currently Vapor has no service that routes prompts through the local Ollama HTTP API. Create `OllamaCompressor.swift` under `Services/Compression/`:

```swift
actor OllamaCompressor: Compressor {
    let name = "Ollama (Local)"
    private let endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    private let model: String  // e.g. "gemma4:4b"

    // Actor isolation already makes this async from external callers;
    // no explicit `get async` annotation needed.
    var isAvailable: Bool {
        // ping /api/tags to verify daemon is running and model is pulled
        false
    }

    func compress(_ text: String) async throws -> CompressedResult { ... }
}
```

This compressor becomes the **primary on-device backend** for any model managed by Ollama (text or multimodal).

---

### 3. Add a Vision-Capable Chat Method

For the Screenshot Awareness feature, text-only `/api/chat` calls must be extended to accept image data. Ollama's chat API already supports this:

```json
{
  "model": "gemma4:4b",
  "messages": [
    {
      "role": "user",
      "content": "Describe what you see",
      "images": ["<base64-encoded-PNG>"]
    }
  ]
}
```

Create a `OllamaVisionService` (separate from the compressor) that accepts a `[URL]` of image files, encodes them to base64, and returns a streaming chat response. This service will be consumed by the Screenshot Awareness feature.

---

### 4. Update Model Management UI (Settings)

Add a new **Local Models** section to `SettingsView`:

- List installed Ollama models (call `GET /api/tags`).
- Allow users to pull new models by name (calls `POST /api/pull` with streaming progress).
- Show model metadata: size on disk, parameter count, vision support flag.
- Let users select the active model for compression and for vision chat.

Model recommendations surfaced in the UI:

| Use case | Recommended | RAM |
|---|---|---|
| Text compression (fast) | `qwen2.5:7b` (current default) | 5 GB |
| Text compression (best) | `gemma4:12b` | 9 GB |
| Vision / screenshot chat | `gemma4:4b` | 3 GB |
| Vision (high quality) | `qwen2.5-vl:7b` | 5 GB |

---

### 5. Update `LocalLLMCompressor` Fallback Logic

The current `LocalLLMCompressor` calls `swift-llama-cpp` directly (GGUF via file path). Keep this as a fallback for users who have already downloaded a GGUF model but do not want to use Ollama.

Update `CompressionService` priority chain:

```
Foundation Models → Ollama (OllamaCompressor) → swift-llama-cpp → OpenRouter → Rule-Based
```

> **Architectural decision:** This is a significant change from the current per-backend fallback model, where each selected backend independently falls back to rule-based. Moving to a sequential chain changes the fundamental compression strategy — the selected backend is no longer authoritative; the chain is. This trade-off should be reviewed before implementation. An alternative is to keep the current model and surface Ollama as a first-class selectable backend alongside the others, leaving the fallback chain unchanged.

---

### 6. Ollama Daemon Lifecycle Management

The Ollama daemon must be started before use and ideally stopped on app quit. Create `OllamaDaemonManager`:

```swift
actor OllamaDaemonManager {
    static let shared = OllamaDaemonManager()
    private var process: Process?
    private let pidFilePath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".vapor-ollama.pid")

    func start() async throws { ... }   // launches bundled ollama serve, writes PID file
    func stop()                { ... }  // terminates process, removes PID file
    func isRunning() async -> Bool { ... }
}
```

**App lifecycle integration — SwiftUI `App` protocol (no `AppDelegate`)**

Vapor uses `VaporApp: App` (SwiftUI lifecycle); there is **no `AppDelegate`** and no `NSApplicationDelegateAdaptor` in the codebase. Do not reference `applicationDidFinishLaunching` or `applicationWillTerminate` — they do not exist. Instead:

- **Start daemon:** call `OllamaDaemonManager.shared.start()` from `VaporApp.init()` or inside the main `Window`'s `.onAppear` modifier (same place `setupWindowOnAppear()` is already called).
- **Stop daemon:** SwiftUI has no guaranteed `willTerminate` equivalent. Use a combination of:
  - `NSWorkspace.shared.notificationCenter.addObserver` for `NSWorkspaceWillPowerOffNotification` (covers logout/shutdown).
  - An `atexit` handler registered in `VaporApp.init()` (covers normal quit and force-quit via `kill -9`).
  - Scene phase observation via `@Environment(\.scenePhase)` and `.onChange(of: scenePhase)` for graceful quit.

**Orphaned process handling**

If a previous Vapor launch left a zombie `ollama serve` binding port 11434:
1. On startup, attempt a health-check `GET http://127.0.0.1:11434/` before spawning a new process.
2. If the health-check succeeds, reuse the existing daemon (skip `Process.launch`).
3. If a PID file exists but the health-check fails, kill the stale PID before starting fresh.

**Port conflict with other apps**

If another application (e.g., a user's own Ollama installation) is already bound to port 11434:
- Reuse it if the `/api/tags` endpoint responds correctly — Ollama's API is version-stable.
- If the port is bound by a non-Ollama process, fail gracefully and surface an error in the UI with a "Change port" option (store the configured port in `UserDefaults`).

Consider writing a PID file to `~/.vapor-ollama.pid` so startup, restart, and crash-recovery logic are all deterministic.

---

### 7. Entitlements

The app sandbox is **already disabled** (`com.apple.security.app-sandbox = false` in `Vapor.entitlements`), so sandbox-specific entitlements like `temporary-exception.files` and Mac App Store distribution restrictions do **not** apply. The `com.apple.security.network.client` entitlement is already present (required for HTTP calls to `127.0.0.1:11434`).

**One missing entitlement — action required in Phase A:**

- `com.apple.security.network.server` — required for `ollama serve` to bind port 11434 locally. **Add this to `Vapor.entitlements` as part of Phase A, not as a future audit item.**

No other entitlement changes are needed for the Ollama integration given the disabled sandbox.

---

## Implementation Phases

> **Note (PR #69):** Phases A and B below were superseded. Ollama is no longer bundled with the app; the bundled binary, `download-ollama.sh`, and the "Download Ollama Binary" Xcode build phase were all removed. The `.ollamaLLM` compressor type was **not** added to `CompressorType`. The current compression backends are:
> - `.localLLM` — swift-llama-cpp running a downloaded GGUF file (default)
> - `.openRouter` — cloud API
>
> Ollama (user-installed via `brew install ollama` or the official installer) is detected at runtime by `OllamaDaemonManager.isInstalled()` but is not exposed as a selectable compression backend in the current release.

### Phase A — Ollama Upgrade & Daemon ~~(1–2 days)~~ — Superseded by PR #69

- ~~Bump `OLLAMA_VERSION` in `download-ollama.sh` to 0.6.5+~~ (script removed)
- ~~**Add `com.apple.security.network.server` to `Vapor.entitlements`**~~ (no longer needed; Ollama is user-managed)
- ~~Implement `OllamaDaemonManager` (start/stop/health-check/PID file)~~ (`OllamaDaemonManager` updated to detect user-installed Ollama instead)
- ~~Wire daemon start into `VaporApp.init()` or main window `.onAppear`~~ (graceful skip if Ollama is not installed)
- [ ] Manual test: `gemma4:4b` model chat via `curl` against user-installed `ollama serve`

### Phase B — OllamaCompressor ~~(2–3 days)~~ — Deferred

> These items are on hold pending a decision on whether to add Ollama back as a user-selectable compression backend.

- [ ] Create `OllamaCompressor.swift`
- [ ] Update `CompressionService` to add Ollama path
- [ ] Add compressor type `.ollamaLLM` to `CompressorType` enum
- [ ] Update `SettingsView` to show Ollama model selector (text models only)
- [ ] Unit tests: mock HTTP responses for `/api/chat` and `/api/tags`

### Phase C — Vision Service (2–3 days)

- [ ] Create `OllamaVisionService.swift` with image-to-base64 + chat
- [ ] Support streaming response for real-time output
- [ ] Integration test: feed a test PNG, assert non-empty description returned

### Phase D — Model Management UI (3–4 days)

- [ ] `LocalModelsView` — list, pull, delete, set active model
- [ ] Progress indicator for `ollama pull` streaming
- [ ] Persist selected vision model in `CompressionSettings`

### Phase E — Distribution & End-to-End Test (1 day)

- [ ] Notarise a test build and confirm end-to-end flow works: daemon starts → model pulled → vision chat → daemon stops cleanly
- [ ] Verify no orphaned `ollama serve` processes remain after force-quit

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Ollama binary size (~80 MB) inflates app bundle | Offer as optional download (like current model download flow); don't ship in App Store build |
| Model downloads are large (3–18 GB) | Show disk-space check before pulling; allow cancellation |
| Ollama port 11434 conflicts with other local Ollama instances | Check if daemon is already running before spawning; reuse existing if healthy |
| GGUF quantisation quality varies | Document recommended quant levels; default to Q4_K_M |
| Apple Silicon only for Metal acceleration | CPU fallback works but is slow; show a warning on Intel Macs |

---

## References

- [Ollama GitHub releases](https://github.com/ollama/ollama/releases)
- [Ollama REST API docs](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [Gemma 4 on Hugging Face](https://huggingface.co/collections/google/gemma-4-release-67f8f55b4b23a5abe2cce75b)
- [llama.cpp multimodal (LLaVA)](https://github.com/ggerganov/llama.cpp/tree/master/examples/llava)
- [Qwen2.5-VL](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct)
