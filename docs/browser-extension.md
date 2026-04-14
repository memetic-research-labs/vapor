# Browser Extension: Setup and Usage Guide

The Vapor Chrome extension sends compressed prompts from the Vapor Mac app directly into AI chat tabs — no copy-paste needed.

---

## Prerequisites

- Vapor for macOS running
- Google Chrome
- macOS 13 Ventura or later

---

## Install the Extension

The extension is not on the Chrome Web Store. Load it as an unpacked extension:

1. Open Chrome and navigate to `chrome://extensions`.
2. Enable **Developer mode** (toggle in the top-right corner).
3. Click **Load unpacked**.
4. Select the `vapor-extension/` folder from the Vapor repository.
5. The Vapor icon appears in your Chrome toolbar.

---

## Enable Browser Integration in Vapor

1. Open Vapor Settings (**⌘,** or the gear icon).
2. Go to the **Browser** tab.
3. Check **Enable browser integration**.
4. Note the **Auth Token** shown in the settings — you'll need this in the next step.
5. The embedded server starts on port `8766` by default. Only change this if another service is using that port.

---

## Copy the Auth Token to the Extension

The extension authenticates to Vapor's local server using a shared token.

1. In Vapor Settings > Browser, click the copy button next to the auth token.
2. Click the Vapor icon in your Chrome toolbar to open the extension popup.
3. Paste the token into the input field.
4. Click **Save**.
5. The token field should now show "Token saved" and be disabled.

---

## Verify the Connection

### In Vapor

- **Pulsing orange** `safari` icon — server is running, waiting for the extension to connect.
- **Solid blue** `safari` icon — extension is connected and ready.
- **No icon** — browser integration is not enabled in Settings.

### In the Extension

- Click the Vapor icon in Chrome. The popup should show **"Connected to Vapor"**.
- If the popup shows "No connection", check that Vapor is running and the token matches.

### After Closing Vapor

- The extension detects the disconnection and shows a red `!` badge.
- When you relaunch Vapor, the extension reconnects automatically (up to 8 seconds).

---

## Send a Prompt to the Browser

### Expanded Window

1. Type or dictate a prompt in the editor.
2. Optionally press `⌘↩` to compress it first.
3. Click the **blue safari** icon in the toolbar.

### Pill View

1. Type or dictate a prompt.
2. Click the **blue safari** icon in the controls bar (visible when the extension is connected).

### Keyboard Shortcut

Press `⌘⇧↩` to send to the browser immediately. This works in both the expanded window and the pill view.

### What Gets Sent

- If you have compressed text, the **compressed** version is sent.
- If no compression has been done, the **raw editor text** is sent.
- The text is injected into the active tab's prompt input field.

### Auto-Submit

Enable **Auto-submit to AI** in Vapor Settings > Browser to have the extension simulate pressing Enter after injection. This works on most sites but may not work on all.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘↩` | Compress & copy to clipboard |
| `⌘⇧↩` | Send to browser |
| `⌘⇧C` | Copy original text to clipboard |
| `⌘K` | Copy original & clear |

---

## Supported Sites

The extension detects prompt inputs on these platforms:

| Platform | URL | Input Type |
|----------|-----|------------|
| ChatGPT | chatgpt.com | textarea |
| Claude | claude.ai | contenteditable div |
| Gemini | gemini.google.com | contenteditable div |
| Perplexity | perplexity.ai | textarea |
| Grok | grok.com, x.com | textarea |
| Generic | any site | keyword-based heuristic fallback |

Some sites may update their DOM and break detection. If injection doesn't work on a site, check the browser console for errors.

---

## Current Limitations

- **Active tab only** — the extension sends to the currently focused tab. There is no tab picker yet.
- **Single input** — the extension picks the first matching input on the page. There is no DOM picker to choose a specific element.
- **No scraping** — the extension cannot fetch or extract web page content yet.
- **Synthetic events** — some sites with custom input handling may not register the injected text.

---

## Troubleshooting

### Extension shows "No connection"

- Make sure Vapor is running.
- Make sure browser integration is enabled in Settings > Browser.
- Verify the token in the extension popup matches the one in Vapor Settings.
- Check that nothing else is using port 8766: run `lsof -i :8766` in Terminal.

### Prompt does not appear in the input field

- Make sure the tab has a visible text input or contenteditable area.
- Some sites use shadow DOM or custom editors that the heuristic cannot detect.
- Check the extension service worker console (right-click extension icon > "Inspect service worker") for errors.

### Vapor shows port conflict alert

- Another process is using port 8766.
- Either quit the conflicting process or change the port in Settings > Browser.
- After changing the port, you may need to update the extension's server URL (currently hardcoded to `127.0.0.1:8766` in `background.js`).

### Extension badge stays red after relaunching Vapor

- Wait up to 8 seconds for the reconnection backoff.
- If it doesn't reconnect, go to `chrome://extensions` and click the refresh button on the Vapor extension.

### Debug Logs

- **Extension**: right-click the Vapor icon in Chrome > "Inspect service worker" > Console tab.
- **Vapor**: check the Xcode console for `[BrowserBridge]` log messages.

---

## Privacy and Security

- The embedded server binds **localhost only** (`127.0.0.1`). It is never reachable from outside your Mac.
- All communication between Vapor and Chrome stays on your local machine. No data is sent to any third-party server.
- The extension uses a shared bearer token for authentication. Without this token, other local processes or web pages cannot send or receive prompts.
- The extension requests broad `https://*/*` host permissions. This is required for prompt injection across any site and for future browser-powered context capture features. Chrome warns you about this at install time. The extension does not read page content except when you explicitly trigger an injection.
- The extension is vanilla JavaScript with no npm dependencies and no build step.

---

## Planned Follow-Ups

- **Tab picker** — fetch and select a specific tab from within Vapor instead of targeting only the active tab. See issue [#33](https://github.com/memetic-research-labs/comp-tok-stt/issues/33).
- **Dynamic input discovery** — replace hardcoded platform selectors with a visual DOM picker and server-side selector storage. See issue [#32](https://github.com/memetic-research-labs/comp-tok-stt/issues/32) and [`docs/plan-dom-picker.md`](plan-dom-picker.md).
- **Web scraping** — use the browser as a research agent to fetch and extract page content into Vapor. See [`docs/plan-web-scraping.md`](plan-web-scraping.md).
- **Context management** — broader bidirectional channel for structured context capture, glossaries, and prompt composition. See the context management design docs (currently under review).
