# Settings

Open Settings with `⌘ ,` or click the gear icon in the expanded toolbar.

**Screenshot needed:** `screens/settings-full.png` — the full Settings panel showing all sections.

## Compression Backend

Choose which AI model compresses your prompts. The selected backend is used whenever you press `⌘ ↩`.

### Apple Foundation Models

- **Default selection** — works immediately with no setup
- Requires macOS 26+ with Apple Intelligence enabled
- Uses Apple's on-device ~3B parameter model
- Good quality for most prompts
- Free, no download, no API key

### Local LLM (On-Device) — Recommended

- **Best compression quality** — follows PC compression rules more accurately
- Uses Qwen2.5-7B-Instruct (Q4_K_M quantization)
- Requires a one-time ~4.7 GB download
- Runs locally with Metal GPU acceleration on Apple Silicon
- Free after download

When you select Local LLM, the configuration panel shows:

- **Model status** — "Model ready" (green checkmark) or "Model not downloaded" (orange arrow)
- **Download button** — downloads the model to `~/Library/Application Support/lol.mrl.app.Vapor/models/`
- **Re-download button** — deletes and re-downloads (useful when a new model version is available)
- **Delete button** — removes the model from disk to free space
- **Progress bar** — shown during download with percentage and bytes

**Screenshot needed:** `screens/settings-local-llm-download.png` — the Settings panel with Local LLM selected showing the download progress bar.

**Screenshot needed:** `screens/settings-local-llm-ready.png` — the Settings panel with Local LLM selected showing "Model ready" with re-download and delete buttons.

### OpenRouter (Cloud API)

- Uses a cloud-hosted model via the OpenRouter API
- Requires an API key from [openrouter.ai](https://openrouter.ai)
- Costs ~$0.01 per 1M tokens
- Quality depends on the selected model

When you select OpenRouter, the configuration panel shows:

- **API Key** — secure field for your OpenRouter API key
- **Model** — text field for the model name (default: `glm-5`)

## Power User

### Auto-compress when dictation ends

When enabled, Vapor automatically compresses and copies to clipboard as soon as you release the Fn key. This skips the manual `⌘ ↩` step.

**Default:** Off

### Auto-copy original when dictation ends

When enabled, Vapor automatically copies the full uncompressed dictated text to the clipboard as soon as you release the Fn key — without running compression. Useful when you just want the raw prompt on the clipboard immediately.

> Enabling **Auto-compress when dictation ends** automatically turns this off, since both auto-actions would conflict.

**Default:** On

### Auto-minimize after compress & copy

When enabled, Vapor collapses to the compact pill view immediately after compressing and copying. This gets the window out of your way so you can paste immediately.

**Default:** Off

### Show experiments button in toolbar

When enabled, shows the flask icon in the expanded toolbar. Clicking it opens the OpenRouter test sidebar for testing compression with different cloud models.

**Default:** Off — this is for power users who want to experiment with different backends.

## Global Hotkey

Customize the keyboard shortcut that focuses Vapor from any app.

- **Default:** `⌃ ⌥ Space` (Control + Option + Space)
- Click the recorder field and press your desired key combination to change it
- The shortcut works globally — from any app, any Space, any fullscreen context

> When you first set a hotkey, macOS may ask for **Input Monitoring** permission. Grant it in System Settings > Privacy & Security > Input Monitoring to enable the global shortcut.

**Screenshot needed:** `screens/settings-global-hotkey.png` — the Settings panel showing the Global Hotkey section with the key recorder.

## Save & Cancel

- **Save** — applies all changes and closes Settings
- **Cancel** — discards changes and closes Settings

Settings are persisted in UserDefaults and survive app restarts.
