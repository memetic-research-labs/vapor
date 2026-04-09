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

The primary flow is designed around three moments, activated entirely from the keyboard:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          PRIMARY FLOW                                   │
│                                                                         │
│  MINIMIZED           ACTIVE / LISTENING        COMPRESS & PASTE         │
│                                                                         │
│  ┌──────────┐  Global  ┌───────────────────┐  ⌘↩   ┌────────────────┐ │
│  │  · Vapor │  hotkey  │  🔴 [||||||||]     │  ──►  │ ✅ Compressed  │ │
│  │  (pill)  │  ──────► │  (audio-reactive  │       │    in clipboard│ │
│  └──────────┘          │   mic icon, live  │       └────────┬───────┘ │
│                        │   transcript)     │                │         │
│                        └───────────────────┘       ┌────────▼───────┐ │
│                                                     │  ⌘V  anywhere  │ │
│                                                     │  (terminal,    │ │
│                                                     │   IDE, chat)   │ │
│                                                     └────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### The Three Gestures

1. **Global hotkey** (e.g., `⌃⌥Space`) — activates Vapor from any app, expands window from minimized pill
2. **Speak** — the mic activates automatically; the icon turns red and responds visually to your voice level in real time
3. **⌘↩** — compress & copy; return to your terminal/IDE/chat and paste with `⌘V`

Everything else in the UI supports or explains this three-gesture flow. The mouse is never required.

---

## Window States

Vapor has two window states. The transition between them is the activation gesture.

### Minimized (Micro) State — default resting state

When not actively in use, Vapor collapses to a compact **floating pill** in the corner of the screen. It is barely intrusive — just enough to confirm the app is running.

```
┌──────────────────┐
│  · Vapor         │   ← Tiny pill, always on top, low opacity
└──────────────────┘
```

