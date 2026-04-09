# Vapor — UX Design

## Purpose

**Vapor** is a power tool for agentic coders and LLM users. Its job is simple:

> **Speak → Compress → Paste.** Turn raw speech into a dense, token-efficient prompt already on your clipboard, ready to paste into any terminal, IDE, chat UI, or agentic workflow.

The app exists because many high-leverage LLM interfaces — terminal agents, custom CLIs, Raycast extensions, Warp, Cursor, Neovim plugins — have no built-in voice input or prompt optimization. Vapor sits in front of all of them as a floating, always-accessible layer.

---

## Users & Mental Model

### Who uses Vapor

| User type | Context | Pain point solved |
|---|---|---|
| Agentic coder | Terminal + Claude/Codex agent | No mic in terminal; prompts are verbose |
| Cursor / Windsurf user | IDE with agent panel | Wants faster prompt entry; hands on keyboard |
| Raycast / Alfred power user | Launcher-driven workflows | Needs spoken prompts without leaving keyboard |
| Researcher / writer | Any LLM chat interface | Dictates faster than typing; tokens are expensive |

### How users think about it

1. **I have a thought I want to send to an AI** — voice is faster than typing
2. **I want the AI to understand me** — compression preserves intent, not noise
3. **I want to paste it immediately** — clipboard integration means zero friction

The app must make this feel like one seamless gesture, not three steps.

---

## Core Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PRIMARY FLOW                                 │
│                                                                     │
│   IDLE              LISTENING            READY TO SEND              │
│                                                                     │
│  ┌────────┐  Hold   ┌────────────┐  Release  ┌──────────────────┐  │
│  │ 🎤     │  Fn ──► │ 🔴 Hearing │  Fn    ►  │ ⌘↩  Compress &  │  │
│  │ Vapor  │         │ your voice │           │     Copy         │  │
│  └────────┘         └────────────┘           └──────────────────┘  │
│                                                        │            │
│                                              ┌─────────▼─────────┐ │
│                                              │ ✅ Compressed text │ │
│                                              │    in clipboard    │ │
│                                              └───────────────────┘ │
│                                                        │            │
│                                              ┌─────────▼─────────┐ │
│                                              │  Paste anywhere   │ │
│                                              │  ⌘V in terminal,  │ │
│                                              │  chat, IDE...     │ │
│                                              └───────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### The Three Gestures

1. **Hold Fn** — dictate (Fn key works system-wide; mic button is the alternative)
2. **⌘↩ (Cmd + Return)** — compress & copy
3. **⌘V** — paste compressed prompt wherever you need it

Everything else in the UI exists to support or explain this three-gesture flow.

---

## Window Design

### Layout

Vapor is a **compact floating window** that stays above all other apps. It appears alongside — not over — whatever tool the user is prompting.

```
┌──────────────────────────────────────────────────────┐
│  🎤 [Hold Fn]    [⚡ Compress & Copy  ⌘↩]  [⚙]  [🧪] │  ← Toolbar
├──────────────────────────────────────────────────────┤
│                                                      │
│   Type or speak your prompt here…                   │  ← Raw input
│   (editable, grows with content)                    │
│                                                      │
├─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│  ─ appears after compress
│  📊 0.65 ratio · 234 → 152 tokens · Saved 82        │  ← Stats bar
├──────────────────────────────────────────────────────┤
│  seniorbackendengineer reviewpullrequest             │  ← Compressed preview
│  focuscorrectnessperformance directnotharsh          │  (read-only, selectable)
└──────────────────────────────────────────────────────┘
```

**Window properties:**
- Size: 500 × 340 (default), fully resizable
- Level: Floating (`.floating` window level, always on top)
- Behavior: Joins all Spaces; works alongside full-screen apps
- Title bar: Hidden (borderless, draggable via toolbar area)
- Position: Remembered across sessions

### Toolbar (top strip)

The toolbar is the command center. Left-to-right reading order matches task order.

| Control | Label / Icon | Interaction | Shortcut |
|---|---|---|---|
| Dictation | 🎤 · "Hold Fn" (idle) → 🔴 "Listening…" (active) | Click to toggle; Fn key is global shortcut | `Fn` hold |
| Compress & Copy | ⚡ "Compress & Copy" | Primary action button, always prominent | `⌘↩` |
| Clear | "Clear" | Resets editor and compressed preview | `⌘N` |
| Settings | ⚙ | Opens settings sheet | — |
| Test sidebar | 🧪 | Reveals OpenRouter test panel | — |

The **Copy** dropdown (original vs. compressed) is a secondary control accessed via the main Copy icon next to the Compress button for users who want to copy without compressing, or copy the original text.

---

## States & Visual Feedback

### Dictation States

