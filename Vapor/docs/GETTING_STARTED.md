# Vapor — Getting Started

## Quick Start

Vapor requires macOS 14 (Sonoma) or later. You need at least one compression backend configured to compress prompts.

1. Download a local model or set up an OpenRouter API key
2. Launch Vapor
3. Grant microphone and speech recognition permissions when prompted
4. Hold the **Fn** key and speak your prompt
5. Release Fn — press **Cmd+Return** to compress & copy
6. Paste into any AI chat interface

## Compression Backends

Vapor supports two compression backends. Pick one in **Settings > Compression**.

| Backend | Setup | Cost | Quality | Speed |
|---------|-------|------|----------|-------|
| **Local LLM** | One-click download (1.5–4.7 GB) | Free | Best | Medium |
| **OpenRouter** | Paste API key from openrouter.ai | ~$0.01/1M tokens | Excellent | Fast |

### Local LLM

The best on-device compression quality. Uses [swift-llama-cpp](https://github.com/pgorzelany/swift-llama-cpp) to run a 4-bit quantized GGUF model entirely in-process.

**Setup:**
1. Go to **Settings > Compression**
2. Select **Local LLM (On-Device)**
3. Choose a model from the picker (Phi-4 Mini recommended)
4. Click **Download**
5. Wait for the download to complete
6. The model auto-loads on next launch

**Available models:**

| Model | Size | RAM | Best For |
|-------|------|-----|----------|
| Phi-4 Mini (3.8B) | 2.3 GB | ~3 GB | Best balance of speed and quality |
| Qwen 3 4B | 2.4 GB | ~4 GB | Good quality, compact |
| Qwen 2.5 7B | 4.7 GB | ~6 GB | Highest quality on-device |

**Requirements:** Metal GPU, disk space for the model. Works on any Apple Silicon Mac. Models are stored at `~/Library/Application Support/Vapor/Models/`.

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
- Choose between OpenRouter or macOS NLTagger as the backend
- Entities are linked to source context items and searchable in Context Explorer

### Summarization

Captured web pages and documents can be automatically summarized.

- Configure in **Settings > Context Processing**
- Requires either an **OpenRouter API key** or a **downloaded Local LLM model**
- Summaries appear in the Context Explorer detail view

## Choosing a Backend by Mac Specs

| Mac | RAM | Recommended Backend |
|-----|-----|-------------------|
| MacBook Air M1/M2/M3 | 8 GB | Local LLM (Phi-4 Mini) |
| MacBook Pro M1/M2/M3 | 16 GB | Local LLM (Qwen 2.5 7B) |
| MacBook Pro M3/M4 Max | 32+ GB | Local LLM (Qwen 2.5 7B) |
| Mac mini M4 | 16 GB | Local LLM (Qwen 2.5 7B) |
| Intel Mac | 16+ GB | OpenRouter (GPU required for local models) |

## Support

Questions or issues? Contact [support@app-dist.com](mailto:support@app-dist.com)
