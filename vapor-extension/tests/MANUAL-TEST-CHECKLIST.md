# Vapor Extension — Manual Test Checklist

Run after reloading the extension in `chrome://extensions` (Developer mode).

## Prerequisites

- [ ] Extension loaded in Chrome (Developer mode)
- [ ] Vapor Mac app running on `127.0.0.1:8766`
- [ ] Auth token configured in extension popup → Settings
- [ ] DevTools console open on target tab (for `[Vapor:injector]` logs)

---

## 1. Popup & Sidebar Basics

- [ ] Click toolbar icon → sidebar opens with status dot, settings gear, screenshot grid
- [ ] `Cmd+Shift+P` → sidebar opens
- [ ] Side panel empty state shows "Attach screenshots in Vapor, then drag them here"
- [ ] Connection dot is green (connected) or red (disconnected)
- [ ] Click "Clear" with no images → no error, empty state stays
- [ ] Click "Verbose" toggle → log container appears
- [ ] Click "Verbose" again → log container hides
- [ ] Verbose setting persists after closing/reopening sidebar (`vaporVerboseLogging` in `chrome.storage.local`)

---

## 2. Text Injection (existing — regression check)

- [ ] Open ChatGPT tab (`chatgpt.com`)
- [ ] Send a prompt from Vapor with **no images** → text appears in ChatGPT input
- [ ] Repeat on Claude (`claude.ai`) and Gemini (`gemini.google.com`)
- [ ] Verify auto-submit works when enabled (if configured)
- [ ] DevTools console shows `[Vapor:injector]` log entries

---

## 3. Screenshot Sidebar (screenshot attachment flow)

Screenshots are synced independently of prompt flow. They appear in the sidebar for drag-and-drop.

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

## 4. Sidebar Drag-and-Drop (primary image attachment path)

- [ ] Side panel has images loaded (from previous injection or re-send)
- [ ] Drag a thumbnail from sidebar onto ChatGPT's input area
- [ ] ChatGPT shows image attachment preview
- [ ] Drag onto Claude's contenteditable area
- [ ] Claude shows image attachment
- [ ] Drag onto Gemini's input area
- [ ] Gemini shows image upload

### Edge cases

- [ ] Multiple images: all thumbnails shown, each individually draggable
- [ ] Drag image to a non-AI tab → no crash
- [ ] Sidebar "Clear" button after images loaded → images removed, empty state restored

---

## 5. Keyboard Shortcuts

- [ ] `Cmd+Shift+C` captures page (no regression)
- [ ] `Cmd+Shift+P` opens side panel
- [ ] Shortcuts work when an AI chat tab is focused
- [ ] Shortcuts work when a non-AI tab is focused

---

## 6. Connection & Error States

- [ ] Kill Vapor app → extension badge shows red `!`
- [ ] Restart Vapor → extension reconnects, badge clears
- [ ] Clear auth token → badge shows `!`, popup shows "No auth token" warning
- [ ] Set wrong token → badge shows `!`, popup shows "Token mismatch" warning
- [ ] Set correct token → reconnects, badge clears

---

## 7. Multi-Image Scenarios

- [ ] Import 2+ screenshots in Vapor
- [ ] Sidebar shows all thumbnails, newest first
- [ ] Each thumbnail individually draggable
- [ ] Each has correct hash label and size label

---

## 8. Image Markdown Preservation

- [ ] Prompt containing `![description](path/to/image.webp)` references is sent
- [ ] After compression, markdown references are preserved unchanged in the injected text
- [ ] Verify in DevTools: `Text injected successfully` log, check input content for `![` prefix

---

## Notes

- Automated `DragEvent`/`ClipboardEvent` injection may silently fail on some platforms. The sidebar drag-and-drop (section 4) is the reliable fallback.
- If automated injection fails, check DevTools logs for `INJECTION_LOG` entries forwarded to sidebar.
- `sidePanel.open()` requires a user gesture in MV3 — the auto-open on first injection may not work in all Chrome versions. The keyboard shortcut and popup button always work.
