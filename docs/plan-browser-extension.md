# Plan: Embedded NIO Server + Browser Extension (Paste-to-AI-Chat Workflow)

## Overview

This plan adds a **bidirectional browser bridge** to Vapor: an embedded SwiftNIO HTTP server running locally in the Mac app that talks to a companion Chrome extension via Server-Sent Events (SSE). The result is a seamless workflow — dictate a prompt in Vapor, compress it with `⌘↩`, and have the compressed text automatically injected into whatever AI chat tab is open in Chrome — no manual copy-paste needed.

The feature is entirely **opt-in**: the server only starts when the user enables the browser integration setting, and the extension only acts when the user has loaded it into Chrome. When disabled or disconnected the existing compress-and-copy behaviour is unchanged.

---

## User Story

> As a developer who uses AI chat interfaces constantly, I want to dictate or type a rough prompt in Vapor, press one key to compress it, and have the polished result appear instantly in my ChatGPT/Claude/Gemini tab — without switching focus or touching the mouse.

---

## Architecture

```
┌──────────────────────────────────┐     SSE (EventSource)      ┌──────────────────────────┐
│         Vapor Mac App            │ ─────────────────────────► │   Chrome Extension        │
│                                  │                             │   (background.js)         │
│  BrowserBridge (@Observable)     │     HTTP POST /api/response │                           │
│  • sendPrompt()                  │ ◄───────────────────────── │   chrome.scripting        │
│  • activatePicker()              │                             │   .executeScript          │
│  • isExtensionConnected          │                             └────────────┬──────────────┘
│                                  │                                          │
│  VaporEmbeddedServer             │                               chrome.tabs.sendMessage
│  • port 127.0.0.1:8766           │                                          │
│  • /api/stream (SSE)             │                             ┌────────────▼──────────────┐
│  • /api/response (POST)          │                             │   Content Script           │
│  • /api/status (GET)             │                             │   (prompt-injector.js)     │
└──────────────────────────────────┘                             │                           │
                                                                 │  • Find prompt input      │
                                                                 │  • Set value + events     │
                                                                 │  • Optional auto-submit   │
                                                                 └───────────────────────────┘
```

### Communication Flow

1. User dictates prompt in Vapor and presses `⌘↩` (compress & copy).
2. If `autoSendToBrowser` is enabled **and** at least one extension is connected, `BrowserBridge.sendCompressedPrompt()` is called after compression.
3. `VaporEmbeddedServer` broadcasts an SSE event on `/api/stream`:
   ```
   event: prompt
   data: {"type":"PROMPT_INJECT","text":"compressed text","autoSubmit":false}
   ```
4. The extension background service worker receives the event and calls `injectPrompt()`.
5. The background script injects `prompt-injector.js` into the active tab (idempotent).
6. The content script discovers the right `<textarea>` / `contenteditable` element using a pinned selector (if saved) or platform auto-detection, sets the value, and fires the appropriate synthetic events.
7. If `autoSubmit` is `true`, the content script simulates an Enter keypress or clicks the submit button.
8. The extension POSTs a confirmation to `/api/response`:
   ```json
   { "type": "PROMPT_INJECTED", "success": true, "platform": "ChatGPT", "tabUrl": "https://chatgpt.com/..." }
   ```
9. `BrowserBridge` receives the confirmation, updates `lastInjectionResult`, and triggers a toast.

---

## Mac App: Embedded NIO Server

### SwiftPM Dependency

Add to `Vapor.xcodeproj` (SPM integration):

```
.package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0")
```

Products required: `NIO`, `NIOHTTP1`

> The sandbox is already disabled (`com.apple.security.app-sandbox = false` in `Vapor.entitlements`), so no additional network entitlement is required to bind `127.0.0.1:8766` in the current setup. If the app is sandboxed again in the future, add `com.apple.security.network.server` at that point to allow listening on the local port.

### New Files

