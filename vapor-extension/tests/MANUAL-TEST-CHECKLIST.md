# Vapor Extension — Manual Test Checklist

Run after reloading the extension in `chrome://extensions` (Developer mode).

## Prerequisites

- [ ] Extension loaded in Chrome (Developer mode)
- [ ] Vapor Mac app running on `127.0.0.1:8766`
- [ ] Auth token configured in sidebar → Settings
- [ ] DevTools console open on sidebar (right-click sidebar → Inspect)

---

## 1. Sidebar Basics

- [ ] Click toolbar icon → sidebar opens with status dot, settings gear, screenshot grid
- [ ] `Cmd+Shift+P` → sidebar opens
- [ ] Side panel empty state shows "Attach screenshots in Vapor, then drag them here"
- [ ] Connection dot is green (connected) or red (disconnected)
- [ ] Click "Clear" with no images → no error, empty state stays
- [ ] Click "Verbose" toggle → log container appears
- [ ] Click "Verbose" again → log container hides
- [ ] Verbose setting persists after closing/reopening sidebar (`vaporVerboseLogging` in `chrome.storage.local`)
- [ ] Settings panel collapses/expands, persists on reopen (`vaporSettingsExpanded` in `chrome.storage.local`)
- [ ] Dark/light mode follows system `prefers-color-scheme`

---

## 2. Text Injection (existing — regression check)

- [ ] Open ChatGPT tab (`chatgpt.com`)
- [ ] Send a prompt from Vapor with **no images** → text appears in ChatGPT input
- [ ] Repeat on Claude (`claude.ai`) and Gemini (`gemini.google.com`)
- [ ] DevTools console shows `[Vapor:injector]` log entries

---

## 3. Screenshot Sync

Screenshots are synced independently of prompt flow via SSE.

- [ ] Import a screenshot in Vapor (Screenshot Shelf)
- [ ] Side panel shows thumbnail with hash label (e.g., `015899c2`) and size label
- [ ] `vapor_img_<hash>` key exists in `chrome.storage.local`
- [ ] `vaporScreenshotOrder` array in storage matches sidebar order
- [ ] Dismiss screenshot in Vapor → thumbnail removed from sidebar, storage key deleted
- [ ] Import 5+ screenshots → sidebar shows all, newest first
- [ ] Import 65+ screenshots → oldest pruned, max 64 retained
- [ ] Close sidebar, reopen → screenshots persist from storage
- [ ] Click "Clear" → all `vapor_img_*` keys removed, empty state restored

---

## 4. Click-to-Copy (primary image attachment path)

Clipboard API write is blocked in Chrome extension side panel context (#23).
Right-click → Copy Image is the current workaround.

- [ ] Click a thumbnail → toast shows "Right-click image → Copy to clipboard"
- [ ] Right-click thumbnail → "Copy Image" in context menu
- [ ] Paste in ChatGPT → image appears as attachment
- [ ] Paste in Claude → image appears as attachment
- [ ] Paste in Gemini → image appears as upload
- [ ] Multiple images: each thumbnail individually copyable

---

## 5. Keyboard Shortcuts

- [ ] `Cmd+Shift+C` captures page (no regression)
- [ ] Shortcuts work when an AI chat tab is focused
- [ ] Shortcuts work when a non-AI tab is focused

---

## 6. Connection & Error States

- [ ] Kill Vapor app → extension badge shows red `!`
- [ ] Restart Vapor → extension reconnects, badge clears
- [ ] Clear auth token → badge shows `!`, sidebar shows "No auth token" warning
- [ ] Set wrong token → badge shows `!`, sidebar shows "Token mismatch" warning
- [ ] Set correct token → reconnects, badge clears

---

## 7. Image Markdown Preservation

- [ ] Prompt containing `![description](path/to/image.webp)` references is sent
- [ ] After compression, markdown references are preserved unchanged in the injected text
- [ ] Verify in DevTools: `Text injected successfully` log, check input content for `![` prefix

---

## 8. Compression Preservation Rules

- [ ] Prompt containing file paths (e.g., `/Users/.../file.swift`) is sent — paths preserved exactly after compression
- [ ] Prompt containing numbers (e.g., `HTTP 200`, `$200,000`, `45 minutes`) is sent — numbers preserved
- [ ] Prompt containing hashes/IDs (e.g., `screenshot_bcd1013e`, `sha:abc123`) is sent — preserved
- [ ] Prompt containing URLs (e.g., `https://example.com/path`) is sent — preserved
- [ ] Prompt containing code symbols (e.g., `var`, `func`, `println!`) is sent — preserved
- [ ] Compressed output does NOT contain hallucinated `Input:` / `Output:` example pairs
- [ ] Compressed output is NOT longer than the original
- [ ] If compression validation fails, error is shown (nothing copied to clipboard)

---

## Notes

- Programmatic clipboard write is blocked in side panel context — tracked in #23
- Drag-and-drop from side panel to webpage does NOT work (Chrome strips cross-context `DataTransfer` data)
- Right-click → Copy Image on thumbnails is the only reliable image copy method
- `sidePanel.open()` requires a user gesture in MV3 — the keyboard shortcut and toolbar icon always work
