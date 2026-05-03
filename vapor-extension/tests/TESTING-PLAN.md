# Vapor Extension — Automated Testing Plan

## Status: Deferred

This document describes the testing infrastructure to build when the team is ready to invest in automated extension tests.

---

## Architecture

Two layers:

```
┌─────────────────────────────┐
│  Layer 1: Unit Tests        │  Vitest + manual Chrome API mocks
│  Pure logic, no browser     │  Fast, CI-friendly
├─────────────────────────────┤
│  Layer 2: E2E Tests         │  Playwright + persistent context
│  Real browser, loaded ext   │  Slower, catches integration bugs
└─────────────────────────────┘
```

---

## Layer 1: Unit Tests (Vitest)

### Setup

```bash
cd vapor-extension
npm init -y
npm i -D vitest jsdom
```

`vitest.config.js`:
```js
export default {
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.js']
  }
};
```

`tests/setup.js` — mock only the Chrome APIs we use:

```js
globalThis.chrome = {
  runtime: {
    getURL: (path) => `chrome-extension://mock-id/${path}`,
    sendMessage: vi.fn(),
    onMessage: { addListener: vi.fn() },
    onInstalled: { addListener: vi.fn() },
    getManifest: () => ({ manifest_version: 3 })
  },
  storage: {
    local: {
      get: vi.fn().mockResolvedValue({}),
      set: vi.fn().mockResolvedValue(undefined)
    }
  },
  tabs: {
    query: vi.fn().mockResolvedValue([]),
    sendMessage: vi.fn().mockResolvedValue({}),
    get: vi.fn().mockResolvedValue({}),
    update: vi.fn().mockResolvedValue({})
  },
  windows: {
    update: vi.fn().mockResolvedValue({})
  },
  scripting: {
    executeScript: vi.fn().mockResolvedValue([])
  },
  sidePanel: {
    open: vi.fn().mockResolvedValue(undefined)
  },
  action: {
    setBadgeText: vi.fn(),
    setBadgeBackgroundColor: vi.fn(),
    setTitle: vi.fn(),
    openPopup: vi.fn()
  },
  alarms: {
    create: vi.fn(),
    onAlarm: { addListener: vi.fn() }
  },
  commands: {
    onCommand: { addListener: vi.fn() }
  }
};
```

### What to unit test

#### `content-scripts/prompt-injector.js`

| Test | What it verifies |
|------|-----------------|
| `resolveTarget` with pinned selector | Uses pinned selector from `chrome.storage.local` when available |
| `resolveTarget` with platform config | Falls through to platform-specific selectors |
| `resolveTarget` generic fallback | Scores candidates by size, keywords, viewport proximity |
| `resolveTarget` no match | Returns `null` when nothing found |
| `setValue` on textarea | Uses native setter, fires `input` + `change` + `compositionend` events |
| `setValue` on contenteditable | Sets `innerText`, fires events |
| `findSubmitButton` scoring | `type=submit` > `aria-label` match > `data-testid` > SVG icon |
| `findSubmitButton` proximity | Among equal scores, picks closer button |
| `executeSubmit` button click | Calls `.click()` on resolved button |
| `executeSubmit` enter key | Falls back to `Enter` keydown/keypress/keyup events |

#### `sidepanel.js`

| Test | What it verifies |
|------|-----------------|
| `UPDATE_IMAGES` | Creates thumbnails from base64 data, renders grid |
| `CLEAR_IMAGES` | Revokes blob URLs, clears array, renders empty state |
| Thumbnail click | Shows right-click Copy Image guidance |
| Log toggle | Shows/hides log container, persists to `chrome.storage.local` |

#### `config/platform-config.js`

| Test | What it verifies |
|------|-----------------|
| Known hostnames | Returns correct config for `chatgpt.com`, `claude.ai`, `gemini.google.com`, etc. |
| Unknown hostname | Returns `_default` config |
| Config shape | Has `promptSelectors` for all platforms |

#### `background.js`

| Test | What it verifies |
|------|-----------------|
| `normalizeHost` | Strips `www.`, lowercases |
| `inferPlatform` | Maps hostnames to platform names |
| `isCandidateTab` | Rejects `chrome://`, `edge://`, `about:`, extension URLs |
| `serializeTab` | Produces `{ tab_id, title, url, platform }` |
| `handlePromptInject` with images | Broadcasts `UPDATE_IMAGES` to sidebar, calls `sidePanel.open()` |
| `handlePromptInject` auto-open | Only opens sidebar on first image injection (`sidebarAutoOpened` flag) |
| `CLEAR_IMAGES` handler | Clears stored images, broadcasts to sidebar |
| `open-side-panel` command | Calls `chrome.sidePanel.open()` |