| File | Purpose |
|---|---|
| `Vapor/Vapor/Services/SSEHub.swift` | Thread-safe registry of active SSE writer closures; `broadcast()` fans out to all connected clients |
| `Vapor/Vapor/Services/VaporHTTPHandler.swift` | `ChannelInboundHandler` — routes GET `/api/stream`, POST `/api/response`, GET `/api/status`; CORS headers for `127.0.0.1` |
| `Vapor/Vapor/Services/VaporEmbeddedServer.swift` | `ServerBootstrap` lifecycle: `start(port:)`, `stop()`, holds the `SSEHub` singleton |
| `Vapor/Vapor/Services/BrowserBridge.swift` | `@Observable` high-level API consumed by SwiftUI views |

### SSEHub

```swift
/// Thread-safe fan-out to all connected SSE clients.
final class SSEHub: @unchecked Sendable {
    private var writers: [ObjectIdentifier: (String) -> Void] = [:]
    private let queue = DispatchQueue(label: "lol.mrl.vapor.sse-hub")

    var clientCount: Int { queue.sync { writers.count } }

    func add(_ id: ObjectIdentifier, writer: @escaping (String) -> Void) {
        queue.async { self.writers[id] = writer }
    }

    func remove(_ id: ObjectIdentifier) {
        queue.async { self.writers.removeValue(forKey: id) }
    }

    /// Serialises `json` and broadcasts an SSE frame to every connected client.
    /// `event` is the SSE event name (e.g. `"prompt"`); omit for unnamed events.
    func broadcast(event: String? = nil, json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let payload = String(data: data, encoding: .utf8) else { return }
        let frame = (event.map { "event: \($0)\n" } ?? "") + "data: \(payload)\n\n"
        queue.async { self.writers.values.forEach { $0(frame) } }
    }
}
```

### VaporHTTPHandler

Key routing logic (simplified):

```swift
// GET /api/stream — upgrade to SSE
// Sets headers: Content-Type: text/event-stream, Cache-Control: no-cache, Connection: keep-alive
// Registers a writer closure with SSEHub; deregisters on channel inactive.

// POST /api/response — extension confirmation
// Reads body JSON, calls bridge.handleExtensionResponse(_:)

// GET /api/status — health check
// Returns: { "status": "ok", "version": "1.0", "connectedClients": N }
```

CORS: respond to `OPTIONS` pre-flight by inspecting the request `Origin`. If it matches an allowlist (including `chrome-extension://<extension-id>` for the companion extension, and `http://127.0.0.1` for local dev/test pages), set `Access-Control-Allow-Origin` to that exact origin and add `Vary: Origin`; otherwise do not emit the CORS header and reject the request. Do not hard-code `Access-Control-Allow-Origin: http://127.0.0.1:8766` for extension traffic.

### BrowserBridge API

```swift
@MainActor
@Observable
final class BrowserBridge {
    var isExtensionConnected: Bool = false   // true when hub.clientCount > 0
    var connectedClientCount: Int = 0
    var lastInjectionResult: InjectionResult?
    var serverPort: Int = 8766

    private var server: VaporEmbeddedServer?

    func start() throws        // called from VaporApp scene lifecycle
    func stop()                // called on app termination / scene background

    func sendPrompt(_ text: String, autoSubmit: Bool = false)
    func sendCompressedPrompt(_ compressed: String, original: String, autoSubmit: Bool)

    func activatePicker()      // sends ACTIVATE_PICKER SSE command (see DOM Picker plan)

    func handleExtensionResponse(_ json: [String: Any])
}

struct InjectionResult {
    var success: Bool
    var platform: String
    var tabURL: String
    var timestamp: Date
}
```

### App Lifecycle Wiring (`VaporApp.swift`)

```swift
// In VaporApp.init():
@State private var browserBridge = BrowserBridge()

// In .onAppear of the main Window scene:
if preferences.browserIntegrationEnabled {
    try? browserBridge.start()
}

// In .onChange(of: scenePhase) == .background / .inactive:
browserBridge.stop()
```

