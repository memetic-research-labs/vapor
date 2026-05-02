# Vapor Extension — Manual Test Checklist

Run after reloading the extension in `chrome://extensions` (Developer mode).

## Prerequisites

- [ ] Extension loaded in Chrome (Developer mode)
- [ ] Vapor Mac app running on `127.0.0.1:8766`
- [ ] Auth token configured in extension popup → Settings
- [ ] DevTools console open on target tab (for `[Vapor:injector]` logs)

---

## 1. Popup & Sidebar Basics

- [ ] Click toolbar icon → popup opens with status dot, capture buttons, green "Screenshots" button
- [ ] Click "Screenshots" button → side panel opens
- [ ] `Cmd+Shift+P` → side panel opens
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

## 3. Image Injection (new — automated flow)

For each target platform below:

1. Open the AI chat tab
2. Attach a screenshot in Vapor (Screenshot Shelf → "Attach for Injection")
3. Send to browser targeting that tab
4. Observe side panel + DevTools console

### ChatGPT (`chatgpt.com`)

- [ ] Side panel auto-opens on first image injection
- [ ] Thumbnail appears in sidebar with size label (e.g., "42K")
- [ ] Prompt text section shows the injected text
- [ ] DevTools console shows: `SET_PROMPT received`, `Target resolved`, `Found drop target`, `File input set`, `Text injected successfully`
- [ ] ChatGPT input shows image attachment (check for thumbnail preview in input area)

### Claude (`claude.ai`)

- [ ] Side panel shows thumbnail
- [ ] DevTools console shows drag-drop + file input logs
- [ ] Claude input shows image attachment

### Gemini (`gemini.google.com`)

- [ ] Side panel shows thumbnail
- [ ] DevTools console shows drag-drop + file input logs
- [ ] Gemini shows image upload indicator

---

## 4. Sidebar Drag-and-Drop (manual fallback — the reliable path)

This is the primary user-facing way to attach images when automated injection fails.

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

- [ ] Attach 2+ screenshots, send to browser
- [ ] Side panel shows all thumbnails
- [ ] DevTools logs show sequential injection with delays
- [ ] Each image processed with correct filename (`screenshot_1.webp`, `screenshot_2.webp`)

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