### Test file structure

```
tests/
  setup.js
  unit/
    prompt-injector.test.js
    sidepanel.test.js
    platform-config.test.js
    background.test.js
```

---

## Layer 2: E2E Tests (Playwright)

### Setup

```bash
npm i -D @playwright/test
npx playwright install chromium
```

`playwright.config.js`:
```js
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  use: {
    channel: 'chromium',
    headless: false,
    args: [
      '--disable-extensions-except=/path/to/vapor-extension',
      '--load-extension=/path/to/vapor-extension'
    ]
  }
});
```

### What to E2E test

#### Extension loading

| Test | What it verifies |
|------|-----------------|
| Extension loads | No errors in service worker console |
| Badge initial state | Shows `!` in red (disconnected by default) |

#### Side panel page

| Test | What it verifies |
|------|-----------------|
| Navigate to `sidepanel.html` | Page renders without errors |
| Empty state | Shows placeholder text when no images |
| Receive images via message | Thumbnails appear after `UPDATE_IMAGES` |
| Clear button | Removes images, shows empty state |

#### Content script injection

| Test | What it verifies |
|------|-----------------|
| Inject on test HTML page | Navigate to a minimal page with `<textarea id="test">`, send `SET_PROMPT`, verify value set |
| Inject on contenteditable | Same with `<div contenteditable="true">` |
| Image drag-drop on test page | Verify `dragenter`/`dragover`/`drop` events fire on target element |

#### Integration: background → sidebar → content script

| Test | What it verifies |
|------|-----------------|
| Full message flow | Mock SSE event with `PROMPT_INJECT` + images → sidebar receives `UPDATE_IMAGES` → content script receives `SET_PROMPT` |

### E2E test file structure

```
tests/
  e2e/
    extension-loading.test.js
    sidepanel.test.js
    content-script.test.js
    integration.test.js
    fixtures/
      test-page.html      # Minimal page with textarea + contenteditable + file input
```

### Test page fixture

`tests/e2e/fixtures/test-page.html` — minimal HTML page that mimics an AI chat interface:

```html
<!DOCTYPE html>
<html>
<body>
  <textarea id="prompt-textarea" placeholder="Ask anything..."></textarea>
  <div contenteditable="true" data-placeholder="Message ChatGPT"></div>
  <input type="file" accept="image/*" />
  <button type="submit" aria-label="Send message">Send</button>
</body>
</html>
```

---

## MV3-Specific Gotchas

1. **Service worker termination**: SWs die after 30s idle. Don't rely on in-memory state in production (use `chrome.storage`). For tests, be aware that Playwright keeps the SW alive longer than real Chrome.

2. **`sidePanel.open()` requires user gesture**: Can't call it from a test directly. Workaround: navigate to `chrome-extension://<id>/sidepanel.html` URL instead.

3. **No eval in content script isolated world**: Can't directly test content script internals from Playwright. Test via observed DOM mutations instead.

4. **Synthetic event limitations**: Browser may silently ignore synthetic `DragEvent` or `ClipboardEvent`. Vapor does not currently auto-inject images. The supported image flow is right-click thumbnail → Copy Image, then paste into the AI chat.

5. **Fixed extension ID for E2E**: Use a `key` field in manifest for consistent extension IDs across test runs.

---

## When to implement

- **Unit tests**: Good first step — fast to write, fast to run, catches regressions in `resolveTarget`, `setValue`, sidebar rendering, and storage handling.
- **E2E tests**: Higher value when the extension stabilizes and we want CI protection against Chrome API changes or platform DOM changes.
- **Start with**: Unit tests for `prompt-injector.js` (most complex logic, most likely to break) and `sidepanel.js` (new code). E2E for extension loading and side panel page.