Pass `browserBridge` as an `@Environment` value so `ContentView`, toolbar, and settings can observe it.

### Integration in `EditorViewModel.compressAndCopy()`

After the existing compression + clipboard logic:

```swift
// Send to browser if connected and enabled
if preferences.autoSendToBrowser,
   let bridge = browserBridge,
   bridge.isExtensionConnected {
    bridge.sendCompressedPrompt(
        compressedContent,
        original: content,
        autoSubmit: preferences.autoSubmitToAI
    )
}
```

---

## UserPreferences Changes

New stored properties (in `UserPreferences.swift`):

| Property | Type | Default | Key |
|---|---|---|---|
| `browserIntegrationEnabled` | `Bool` | `false` | `browserIntegrationEnabled` |
| `autoSendToBrowser` | `Bool` | `false` | `autoSendToBrowser` |
| `autoSubmitToAI` | `Bool` | `false` | `autoSubmitToAI` |
| `embeddedServerPort` | `Int` | `8766` | `embeddedServerPort` |

---

## Chrome Extension

### Directory Structure

```
vapor-extension/
├── manifest.json
├── background.js                      # Service worker — SSE + dispatch
├── content-scripts/
│   ├── prompt-injector.js             # DOM discovery + value injection
│   └── prompt-target-picker.js        # Visual element picker (see DOM Picker plan)
├── config/
│   └── platform-config.js             # Per-platform CSS selectors
├── popup.html                         # Connection status popup
├── popup.js
├── popup.css
└── icons/
    ├── icon16.png
    ├── icon48.png
    └── icon128.png
```

### `manifest.json`

```json
{
  "manifest_version": 3,
  "name": "Vapor – Prompt Injector",
  "version": "1.0.0",
  "description": "Injects compressed prompts from Vapor into AI chat interfaces.",
  "permissions": ["tabs", "scripting", "storage", "webRequest"],
  "host_permissions": [
    "http://127.0.0.1:8766/*",
    "https://*/*"
  ],
  "web_accessible_resources": [
    {
      "resources": [
        "content-scripts/prompt-injector.js",
        "content-scripts/prompt-target-picker.js",
        "config/platform-config.js"
      ],
      "matches": ["*://*/*"]
    }
  ],
  "action": {
    "default_popup": "popup.html",
    "default_title": "Vapor"
  },
  "background": {
    "service_worker": "background.js"
  },
  "icons": {
    "16": "icons/icon16.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png"
  }
}
```

### `background.js`

```javascript
const SERVER_URL = 'http://127.0.0.1:8766';
const RECONNECT_DELAY_MS = 2000;
const MAX_RECONNECT_DELAY_MS = 30000;

let eventSource = null;
let reconnectDelay = RECONNECT_DELAY_MS;

function connect() {
  eventSource = new EventSource(`${SERVER_URL}/api/stream`);

  eventSource.onopen = () => {
    reconnectDelay = RECONNECT_DELAY_MS;
    chrome.action.setBadgeText({ text: '●' });
    chrome.action.setBadgeBackgroundColor({ color: '#22c55e' });
    chrome.storage.local.set({ connected: true });
  };

  eventSource.addEventListener('prompt', async (e) => {
    const data = JSON.parse(e.data);
    if (data.type === 'PROMPT_INJECT') {
      await handlePromptInject(data.text, data.autoSubmit ?? false);
    } else if (data.type === 'ACTIVATE_PICKER') {
      await handleActivatePicker();
    } else if (data.type === 'SCRAPE') {
      await handleScrapeCommand(data);
    }
  });

  eventSource.onerror = () => {
    chrome.action.setBadgeText({ text: '' });
    chrome.storage.local.set({ connected: false });
    eventSource.close();
    setTimeout(connect, reconnectDelay);
    reconnectDelay = Math.min(reconnectDelay * 1.5, MAX_RECONNECT_DELAY_MS);
  };
}

async function handlePromptInject(text, autoSubmit) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return;

  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ['content-scripts/prompt-injector.js']
    });

    const result = await chrome.tabs.sendMessage(tab.id, {
      type: 'SET_PROMPT', text, autoSubmit
    });

    await postResponse({
      type: 'PROMPT_INJECTED',
      success: result?.success ?? false,
      platform: result?.platform ?? 'unknown',
      tabUrl: tab.url
    });
  } catch (err) {
    await postResponse({ type: 'PROMPT_INJECTED', success: false, error: err.message });
  }
}

function postResponse(body) {
  return fetch(`${SERVER_URL}/api/response`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  }).catch(() => {});
}

connect();
```

