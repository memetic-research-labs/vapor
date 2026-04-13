# Browser Extension: Setup and Usage Guide

This guide explains how to install the **Vapor – Prompt Injector** Chrome extension and use it to automatically inject compressed prompts from Vapor into any web-based AI chat.

---

## Prerequisites

- Vapor for macOS installed and running
- Google Chrome (or any Chromium-based browser: Arc, Brave, Edge)
- macOS 13 Ventura or later

---

## Installation

### 1. Enable Browser Integration in Vapor

1. Open Vapor and click the ⚙️ Settings button.
2. In the **Browser Integration** section, check **Enable browser integration**.
3. Optionally set the **Server port** (default: `8766`). Only change this if another service is already using that port.
4. Restart Vapor if prompted.

### 2. Load the Extension in Chrome

The extension is not yet on the Chrome Web Store. Load it as an unpacked extension:

1. Open Chrome and navigate to `chrome://extensions`.
2. Enable **Developer mode** (toggle in the top-right corner).
3. Click **Load unpacked**.
4. Select the `vapor-extension/` folder from the Vapor repository (or from wherever you downloaded it).
5. The Vapor icon (⚡) appears in your Chrome toolbar.

### 3. Verify the Connection

- Click the ⚡ Vapor icon in Chrome. The popup should show **"Connected to Vapor"** with a green dot.
- In Vapor's toolbar, you should see **"🌐 Browser connected"** with a green indicator.

If the popup shows "Waiting for Vapor…", make sure Vapor is running with browser integration enabled (Step 1).

---

## Basic Usage

### Inject a Prompt (Manual)

1. Type or dictate a prompt in Vapor.
2. Press `⌘↩` to compress the prompt. It is automatically copied to your clipboard (existing behaviour).
3. Switch to your Chrome tab (ChatGPT, Claude, Gemini, etc.).
4. The compressed prompt is already in your clipboard — paste with `⌘V` as usual.

### Inject a Prompt (Automatic — Recommended)

1. Open Vapor Settings → Browser Integration.
2. Enable **Auto-send to browser after compression**.
3. Optionally enable **Auto-submit to AI** (simulates pressing Enter after injection).
4. Now press `⌘↩` in Vapor. The compressed prompt is injected directly into your active AI chat tab — no paste needed.

### Compress, Copy, and Send in One Step

Press `⌘⇧↩` to compress, copy to clipboard, **and** send to the browser — regardless of the auto-send setting. Useful when you want to override auto-send for a specific prompt.

---

## Supported AI Platforms

The extension auto-detects the prompt input on these platforms out of the box:

| Platform | URL | Notes |
|---|---|---|
| ChatGPT | chatgpt.com | Uses `#prompt-textarea` |
| Claude | claude.ai | Uses `div[contenteditable]` |
| Gemini | gemini.google.com | Uses `div[contenteditable]` |
| Perplexity | perplexity.ai | Uses `textarea` |
| Generic | any other site | Keyword-based heuristic |

For platforms not listed above, or if auto-detection picks the wrong field, use the **DOM Element Picker** (see below).

---

## DOM Element Picker

If the extension injects into the wrong field, or you are on a custom AI tool not in the list:

1. In Vapor's expanded toolbar, click **[Pick Target]** (visible when extension is connected).
2. An overlay appears on your active tab. Move the mouse — blue outlines highlight text inputs.
3. Click the input field where you want prompts injected.
4. Vapor stores this choice for the current domain. All future injections on this site use the selected field.

To change or clear a pinned target, go to Vapor Settings → Browser Integration → Pinned targets.

---

## Web Research (Scraping)

Vapor can fetch web pages directly into your prompt editor using the browser:

1. In Vapor's expanded view, click the **🔍 Research** button.
2. Enter a URL or search query.
3. Click **Fetch**. The page content (extracted as Markdown) appears in the research panel.
4. Click **Insert into prompt** to append it to your editor.

See `docs/plan-web-scraping.md` for the full design of the research feature.

---

## Troubleshooting

### Extension shows "Waiting for Vapor…"

- Make sure Vapor is running.
- Make sure **Enable browser integration** is checked in Vapor Settings.
- Check that nothing else is using port 8766: run `lsof -i :8766` in Terminal.

### Prompt lands in the wrong field

Use the **DOM Element Picker** to manually select the correct element (see above).

### Prompt is injected but the chat interface doesn't register it

Some platforms require a specific sequence of synthetic events to trigger their framework bindings. Try disabling and re-enabling the extension, then inject again. If it still fails, file an issue with the platform name and the browser console output.

### Extension disconnects frequently

Chrome's service worker is idle-terminated after ~30 seconds of inactivity. Vapor sends SSE heartbeat pings every 25 seconds to keep the connection alive. If you still see frequent disconnections, check for browser extensions that throttle background scripts.

---

## Privacy and Security

- The embedded server **only** binds `127.0.0.1` — it is never reachable from outside your Mac.
- No prompt text is sent to any third party by the extension. All communication is between Vapor and Chrome on your local machine.
- The extension uses broad `host_permissions` (`https://*/*`) to support injection, the DOM picker, and web scraping on **any** site. Chrome warns you about this at install time. The extension does not read page content except when you explicitly trigger an injection, picker, or scrape command.
- All requests to the embedded server are authenticated with a shared bearer token (generated on first connection). Without this token, other local processes or web pages cannot send or receive prompts.
- Scraped page content is cached in memory only; it is never written to disk unless you explicitly insert it into a prompt and save prompt history.
