# Vapor — Getting Started

## Quick Start

Vapor works out of the box on macOS 26+ with Apple Intelligence. No downloads or API keys required.

1. Launch Vapor
2. Grant microphone and speech recognition permissions when prompted
3. Hold the **Fn** key and speak your prompt
4. Release Fn — press **Cmd+Return** to compress & copy
5. Paste into any AI chat interface

That's it. Apple's on-device Foundation Models handle compression automatically.

## Compression Backends

Vapor supports five compression backends. Pick one in **Settings > Compression**.

| Backend | Setup | Cost | Quality | Speed |
|---------|-------|------|----------|-------|
| **Apple Foundation Models** | None — built into macOS 26+ | Free | Good | Fast |
| **Local LLM (Qwen 2.5-7B)** | One-click download (~4.7 GB) | Free | Best | Medium |
| **Ollama** | Pull models from UI | Free | Varies by model | Varies |
| **OpenRouter** | Paste API key from openrouter.ai | ~$0.01/1M tokens | Excellent | Fast |
| **Rule-Based** | None | Free | Lower | Instant |

### Apple Foundation Models (Default)

Zero configuration. Uses Apple's on-device LLM via the `FoundationModels` framework. Available on any Mac with Apple Intelligence (macOS 26+).

### Local LLM — Qwen 2.5-7B

The best on-device compression quality. Uses [swift-llama-cpp](https://github.com/pgorzelany/swift-llama-cpp) to run a 4-bit quantized GGUF model entirely in-process.

**Setup:**
1. Go to **Settings > Compression**
2. Select **Local LLM (On-Device)**
3. Click **Download Qwen 2.5-7B (4.7 GB)**
4. Wait for the download to complete
5. The model auto-loads on next launch

**Requirements:** Metal GPU, ~5 GB disk space. Works on any Apple Silicon Mac. The model file is stored at `~/Library/Application Support/Vapor/Models/Qwen2.5-7B-Instruct-Q4_K_M.gguf`.

### Ollama

Vapor bundles the Ollama binary and manages it automatically. You can also use a system-installed Ollama if you prefer.

**Using the bundled Ollama:**
1. Go to **Settings > Ollama Models**
2. Click **Pull** on any recommended model
3. Wait for the download to complete
4. Click **Select** to make it active

**Using system-installed Ollama:**
1. Install Ollama from [ollama.com](https://ollama.com) or `brew install ollama`
2. Pull models: `ollama pull gemma4:e4b`
3. Vapor auto-detects Ollama running on `localhost:11434`

**Recommended models:**

| Model | Size | RAM | Best For |
|-------|------|-----|----------|
| `gemma4:e4b` | 3.2 GB | ~5 GB | Best balance of speed and quality |
| `gemma4:e2b` | 1.8 GB | ~3 GB | Fastest, good for low-RAM Macs |
| `qwen3:8b` | 5.2 GB | ~7 GB | High quality text compression |
| `phi4:mini` | 1.5 GB | ~2 GB | Lightweight, minimal resource usage |
| `qwen2.5:7b` | 4.7 GB | ~6 GB | Proven quality, same as Local LLM |

### OpenRouter (Cloud)

Access to hundreds of cloud models including the latest from OpenAI, Anthropic, Google, Meta, and more.

**Setup:**
1. Get an API key from [openrouter.ai](https://openrouter.ai)
2. Go to **Settings > Cloud**
3. Paste your API key
4. Click **Refresh Catalog** to see available models
5. Go to **Settings > Compression** and select **OpenRouter**
6. Pick a model from the dropdown

The default model is `glm-5` (cheap and fast). You can choose any model with 8,000+ token context.

### Rule-Based (Fallback)

Always available. No ML — uses linguistic heuristics to strip articles, prepositions, and auxiliary verbs. Lower quality but instant and never fails. Vapor automatically falls back to this if the selected backend is unavailable.

## Keyboard Shortcuts

### Dictation

| Shortcut | Action |
|----------|--------|
| **Fn** (hold) | Start dictating |
| **Fn** (release) | Stop dictating, commit text |

### Compression & Editing

| Shortcut | Action |
|----------|--------|
| **Cmd+Return** | Compress & copy |
| **Cmd+Shift+C** | Copy original (uncompressed) |
| **Cmd+K** | Copy & clear |
| **Cmd+V** | Paste |

### Window Management

| Shortcut | Action |
|----------|--------|
| **Ctrl+Opt+Space** | Focus Vapor from any app |
| **Cmd+\\** | Toggle compact / full view |
| **Escape** | Minimize to compact pill |

### Focus Panels

| Shortcut | Action |
|----------|--------|
| **Cmd+Shift+S** | Focus screenshot shelf |
| **Cmd+Option+C** | Focus context tray |
| **Cmd+Shift+T** | Focus tool rail |
| **Cmd+Shift+I** | Focus editor |

### Windows & Tools

| Shortcut | Action |
|----------|--------|
| **Cmd+Y** | Prompt history |
| **Cmd+Shift+E** | Context explorer |
| **Cmd+Shift+L** | Activity log |
| **Cmd+/** | Keyboard shortcuts help |

## Browser Extension

Vapor includes a Chrome extension that lets you inject compressed prompts directly into AI chat interfaces.

**Setup:**
1. Open the DMG and navigate to the **Browser Extension** folder
2. Open Chrome and go to `chrome://extensions/`
3. Enable **Developer mode** (top-right toggle)
4. Click **Load unpacked** and select the `Browser Extension` folder
5. In Vapor's **Settings > Browser**, enable browser integration

**How it works:** The extension communicates with Vapor on `localhost:8766`. When you compress a prompt, you can send it directly to a browser tab with **Cmd+Shift+P**.

## Advanced Features

### Screenshot Shelf

Vapor automatically detects screenshots on your Desktop. They appear in the screenshot shelf panel where you can add them to your prompt context.

- Screenshots are scanned every 10 seconds from `~/Desktop/`
- Navigate with arrow keys or `Cmd+Shift+S` to focus the shelf
- Select a screenshot and press **Enter** to add it to the current context

### Context Explorer

A searchable index of everything Vapor has captured — web pages, screenshots, entities, and more.

- Opens with **Cmd+Shift+E**
- Full-text search powered by MiniLM embeddings (384-dimensional vectors)
- Click any item to view details, copy, or send to the editor

### Entity Extraction

Vapor can automatically extract named entities (people, organizations, products, locations) from captured text.

- Configure in **Settings > Context Processing**
- Choose between Ollama, OpenRouter, or macOS NLTagger as the backend
- Entities are linked to source context items and searchable in Context Explorer

### Summarization

Captured web pages and documents can be automatically summarized.

- Configure in **Settings > Context Processing**
- Choose between Ollama, OpenRouter, or Foundation Models as the backend
- Summaries appear in the Context Explorer detail view

## Choosing a Backend by Mac Specs

| Mac | RAM | Recommended Backend |
|-----|-----|-------------------|
| MacBook Air M1/M2/M3 | 8 GB | Foundation Models or `phi4:mini` |
| MacBook Pro M1/M2/M3 | 16 GB | Local LLM (Qwen 2.5-7B) or `gemma4:e4b` |
| MacBook Pro M3/M4 Max | 32+ GB | Local LLM or `gemma4:26b` |
| Mac mini M4 | 16 GB | Local LLM or `gemma4:e4b` |
| Intel Mac | 16+ GB | OpenRouter (GPU required for local models) |

## Support

Questions or issues? Contact [support@app-dist.com](mailto:support@app-dist.com)