| State | Mic button appearance | Editor hint |
|---|---|---|
| Idle | 🎤 "Hold Fn" (gray, muted) | Placeholder: "Type or speak your prompt…" |
| Listening | 🔴 "Listening…" (pulsing waveform icon, red) | Live transcript appears as you speak |
| Processing | Spinner (brief, <0.5s) | Transcript finalizing |
| Done | Returns to idle | Final text in editor; cursor at end |

The **pulsing waveform icon** is the primary listening signal. It must be visible at a glance without reading text — agentic users keep focus on their primary tool, not Vapor.

### Compression States

| State | Button appearance | Panel behavior |
|---|---|---|
| No input | Compress & Copy (disabled, dimmed) | Stats bar and preview hidden |
| Has input, not yet compressed | Compress & Copy (enabled) | Stats bar and preview hidden |
| Compressing | Spinner inside button | Spinner inline, stats/preview hidden |
| Compressed | Compress & Copy (re-enabled for re-run) | Stats bar + compressed preview slide in |

### Toast Notifications

Toasts appear at the top of the window, auto-dismiss after 2 seconds. They confirm actions without demanding attention.

| Event | Toast | Color |
|---|---|---|
| Compressed & copied | "Compressed & copied (0.65 ratio)" | Green |
| Original copied | "Original copied" | Blue/neutral |
| Compression failed | "Compression failed: [reason]" | Red |
| No microphone access | "Microphone access required — see System Settings" | Red |

---

## Interaction Design

### Dictation Flow (detailed)

1. **Global trigger:** User holds `Fn`. Vapor's mic button turns red and pulses. No click needed — the key event is captured system-wide regardless of focus.
2. **Live transcription:** Words appear in the editor as the user speaks. Partial results show in a slightly lighter color; final results are full opacity.
3. **Stop:** User releases `Fn`. Speech recognition finalizes. Cursor moves to end of text.
4. **Auto-compress option (configurable):** Optionally, releasing Fn can automatically trigger compress & copy — zero additional keystrokes for the most common flow.

### Compression Flow (detailed)

1. **Trigger:** User presses `⌘↩` or clicks "Compress & Copy".
2. **Inline spinner** appears inside the button — no modal, no blocking overlay.
3. **On success:** Stats bar and compressed preview slide in smoothly (0.2s animation). Toast confirms clipboard copy.
4. **On failure:** Toast shows error. Original text stays intact. User can retry or switch backend in Settings.
5. **Clipboard:** Compressed text is always what gets copied — the assumption is that the user wants the optimized version.

### Editing Flow

The raw text editor is a standard macOS `NSTextView`:
- Full macOS text editing shortcuts (⌘Z undo, ⌘A select all, etc.)
- Tab, arrow keys, and cursor work normally
- Drag-and-drop text accepted
- Paste from clipboard (`⌘V`) accepted

The compressed preview is **read-only and selectable** — users can manually copy a portion if needed, but cannot edit it. To change the compressed output, edit the original and re-compress.

---

## Settings Panel

Settings are a modal sheet. They contain exactly what is needed — no more.

```
Settings
─────────────────────────────────────────
Compression Backend

  ◉ Rule-Based (Local)
    Free · Always available · ~65% quality

  ○ Apple Foundation Models
    Free · On-device · macOS 26+ required

  ○ Local LLM (On-Device)
    Free · Best quality · Requires 2GB download

  ○ OpenRouter (Cloud)
    API key required · ~$0.01/1M tokens

─────────────────────────────────────────
[When OpenRouter selected]

  API Key  [sk-…………………]
  Model    [glm-5         ]
           Default: glm-5 (fast, cheap)

─────────────────────────────────────────
[When Local LLM selected]

  ✅ Model ready  Qwen2.5-3B (~2.1 GB)
  — or —
  ⬇ Download Qwen2.5-3B  [████░░ 62%]

─────────────────────────────────────────
                    [Cancel]  [Save]
```

**Design principles for settings:**
- Only show fields relevant to the selected backend
- Never make users scroll unless the window is tiny
- Explain the tradeoffs of each backend inline (cost, privacy, quality, requirements)
- Backend selection is radio-button style with a clear visual active state

---

## Onboarding (First Launch)

First launch should take < 30 seconds and leave the user ready to dictate.

1. **Microphone permission prompt** — triggered automatically; macOS system dialog
2. **Speech recognition permission** — same; macOS system dialog
3. **Backend auto-selection:** Default is Rule-Based (always works, no setup). A subtle one-line banner at the bottom: *"Using rule-based compression. Open Settings to enable better backends."*
4. **First use tip:** After the first compress-and-copy, a one-time tooltip: *"Your compressed prompt is in the clipboard. Switch to your terminal or AI tool and press ⌘V."*

No onboarding wizard. The app explains itself through its state and labels.

---

## Accessibility & Power User Modes

### Keyboard-First Design

Every primary action has a keyboard shortcut. Users should never need to touch the mouse:

| Action | Shortcut |
|---|---|
| Start / stop dictation | `Fn` (hold) |
| Compress & Copy | `⌘↩` |
| Copy original | `⌘⇧C` |
| Clear editor | `⌘N` |
| Open Settings | `⌘,` |
| Close / Hide window | `⌘W` or `⌘H` |

### Auto-Compress Mode (power user preference)

Configurable in Settings: **"Auto-compress when dictation ends"**

When enabled:
- Releasing `Fn` automatically triggers compress & copy
- The entire flow becomes: Hold Fn → Speak → Release Fn → Paste
- A green checkmark badge appears on the mic icon to signal auto-mode is on

This is the highest-efficiency mode for users who trust the compression backend.

### Window Management

- Vapor can be hidden with `⌘H` (standard macOS hide) or `⌘W`
- It reappears via Dock, menu bar, or a configurable global hotkey
- It always re-opens in the same position
- It does not appear in Mission Control's full-screen Space layouts (`.canJoinAllSpaces` behavior)

---

## Visual Design Direction

### Philosophy

The UI should feel like a **focused developer tool**, not a consumer app. Clarity and density matter more than decoration.

- **Color use:** Minimal. System colors only. Accent color for the primary action button. Red for dictation active state. Green for success toasts. The editor is plain white/dark — no chrome.
- **Typography:** System font (SF Pro) throughout. Monospaced font for the compressed preview — it signals "this is output/data, not prose."
- **Density:** Compact but not cramped. A power user running Vapor at 500×340 alongside a terminal should see everything without scrolling during normal use.
- **Dark mode:** Full support. Dark mode is the default environment for most agentic coding users.
- **Animations:** Subtle and fast. Stats bar and compressed preview slide in at 0.2s. Toast fades in at 0.15s. Nothing should feel sluggish.

### Window Chrome

- Hidden title bar (`.hiddenTitleBar` window style)
- Draggable via the toolbar area (background drag region)
- Traffic light buttons (close/minimize/zoom) remain functional but visually quiet
- Rounded corners, native macOS vibrancy material for the window background (optional)

---

## OpenRouter Test Sidebar

This is a **power-user debugging panel**, not part of the primary flow. It is hidden by default and toggled via the 🧪 flask button.

```
┌──────────────────────────────────────────────────────┬─────────────────┐
│  (main editor panel)                                 │  OpenRouter     │
│                                                      │  ─────────────  │
│                                                      │  API Key        │
│                                                      │  [sk-…]         │
│                                                      │  ─────────────  │
│                                                      │  Prompt         │
│                                                      │  [compressed    │
│                                                      │   text auto-    │
│                                                      │   populated]    │
│                                                      │  ─────────────  │
│                                                      │  [Send]         │
│                                                      │  ─────────────  │
│                                                      │  Response       │
│                                                      │  (scrollable)   │
└──────────────────────────────────────────────────────┴─────────────────┘
```

The compressed prompt auto-populates the sidebar's prompt field, so users can immediately test whether their compressed prompt produces the right output from an LLM.

---

## Prompt History (Future / Phase 2)

History is tracked silently in the background via SwiftData. Future UI entry points:

- A "History" button or panel (e.g., list icon in toolbar) showing past prompt pairs
- Each history item shows: original snippet, compressed snippet, ratio, backend used, timestamp
- Tap any item to restore the original to the editor
- Search / filter history by keyword or date
- Mark favorites (⭐)

This feature does not block the primary flow. History is opt-in visible.

---

## Error Handling & Graceful Degradation

| Condition | Behavior |
|---|---|
| No microphone permission | Toast error + link to System Settings |
| Speech recognizer unavailable (offline, unsupported) | Mic button disabled with tooltip explaining why |
| Foundation Models unavailable (wrong OS / AI disabled) | Backend greyed out in Settings with explanation |
| OpenRouter API key missing / invalid | Toast error; Settings sheet opens automatically if key is missing |
| Local LLM model not downloaded | Settings shows download prompt; backend shows "needs setup" label |
| Compression fails (all backends) | Toast error; original text preserved; user can retry |
| Network timeout (OpenRouter) | Toast: "OpenRouter timed out — falling back to rule-based" |

The **fallback chain** (Foundation Models → OpenRouter → Rule-Based) handles transient failures silently when possible. Silent fallbacks are logged to console for debugging but do not interrupt the user.

---

## Success Criteria

A successful UX means:

1. **A new user** can speak, compress, and paste a prompt in under 30 seconds with no explanation
2. **A power user** can do the entire flow (Fn → speak → release → ⌘V in terminal) without ever moving the mouse
3. **The compression output** is clearly distinguished from the original — no confusion about what is in the clipboard
4. **Errors** are explained in plain language and offer a clear path to resolution
5. **The window** never gets in the way — it floats, it's compact, and it disappears cleanly when not needed