### `config/platform-config.js`

```javascript
const PLATFORM_CONFIGS = {
  'chatgpt.com': {
    name: 'ChatGPT',
    promptSelectors: ['#prompt-textarea', 'div[contenteditable="true"]'],
    submitMode: 'enter',
  },
  'chat.openai.com': {
    name: 'ChatGPT (legacy)',
    promptSelectors: ['#prompt-textarea', 'textarea[data-id="root"]'],
    submitMode: 'enter',
  },
  'claude.ai': {
    name: 'Claude',
    promptSelectors: ['div[contenteditable="true"]', 'textarea'],
    submitMode: 'enter',
  },
  'gemini.google.com': {
    name: 'Gemini',
    promptSelectors: ['div[contenteditable="true"]', 'textarea'],
    submitMode: 'enter',
  },
  'perplexity.ai': {
    name: 'Perplexity',
    promptSelectors: ['textarea'],
    submitMode: 'enter',
  },
  '_default': {
    name: 'Generic',
    promptKeywords: ['prompt', 'message', 'ask', 'chat', 'input'],
    submitMode: 'enter',
  }
};

// Export for use in content scripts loaded via executeScript
if (typeof module !== 'undefined') module.exports = PLATFORM_CONFIGS;
```

### `content-scripts/prompt-injector.js`

Key responsibilities:

1. **Guard against double-injection**: check `window.__vaporInjectorLoaded` and return early if already present.
2. **Resolve target element**:
   - Check `chrome.storage.local` for a pinned selector for this domain.
   - Fall back to `PLATFORM_CONFIGS` selectors for the current hostname.
   - Fall back to generic keyword-based heuristic (`textarea, input[type=text], [contenteditable]` that matches label keywords).
3. **Set value**:
   ```javascript
   // textarea / input
   const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
     window.HTMLTextAreaElement.prototype, 'value'
   ).set;
   nativeInputValueSetter.call(el, text);

   // contenteditable div
   el.innerText = text;
   ```
4. **Fire synthetic events** so React/Vue/Angular bindings update:
   ```javascript
   ['input', 'change', 'compositionend'].forEach(name => {
     el.dispatchEvent(new Event(name, { bubbles: true }));
   });
   ```
5. **Auto-submit** (if requested):
   ```javascript
   el.dispatchEvent(new KeyboardEvent('keydown', {
     key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true
   }));
   ```
6. **Return result** to background script:
   ```javascript
   chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
     if (msg.type === 'SET_PROMPT') {
       const result = injectPrompt(msg.text, msg.autoSubmit);
       reply(result);
     }
   });
   ```

### `popup.html` / `popup.js`

The popup shows:
- Connection status: green "Connected to Vapor" or grey "Waiting for Vapor…"
- Pinned target for the current domain (if any), with a "Re-pick" button
- Link to `docs/browser-extension.md` (opens GitHub page)

---

## UI Changes in Vapor

### Status Indicator

**`MinimizedPillView.swift`** — add a small dot to the right of the existing status badge:

```
● Vapor   ⚡ 1 browser connected
```

**`ToolbarView.swift`** — add a browser status row in the toolbar:

```
🌐 Browser  ●  ChatGPT connected
```

Color: green (`#22c55e`) when `bridge.connectedClientCount > 0`; grey otherwise.

### Toast Notifications

After a successful injection (via `BrowserBridge.handleExtensionResponse`):

