# Plan: DOM Element Picker Overlay

## Overview

The **DOM Element Picker** lets a user visually click on any input field in a web page to designate it as the injection target for Vapor prompts. This solves the primary failure mode of selector-based auto-detection: AI chat platforms frequently change their DOM structure, and the user may want to inject prompts into a non-standard or custom interface.

The picker is a Chrome content script that overlays the current tab with a hover-highlight UI. The user clicks any `<textarea>`, `<input>`, or `contenteditable` element; the script derives a stable CSS selector for that element and reports it back to Vapor via the embedded server. Vapor stores the selector per-domain ("pinned target") and uses it for all future injections on that site.

---

## User Story

> As a developer on a custom or enterprise AI tool that Vapor doesn't recognise automatically, I want to click "Pick Target" once, click on the chat input on screen, and have Vapor remember that element forever — so that future injections always land in the right place.

---

## Feature Concept

```
┌──────────────────────────────────────────────────────────────────┐
│  ⚡ Vapor — Pick Prompt Target                      [ESC] Cancel │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Click on the input field where you want Vapor to inject         │
│  compressed prompts. Only text inputs are highlighted.           │
│                                                                  │
│   ╔══════════════════════════════════════════╗  ← blue outline  │
│   ║  Ask me anything...                      ║    follows mouse  │
│   ╚══════════════════════════════════════════╝                   │
│        ↑ tooltip: "textarea · 620×52 · Click to select"         │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Architecture

```
Vapor App                         Chrome Extension             Active Tab
    │                                  │                           │
    │  SSE: ACTIVATE_PICKER            │                           │
    │ ─────────────────────────────►  │                           │
    │                                  │  executeScript:           │
    │                                  │  prompt-target-picker.js  │
    │                                  │ ─────────────────────────►│
    │                                  │                           │  overlay appears
    │                                  │                           │  user clicks element
    │                                  │  sendMessage: TARGET_CLICK│
    │                                  │ ◄─────────────────────── │
    │  POST /api/response              │                           │
    │  { type: TARGET_SELECTED, … }    │                           │
    │ ◄──────────────────────────────  │                           │
    │                                  │                           │
    │  store pinnedTarget[domain]      │                           │
```

---

## Triggering the Picker

### From Vapor

A new **"Pick Target"** button appears in the expanded toolbar when `browserBridge.isExtensionConnected` is true. There is also a keyboard shortcut `⌘⌥P` ("Pick target").

Pressing the button calls `BrowserBridge.activatePicker()`, which broadcasts:

```
event: prompt
data: { "type": "ACTIVATE_PICKER" }
```

### From the Extension Popup

A secondary "Pick target for this page" button in `popup.html` sends the same command by calling `chrome.runtime.sendMessage({ type: 'ACTIVATE_PICKER_LOCAL' })` to the background script, which then injects the picker directly.

---

## Picker Content Script: `prompt-target-picker.js`

### Activation Guard

```javascript
if (window.__vaporPickerActive) return;
window.__vaporPickerActive = true;
```

### Overlay Structure

The script injects a `<div id="vapor-picker-overlay">` containing:

| Element | Role |
|---|---|
| `#vapor-picker-bar` | Fixed top bar with logo, instructions, Cancel button |
| `#vapor-picker-highlight` | Absolute-positioned transparent box that tracks the hovered element |
| `#vapor-picker-tooltip` | Small label below the highlight showing element info |

All styles are injected via `<style id="vapor-picker-styles">` in the same script (no separate CSS fetch needed) to keep the script self-contained and avoid CSP issues with `chrome.runtime.getURL`.

### Eligible Elements

```javascript
const ELIGIBLE_SELECTORS = [
  'textarea',
  'input[type="text"]',
  'input:not([type])',
  '[contenteditable="true"]',
  '[contenteditable=""]',
  '[role="textbox"]',
];
```

Non-eligible elements (buttons, images, divs without contenteditable, etc.) show no highlight and are unclickable through the overlay.

### Hover Highlight

```javascript
document.addEventListener('mousemove', onMouseMove, true);

function onMouseMove(e) {
  const el = document.elementFromPoint(e.clientX, e.clientY);
  const target = el?.closest(ELIGIBLE_SELECTORS.join(','));
  if (!target) { hideHighlight(); return; }

  const rect = target.getBoundingClientRect();
  const scrollX = window.scrollX, scrollY = window.scrollY;

  highlight.style.cssText = `
    position: absolute;
    left:   ${rect.left   + scrollX - 3}px;
    top:    ${rect.top    + scrollY - 3}px;
    width:  ${rect.width  + 6}px;
    height: ${rect.height + 6}px;
    border: 2.5px solid #3b82f6;
    border-radius: 4px;
    pointer-events: none;
    z-index: 2147483646;
    transition: all 60ms ease;
  `;

  tooltip.textContent =
    `${target.tagName.toLowerCase()} · ${Math.round(rect.width)}×${Math.round(rect.height)} · Click to select`;
  tooltip.style.top  = `${rect.bottom + scrollY + 6}px`;
  tooltip.style.left = `${rect.left   + scrollX}px`;

  currentTarget = target;
}
```