- Size: ~120 × 28 px
- Opacity: 60–70% (slightly transparent so it doesn't obscure content)
- Position: Bottom-right or user-chosen corner; position is remembered
- Click or global hotkey expands to the full window

### Full / Active State — when composing or reviewing

The full window opens when the user triggers the global hotkey or clicks the pill.

```
┌──────────────────────────────────────────────────────┐
│  🔴 [||||||||]   [⚡ Compress & Copy  ⌘↩]  [⚙]  [🧪] │  ← Toolbar
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

When the user presses `⌘↩` (compress & copy), the window can optionally auto-minimize back to the pill so the user can switch immediately to their target app and paste.

---

## Window Design

### Layout

Vapor's full window stays above all other apps. It appears alongside — not over — whatever tool the user is prompting. The wireframe above in **Window States** shows the full layout.

**Window properties:**
- Size: 500 × 340 (default), fully resizable
- Level: Floating (`.floating` window level, always on top)
- Behavior: Joins all Spaces; works alongside full-screen apps
- Title bar: Hidden (borderless, draggable via toolbar area)
- Position: Remembered across sessions

### Audio-Reactive Mic Icon

The mic icon in the toolbar is the primary dictation signal. It has three distinct visual states:

| State | Icon appearance |
|---|---|
| Idle | 🎤 Gray mic, static |
| Listening — quiet | 🔴 Red mic + short bar `[|  ]` |
| Listening — speaking | 🔴 Red mic + tall bars `[||||||||]` |
| Listening — loud | 🔴 Red mic + overflowing bars `[||||||||||]` |

The bar height is driven by the **real-time audio input level** captured from the microphone (already computed as `inputLevel` in `SpeechDictationService`). This gives users instant confirmation that their voice is being picked up — a critical feedback signal when using Vapor without looking at the screen.

The bars should be rendered as a small inline waveform or VU-meter strip to the right of the mic icon, using the system red color.

### Toolbar (top strip)

The toolbar is the command center. Left-to-right reading order matches task order.

| Control | Label / Icon | Interaction | Shortcut |
|---|---|---|---|
| Dictation indicator | 🎤 / 🔴 [audio bars] | Read-only during Fn-key dictation; click to toggle manually | `Fn` hold or click |
| Compress & Copy | ⚡ "Compress & Copy" | Primary action button, always prominent | `⌘↩` |
| Clear | "Clear" | Resets editor and compressed preview | `⌘N` |
| Settings | ⚙ | Opens settings sheet | `⌘,` |
| Test sidebar | 🧪 | Reveals OpenRouter test panel | — |

The **Copy** dropdown (original vs. compressed) is a secondary control accessed via the main Copy icon next to the Compress button for users who want to copy without compressing, or copy the original text.

---

## States & Visual Feedback

### Dictation States

| State | Mic icon appearance | Editor behavior |
|---|---|---|
| Idle (window minimized) | Pill only: `· Vapor` | N/A — window is collapsed |
| Idle (window open) | 🎤 Gray mic, static | Placeholder: "Type or speak your prompt…" |
| Listening — quiet | 🔴 Red mic + `[|  ]` | Waiting for voice input |
| Listening — active | 🔴 Red mic + `[||||||||]` | Live transcript appearing in editor |
| Listening — loud | 🔴 Red mic + `[||||||||||]` | Live transcript, icon shows signal clipping |
| Finalizing | Brief spinner | Transcript committing to editor |
| Done | Returns to gray idle | Final text in editor; cursor at end |

The audio-reactive bars give users **immediate physical confirmation** that the mic is capturing their voice, without needing to read any text. This matters most when Vapor is in a corner of the screen while focus is on a terminal or IDE.

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

1. **Activate Vapor:** User presses the global hotkey (e.g., `⌃⌥Space`) from any app. Vapor expands from its minimized pill to the full window and immediately starts listening.
2. **Audio-reactive feedback:** The mic icon turns red and the bar indicator responds in real time to the user's voice level, driven by the `inputLevel` reading from the audio engine. Users can confirm the mic is working without looking away from their primary app for more than a glance.
3. **Live transcription:** Words appear in the editor as the user speaks. Partial results show in a slightly lighter color; final results are full opacity.
4. **Stop speaking:** The user stops talking. The Fn key (or clicking the mic) can also stop dictation explicitly.
5. **Compress & Copy:** User presses `⌘↩`. The compressed text lands in the clipboard.
6. **Optional auto-minimize:** After compress & copy, Vapor can optionally shrink back to the pill, returning focus to the user's primary app.
7. **Paste:** User presses `⌘V` in their terminal, IDE, or chat UI.

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
3. **Global hotkey setup:** A one-time prompt: *"Vapor uses `⌃⌥Space` to activate from any app. You can change this in Settings."* — user acknowledges, hotkey is registered.
4. **Backend auto-selection:** Default is Rule-Based (always works, no setup). A subtle one-line note in the expanded window: *"Using rule-based compression — open Settings to enable better backends."*
5. **First use tip:** After the first compress-and-copy, a one-time toast: *"Compressed prompt copied. Switch to your terminal or AI tool and press ⌘V."*

No onboarding wizard. The app explains itself through its state and labels.

---

## Accessibility & Power User Modes

### Keyboard-First Design

Every primary action has a keyboard shortcut. Users should never need to touch the mouse:

| Action | Shortcut |
|---|---|
| Activate Vapor (show / expand from pill) | `⌃⌥Space` (configurable global hotkey) |
| Minimize Vapor (collapse to pill) | `⌘H` or `Escape` |
| Start / stop dictation manually | `Fn` (hold) or click mic icon |
| Compress & Copy | `⌘↩` |
| Copy original | `⌘⇧C` |
| Clear editor | `⌘N` |
| Open Settings | `⌘,` |
| Close window | `⌘W` |

### Auto-Compress Mode (power user preference)

Configurable in Settings: **"Auto-compress when dictation ends"**

When enabled:
- Dictation ending (silence detected or Fn released) automatically triggers compress & copy
- The window optionally auto-minimizes back to the pill
- The entire flow becomes: `⌃⌥Space` → Speak → (silence) → `⌘V` — two keystrokes total
- A small lightning bolt badge on the mic icon signals auto-mode is active

This is the highest-efficiency mode for users who trust the compression backend.

### Window Management

- Vapor runs as a **menu bar app** (no Dock icon by default) so it does not clutter the taskbar
- The minimized pill is the primary persistent presence; it can be repositioned by dragging
- The global hotkey (`⌃⌥Space` by default, user-configurable) activates from any context including full-screen apps
- Vapor always re-opens in the same position and state as when it was last minimized
- It joins all Spaces (`.canJoinAllSpaces`), so it appears regardless of which desktop the user is on

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
2. **A power user** can do the entire flow (`⌃⌥Space` → speak → `⌘↩` → `⌘V` in terminal) without ever moving the mouse or switching focus deliberately
3. **The audio-reactive mic icon** gives immediate physical confirmation that voice is being captured, visible even at the edge of peripheral vision
4. **The compression output** is clearly distinguished from the original — no confusion about what is in the clipboard
5. **Errors** are explained in plain language and offer a clear path to resolution
6. **The minimized pill** means Vapor is always one hotkey away but never in the way