```
✓ Sent to ChatGPT
```

On failure:

```
⚠ Injection failed (unknown platform)
```

Use the existing `ToastService` already wired into `ContentView`.

### Settings Panel (`SettingsView.swift`)

Add a new `GroupBox("Browser Integration")` section:

```
☑ Enable browser integration
  Start the embedded server on launch and allow the Chrome
  extension to connect.

☐ Auto-send to browser after compression
  After ⌘↩, automatically inject the compressed prompt into
  the active AI chat tab.

☐ Auto-submit to AI
  Simulate Enter/click after injecting (requires auto-send).

Server port: [8766]
  Change if another service is already using this port.
  Requires app restart.
```

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘↩` | Compress & copy (existing) — also sends to browser if auto-send is on |
| `⌘⇧↩` | Compress, copy, **and** send to browser (always, regardless of auto-send setting) |

Add `⌘⇧↩` to:
- `KeyboardShortcutsHelpView.swift` help list
- `VaporApp.swift` `CommandMenu("Actions")` group
- `NotificationCenter` post: `.vaporCompressCopyAndSend`

---

## Implementation Phases

### Phase 1 — Embedded Server (Mac App)

- [ ] Add `swift-nio` SPM dependency to `Vapor.xcodeproj`
- [ ] Add `com.apple.security.network.server` to `Vapor.entitlements`
- [ ] Create `SSEHub.swift`
- [ ] Create `VaporHTTPHandler.swift` with SSE, POST, status, and CORS
- [ ] Create `VaporEmbeddedServer.swift` (ServerBootstrap lifecycle)
- [ ] Create `BrowserBridge.swift` (`@Observable`, starts/stops server)
- [ ] Add new preferences to `UserPreferences.swift`
- [ ] Start/stop bridge in `VaporApp.swift` scene lifecycle
- [ ] Wire `compressAndCopy` → `BrowserBridge.sendCompressedPrompt` in `EditorViewModel`
- [ ] Manual test: `curl -N http://127.0.0.1:8766/api/stream` receives SSE after compression

### Phase 2 — Chrome Extension

- [ ] Create `vapor-extension/` directory
- [ ] `manifest.json`
- [ ] `config/platform-config.js`
- [ ] `background.js` (SSE, reconnect, inject dispatch, POST back)
- [ ] `content-scripts/prompt-injector.js` (DOM discovery, value set, events)
- [ ] `popup.html` + `popup.js` + `popup.css`
- [ ] Extension icons (export from Vapor app icon assets)
- [ ] Manual test: load extension, open ChatGPT, trigger compression in Vapor, confirm text appears

### Phase 3 — DOM Picker

See `docs/plan-dom-picker.md`.

### Phase 4 — Web Scraping

See `docs/plan-web-scraping.md`.

### Phase 5 — Polish

- [ ] Toast notifications wired to `ToastService`
- [ ] `⌘⇧↩` shortcut end-to-end
- [ ] Status indicators in pill and toolbar
- [ ] Settings panel section
- [ ] Error handling: port conflict dialog, extension not installed helper
- [ ] Reconnection visual feedback
- [ ] Documentation: `docs/browser-extension.md` (setup guide, installation steps)

---

## Files to Create

| File | Purpose |
|---|---|
| `Vapor/Vapor/Services/SSEHub.swift` | SSE connection fan-out |
| `Vapor/Vapor/Services/VaporHTTPHandler.swift` | NIO HTTP routing |
| `Vapor/Vapor/Services/VaporEmbeddedServer.swift` | Server lifecycle |
| `Vapor/Vapor/Services/BrowserBridge.swift` | Observable bridge for SwiftUI |
| `vapor-extension/manifest.json` | Chrome Manifest V3 |
| `vapor-extension/background.js` | Service worker |
| `vapor-extension/content-scripts/prompt-injector.js` | DOM injection |
| `vapor-extension/content-scripts/prompt-target-picker.js` | Visual element picker |
| `vapor-extension/config/platform-config.js` | AI platform selectors |
| `vapor-extension/popup.html` | Status popup |
| `vapor-extension/popup.js` | Popup logic |
| `vapor-extension/popup.css` | Popup styles |
| `docs/browser-extension.md` | End-user setup guide |