### Click to Select

```javascript
document.addEventListener('click', onPickerClick, true);

function onPickerClick(e) {
  e.preventDefault(); e.stopPropagation();
  if (!currentTarget) return;
  const selector = buildSelector(currentTarget);
  deactivatePicker();
  chrome.runtime.sendMessage({
    type: 'TARGET_CLICK',
    selector,
    elementTag: currentTarget.tagName.toLowerCase(),
    domain: location.hostname
  });
}
```

### Building a Durable Selector

Priority (most to least stable):

1. `#id` — if the element has a unique `id`
2. `[data-testid="…"]` or `[data-id="…"]` — test/semantic attributes
3. `[name="…"]` — form field name
4. CSS path: walk up the DOM tree constructing `tag:nth-of-type(n)` segments until a unique path is found
5. Full XPath as a fallback

```javascript
function isUniqueSelector(selector) {
  try {
    return document.querySelectorAll(selector).length === 1;
  } catch {
    return false;
  }
}

function buildXPath(el) {
  const parts = [];
  let node = el;

  while (node && node.nodeType === Node.ELEMENT_NODE) {
    const tag = node.tagName.toLowerCase();
    const siblings = Array.from(node.parentElement?.children ?? []).filter(
      c => c.tagName === node.tagName
    );
    const idx = siblings.indexOf(node) + 1;
    parts.unshift(siblings.length > 1 ? `${tag}[${idx}]` : tag);
    node = node.parentElement;
  }

  return `/${parts.join('/')}`;
}

function buildSelector(el) {
  if (el.id) {
    const candidate = `#${CSS.escape(el.id)}`;
    if (isUniqueSelector(candidate)) return candidate;
  }

  for (const attr of ['data-testid', 'data-id', 'aria-label', 'name', 'placeholder']) {
    const val = el.getAttribute(attr);
    if (val) {
      const candidate = `${el.tagName.toLowerCase()}[${attr}="${CSS.escape(val)}"]`;
      if (isUniqueSelector(candidate)) return candidate;
    }
  }

  // CSS path walk: return the first unique path we can build
  const parts = [];
  let node = el;
  while (node && node.nodeType === Node.ELEMENT_NODE && node !== document.documentElement) {
    const tag = node.tagName.toLowerCase();
    const siblings = Array.from(node.parentElement?.children ?? []).filter(
      c => c.tagName === node.tagName
    );
    const idx = siblings.indexOf(node) + 1;
    parts.unshift(siblings.length > 1 ? `${tag}:nth-of-type(${idx})` : tag);

    const candidate = parts.join(' > ');
    if (isUniqueSelector(candidate)) return candidate;

    node = node.parentElement;
  }

  // Final fallback when no unique CSS selector is available
  return buildXPath(el);
}
```

### Keyboard Handling

- `Escape` — deactivate picker, send `PICKER_CANCELLED` message
- No other keys pass through while picker is active

### Deactivation

```javascript
function deactivatePicker() {
  document.removeEventListener('mousemove', onMouseMove, true);
  document.removeEventListener('click', onPickerClick, true);
  document.removeEventListener('keydown', onKeyDown, true);
  overlay.remove();
  window.__vaporPickerActive = false;
}
```

---

## Extension Background Script Changes (`background.js`)

```javascript
// Receive ACTIVATE_PICKER from Vapor SSE stream
} else if (data.type === 'ACTIVATE_PICKER') {
  await handleActivatePicker();
}

async function handleActivatePicker() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) return;
  await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    files: ['content-scripts/prompt-target-picker.js']
  });
}