## Files to Modify

| File | Change |
|---|---|
| `Vapor.xcodeproj/project.pbxproj` | Add swift-nio SPM dependency |
| `Vapor/Vapor/VaporApp.swift` | Start/stop `BrowserBridge` on lifecycle events |
| `Vapor/Vapor/ViewModels/EditorViewModel.swift` | Call `BrowserBridge.sendCompressedPrompt` after compression |
| `Vapor/Vapor/Models/UserPreferences.swift` | Add 4 new browser prefs |
| `Vapor/Vapor/Views/SettingsView.swift` | Add Browser Integration `GroupBox` |
| `Vapor/Vapor/Views/MinimizedPillView.swift` | Show browser connection dot |
| `Vapor/Vapor/Views/ToolbarView.swift` | Show browser status row |
| `Vapor/Vapor/Views/KeyboardShortcutsHelpView.swift` | Add `⌘⇧↩` row |
| `Vapor/Vapor/ContentView.swift` | Pass `browserBridge` to sub-views |
| `Vapor/Vapor/Vapor.entitlements` | Add `com.apple.security.network.server` |

---

## Acceptance Criteria

- [ ] Embedded NIO server starts on app launch when integration is enabled; binds to `127.0.0.1:8766`
- [ ] Server stops cleanly on app termination or scene background transition
- [ ] `/api/stream` emits SSE heartbeat every 25 s to keep the connection alive ahead of the service worker's 30 s idle eviction timeout
- [ ] Chrome extension connects via SSE and badge turns green
- [ ] Extension reconnects automatically with exponential back-off after server restart
- [ ] `⌘↩` sends to browser when auto-send is enabled and extension is connected
- [ ] `⌘⇧↩` always sends to browser regardless of auto-send setting
- [ ] Content script injects into ChatGPT, Claude, Gemini, Perplexity (textarea and contenteditable)
- [ ] React/Vue/Angular bindings update (native setter + synthetic events)
- [ ] Auto-submit option fires Enter keypress after injection
- [ ] Toast confirms success/failure with platform name
- [ ] Extension popup shows connected status and pinned target
- [ ] Settings section allows enabling/disabling integration, auto-send, auto-submit, port
- [ ] Port conflict: clear error message and option to change port without restart (or prompt restart)
- [ ] No network traffic leaves localhost; extension `host_permissions` scoped to `127.0.0.1:8766` for the server and `https://*/*` for content injection/scraping (Chrome warns users at install time for broad permissions)

---

## Security Notes

Related follow-on architecture:

- For site-aware structured extraction workflows such as Amazon review corpora, see [`docs/plan-browser-research-adapters.md`](plan-browser-research-adapters.md).

- The server **only** binds `127.0.0.1` — never `0.0.0.0`. Remote access is impossible by design.
- The localhost bridge uses **explicit client authentication**: on first setup, the Mac app generates a random secret stored in `UserDefaults`, and the extension saves it in `chrome.storage.local`. Both `GET /api/stream` and `POST /api/response` must present this secret via `Authorization: Bearer <token>`. CORS is used as a browser-side hardening measure after the server validates the shared secret.
- CORS headers are set by reflecting the request `Origin` when it matches the known extension origin (`chrome-extension://<id>`) or `http://127.0.0.1`; `Vary: Origin` is included. Arbitrary web pages cannot connect because they lack the bearer token.
- Content scripts can be injected into **any HTTPS site** because the extension uses broad `host_permissions` (`https://*/*`). This is required for the scraping use case (see `docs/plan-web-scraping.md`) and for the DOM picker to work on custom/enterprise AI tools. Chrome warns users about broad permissions at install time; the extension does not access arbitrary page data except when the user explicitly triggers an injection, picker, or scrape command.