// Receive TARGET_CLICK from the picker content script
chrome.runtime.onMessage.addListener(async (msg) => {
  if (msg.type === 'TARGET_CLICK') {
    // Persist the pinned target
    const stored = await chrome.storage.local.get('pinnedTargets') ?? {};
    const targets = stored.pinnedTargets ?? {};
    targets[msg.domain] = {
      selector: msg.selector,
      elementTag: msg.elementTag,
      pinnedAt: Date.now(),
    };
    await chrome.storage.local.set({ pinnedTargets: targets });

    // Notify Vapor
    await postResponse({
      type: 'TARGET_SELECTED',
      domain: msg.domain,
      selector: msg.selector,
      elementTag: msg.elementTag,
    });
  } else if (msg.type === 'PICKER_CANCELLED') {
    await postResponse({ type: 'PICKER_CANCELLED', domain: msg.domain });
  }
});
```

---

## Prompt Injector Changes (`prompt-injector.js`)

Before falling back to platform config selectors, check for a pinned target:

```javascript
async function resolveTarget(hostname) {
  const { pinnedTargets = {} } = await chrome.storage.local.get('pinnedTargets');
  const pin = pinnedTargets[hostname];
  if (pin) {
    const el = document.querySelector(pin.selector);
    if (el) return { element: el, platform: `${hostname} (pinned)` };
    // Pinned element gone — fall through and notify user
    console.warn('[Vapor] Pinned target not found, falling back to auto-detect');
  }
  return autoDetect(hostname);
}
```

---

## Mac App Changes (`BrowserBridge.swift`)

```swift
func activatePicker() {
    server?.sseHub.broadcast(event: "prompt", json: ["type": "ACTIVATE_PICKER"])
}

// In handleExtensionResponse(_:):
case "TARGET_SELECTED":
    let domain = json["domain"] as? String ?? ""
    let selector = json["selector"] as? String ?? ""
    pinnedTargets[domain] = PinnedTarget(selector: selector, domain: domain, pinnedAt: Date())
    toastService?.showSuccess("Target pinned for \(domain)")

case "PICKER_CANCELLED":
    break  // no action needed
```

Store `pinnedTargets` in `UserDefaults` as JSON-encoded `[String: PinnedTarget]`.

---

## New `PinnedTarget` Model

```swift
struct PinnedTarget: Codable {
    var selector: String
    var domain: String
    var elementTag: String
    var label: String?
    var pinnedAt: Date
}
```

---

## UI Changes in Vapor

### Expanded Toolbar (`ToolbarView.swift`)

When `browserBridge.isExtensionConnected`:

```
🌐 Browser  ●  ChatGPT connected   [Pick Target]
```

`[Pick Target]` button calls `browserBridge.activatePicker()`.

### Settings Panel

Under **Browser Integration**:

```
Pinned targets:
  chatgpt.com      textarea#prompt-textarea    [Clear]
  custom-ai.com    div.chat > [contenteditable] [Clear]
```

Each row shows the domain, the CSS selector, and a Clear button that removes the pin from UserDefaults.

---

## Files to Create

| File | Purpose |
|---|---|
| `vapor-extension/content-scripts/prompt-target-picker.js` | Overlay, hover highlight, click handler, selector builder |

## Files to Modify

| File | Change |
|---|---|
| `vapor-extension/background.js` | Handle `ACTIVATE_PICKER` SSE message; handle `TARGET_CLICK` / `PICKER_CANCELLED` runtime messages; persist pinned targets |
| `vapor-extension/content-scripts/prompt-injector.js` | Check pinned targets before auto-detection |
| `vapor-extension/popup.html` + `popup.js` | Show pinned target for current domain; "Re-pick" button |
| `Vapor/Vapor/Services/BrowserBridge.swift` | `activatePicker()`, `TARGET_SELECTED` response handler, `pinnedTargets` storage |
| `Vapor/Vapor/Views/ToolbarView.swift` | "Pick Target" button when extension connected |
| `Vapor/Vapor/Views/SettingsView.swift` | Pinned targets list |
| `Vapor/Vapor/Models/UserPreferences.swift` | `pinnedTargets: [String: PinnedTarget]` |

---

## Acceptance Criteria

- [ ] "Pick Target" button appears in toolbar when extension is connected
- [ ] Pressing the button causes the picker overlay to appear in the active tab
- [ ] Hover highlight follows mouse and only activates on eligible input elements
- [ ] Tooltip shows element tag, dimensions, and "Click to select"
- [ ] Clicking an element sends `TARGET_SELECTED` with a CSS selector back to Vapor
- [ ] Escape key cancels the picker with no side effects
- [ ] Pinned selector is persisted in `chrome.storage.local` and in Vapor's `UserPreferences`
- [ ] Subsequent injections on the same domain use the pinned selector
- [ ] When pinned element is not found, injector falls back to auto-detect and logs a warning
- [ ] Settings panel shows all pinned targets with a Clear option per domain
- [ ] Picker does not interfere with normal page interaction after deactivation
- [ ] Picker works inside iframes (future: requires `allFrames: true` in `executeScript`)
