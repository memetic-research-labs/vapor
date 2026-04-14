# UX Design: Context Management & Glossary System

## Overview

This document describes the user experience for Vapor's **Context Management** and **Glossary** features. It is a companion to `docs/plan-context-management.md`, which covers the backend architecture. Together they address the research direction set out in the [Context Management Tools issue].

The goal is a fast, keyboard-first experience that feels as natural as dictating a single sentence — even when you are composing a large, complex prompt that weaves together articles, data tables, images, and stored glossary entries.

---

## Design Principles

1. **Capture fast, compose later.** Collecting context should take one click or one shortcut — the user never wants to stop what they are doing to organise.
2. **Inline is the only layout.** Context chunks live *inside* the prompt, not in a side panel that the user has to mentally map onto their text.
3. **Keyboard first, mouse optional.** Every core action has a shortcut or a `@`-trigger. The mouse is for discovery.
4. **Show provenance always.** Every piece of context shows where it came from. Trust depends on citations.
5. **Progressive disclosure.** New users see a simple "Capture → Compose → Compress" flow. Power users unlock glossaries, semantic search, and XHR interception through settings and contextual UI.

---

## Window Layout — Expanded State

When Context Management is active, Vapor's main window gains a new **Context Tray** panel that slides in from the left (collapsible). The existing Prompt Composer occupies the centre-right area.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ⚡ Vapor  [🎤] [Compose ▼] [Glossary] [Context ☰] [Compress ⌘↩] [⚙️]     │  ← Toolbar
├──────────────────┬──────────────────────────────────────────────────────────┤
│                  │                                                           │
│  CONTEXT TRAY    │                PROMPT COMPOSER                            │
│                  │                                                           │
│  ● Processing    │  [🎤 dictated segment — "Explain why SwiftNIO is        │
│  ○ Ready (3)     │   better than GCD for server workloads" ]                │
│                  │                                                           │
│  ─────────────── │  ┌──────────────────────────────────────────────────┐   │
│                  │  │ 📄 Context: "SwiftNIO Overview — swift.org"      │   │
│  📄 Article      │  │ Tags: swift · networking · concurrency           │   │
│  SwiftNIO README │  │ [↗ Open] [✕ Remove]                             │   │
│  swift.org       │  └──────────────────────────────────────────────────┘   │
│  Tags: swift…    │                                                           │
│  [+ Add]         │  [🎤 dictated segment — "Specifically compare…" ]        │
│                  │                                                           │
│  🖼 Image         │  ┌──────────────────────────────────────────────────┐   │
│  arch-diagram.png│  │ 🖼 @my-arch-diagram                              │   │
│  cdn.example.com │  │ [thumbnail]  Architecture Diagram                │   │
│  Tags: arch…     │  │ [↗ Open] [✕ Remove]                             │   │
│  [+ Add]         │  └──────────────────────────────────────────────────┘   │
│                  │                                                           │
│  [+ Capture]     │  ─────────────────────────────────────────────────────  │
│                  │  Ratio: –  |  Tokens: ~340  |  Segments: 4              │
└──────────────────┴──────────────────────────────────────────────────────────┘
```

---

## Context Tray

### Purpose

The Context Tray is a live feed of every `ContextItem` that has been captured in the current session (and recent past sessions). It is the "inbox" for raw browser captures before they are inserted into a prompt.

### Layout

```
┌──────────────────┐
│  CONTEXT TRAY  ☰ │  ← header with collapse/expand toggle
├──────────────────┤
│ 🔵 Processing…   │  ← spinning indicator (disappears when queue empty)
│ 3 items ready    │
├──────────────────┤
│ [ Search items ] │  ← live text filter
├──────────────────┤
│  ┌────────────┐  │
│  │ 📄 Article │  │  ← item card
│  │ SwiftNIO   │  │
│  │ swift.org  │  │
│  │ ● ready    │  │
│  │ swift nwk  │  │  ← tag pills
│  │ [+Add][✕]  │  │
│  └────────────┘  │
│  ┌────────────┐  │
│  │ 🖼 Image   │  │
│  │ [thumb]    │  │
│  │ diagram.png│  │
│  │ ● ready    │  │
│  │ [+Add][✕]  │  │
│  └────────────┘  │
├──────────────────┤
│ [+ Capture text] │  ← manual text entry
│ [🌐 Open Browser]│  ← focuses browser window
└──────────────────┘
```

### Item Card States

| State | Visual | Meaning |
|---|---|---|
| `pending` | Grey dot, "Waiting…" | In queue, not yet started |
| `processing` | Blue spinner | Being vectorised / tagged |
| `ready` | Green dot | Processed; insertable into prompt |
| `failed` | Red dot | Processing failed; tap for details |

### Actions

- **Drag to Composer:** Drag any ready item into the prompt composer to insert it at the drop point as an inline `ContextItem` chip.
- **[+ Add] button:** Inserts the item at the current cursor position in the composer.
- **[✕] button:** Removes the item from the tray (does not delete the asset).
- **Long-press / right-click:** Context menu with "Save to Glossary…", "Copy citation", "Preview", "Delete".

---

## Prompt Composer

### Overview

The Prompt Composer replaces the single `NSTextView` in the existing Vapor window. It is a **mixed-content editor** that can hold both text runs and inline context chips — displayed linearly in the order the user assembles them.

This is conceptually similar to a rich-text editor or a document editor row-by-row, but rendered in a SwiftUI `LazyVStack` over a custom layout engine (not `NSAttributedString`).

### Segment Types — Visual Appearance

#### Dictated Text Segment
```
┌───────────────────────────────────────────────────────────┐
│ 🎤  "Explain why SwiftNIO is better than GCD for server   │
│      workloads — focus on memory allocations."            │
└───────────────────────────────────────────────────────────┘
```
Background: `systemBackground`. Left edge: thin teal accent bar. Microphone icon indicates this was dictated.

#### Typed Text Segment
```
┌───────────────────────────────────────────────────────────┐
│ ⌨️  "Also consider the following benchmark data:"         │
└───────────────────────────────────────────────────────────┘
```
Background: `systemBackground`. Left edge: thin grey accent bar.

#### Context Item Chip (text)
```
┌───────────────────────────────────────────────────────────┐
│ 📄  SwiftNIO README — swift.org                           │
│     Tags: swift · networking · concurrency                │
│     "Swift NIO is a cross-platform asynchronous event-    │
│      driven network application framework…" [expand ▼]   │
│     [Cite: ¹]  [↗ Open]  [✕ Remove]                      │
└───────────────────────────────────────────────────────────┘
```
Background: `secondarySystemBackground`. Border: 1pt, `separator`. Icon matches `ContextItemKind`.

#### Context Item Chip (image)
```
┌───────────────────────────────────────────────────────────┐
│ 🖼  Architecture Diagram — cdn.example.com                │
│     ┌──────────────────────┐                              │
│     │   [thumbnail 256px]  │                              │
│     └──────────────────────┘                              │
│     Tags: architecture · diagram                          │
│     [Cite: ²]  [↗ Open]  [✕ Remove]                      │
└───────────────────────────────────────────────────────────┘
```

#### Glossary Item Chip
```
┌───────────────────────────────────────────────────────────┐
│ 📚  @swiftnio  ·  3 items  (2 articles, 1 image)          │
│     [Expand ▼]  [✕ Remove]                                │
└───────────────────────────────────────────────────────────┘
```
Background: accent color at 10% opacity. Border: accent color.

#### Citation Block
```
┌───────────────────────────────────────────────────────────┐
│ 📎  References                                            │
│     ¹ swift.org — "SwiftNIO" (2025-04-14)                │
│     ² cdn.example.com/diagram.png — "Architecture…"      │
└───────────────────────────────────────────────────────────┘
```
Auto-appended at the end of the composer when any context items are present. Always collapses to "2 citations" in the compressed preview.

### Keyboard Interactions in Composer

| Shortcut | Action |
|---|---|
| `@` | Open autocomplete popover for glossary items |
| `⌘ + Shift + C` | Capture current browser selection into context tray |
| `⌘ + Shift + V` | Insert last captured context item at cursor |
| `⌘ + [` / `⌘ + ]` | Select previous / next segment |
| `⌘ + Delete` | Remove selected segment |
| `⌘ + ↑` / `⌘ + ↓` | Move selected segment up / down |
| `⌘ + Return` | Serialise + compress (existing shortcut — unchanged) |

### Reordering Segments

Drag-and-drop within the composer reorders segments. A drag handle (⠿) appears on hover at the left edge of each segment. On trackpad, two-finger drag is also supported.

---

## Autocomplete Popover

Triggered by typing `@` anywhere in a text segment within the composer.

```
┌─────────────────────────────────┐
│  @swi|                          │  ← inline cursor position
│  ┌─────────────────────────┐    │
│  │ 📚 @swiftnio            │ ←  │  ← selected (highlighted)
│  │    SwiftNIO Docs · 3 ✦  │    │
│  ├─────────────────────────┤    │
│  │ 📄 @swift-evolution     │    │
│  │    Swift Evolution · 1  │    │
│  ├─────────────────────────┤    │
│  │ 🖼 @swift-logo          │    │
│  │    Image set · 2        │    │
│  └─────────────────────────┘    │
│  ↑↓ navigate  ↩ insert  Esc dismiss
└─────────────────────────────────┘
```

- Results update on every keypress (debounced 80ms).
- Shows at most 8 results.
- Arrow keys navigate; `↩` or `Tab` inserts the selected item.
- If no results, shows "No matching glossary items — [Create new]".

### Semantic Suggestion Strip

When the user has typed more than ~3 words without triggering `@`, a low-prominence suggestion strip appears *below* the active text segment (not a popover — it does not interrupt typing):

```
  💡 Suggestions: @swiftnio  @concurrency-patterns  @server-benchmarks   [×]
```

- Suggestions are generated by `GlossarySearchService.search(query:)` on the current segment text.
- The strip fades in after a 400ms debounce and disappears when focus moves away or is dismissed with `Esc`.
- Clicking a suggestion inserts the glossary item at the end of the current segment and starts a new text segment.

---

## Glossary Manager View

Accessed from the toolbar `[Glossary]` button or `⌘ + G`. Opens as a sheet (or a side panel in the expanded window).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Glossaries                                      [+ New Glossary] [Done]   │
├───────────────────┬─────────────────────────────────────────────────────────┤
│                   │  iOS Architecture Patterns                  [✏️ Edit]  │
│  📘 Default       │  ─────────────────────────────────────────────────────  │
│  🟢 iOS Arch      │  [ Search items ]             [+ New Item] [Sort ▼]    │
│  🟣 Swift Perf    │                                                         │
│  🔴 My Project    │  ┌──────────────────────────────────────────────────┐  │
│                   │  │ 📄 @mvc-overview    Text snippet · 2 items       │  │
│  [+ New Glossary] │  │ MVC pattern intro + Apple HIG reference          │  │
│                   │  │ Tags: architecture · mvc · uikit                 │  │
│                   │  │ Used 12×   Last: 2 days ago                      │  │
│                   │  │ [Insert] [Edit] [Delete]                         │  │
│                   │  └──────────────────────────────────────────────────┘  │
│                   │  ┌──────────────────────────────────────────────────┐  │
│                   │  │ 🖼 @uikit-diagrams   Image set · 5 images        │  │
│                   │  │ UIKit component hierarchy diagrams               │  │
│                   │  │ Tags: uikit · hierarchy · components             │  │
│                   │  │ Used 3×    Last: 1 week ago                      │  │
│                   │  │ [Insert] [Edit] [Delete]                         │  │
│                   │  └──────────────────────────────────────────────────┘  │
│                   │  ┌──────────────────────────────────────────────────┐  │
│                   │  │ 🏷 @swiftui-keywords   Keyword cluster · 18 kw   │  │
│                   │  │ @Observable, @State, @Binding, SwiftUI, …        │  │
│                   │  │ Tags: swiftui · keywords                         │  │
│                   │  │ Used 7×    Last: 3 days ago                      │  │
│                   │  │ [Insert] [Edit] [Delete]                         │  │
│                   │  └──────────────────────────────────────────────────┘  │
└───────────────────┴─────────────────────────────────────────────────────────┘
```

### Glossary Item Detail / Edit View

```
┌────────────────────────────────────────────────────────────┐
│  Edit Glossary Item                           [Save] [Cancel]│
├────────────────────────────────────────────────────────────┤
│  Name:       [ SwiftNIO Overview              ]            │
│  Short code: [ @swiftnio                      ]            │
│  Glossary:   [ iOS Architecture Patterns ▼    ]            │
│  Kind:       ● Text Snippet  ○ Image Set  ○ Keywords       │
├────────────────────────────────────────────────────────────┤
│  Content Items (2):                                        │
│                                                            │
│  ┌────────────────────────────────────────────────────┐   │
│  │ 📄 SwiftNIO README — swift.org         [✕ Remove]  │   │
│  └────────────────────────────────────────────────────┘   │
│  ┌────────────────────────────────────────────────────┐   │
│  │ 📄 SwiftNIO HTTP2 Docs — apple.github.io [✕ Remove]│   │
│  └────────────────────────────────────────────────────┘   │
│                                                            │
│  [+ Add from Context Tray]  [+ Paste URL]                 │
├────────────────────────────────────────────────────────────┤
│  Tags (auto + manual):                                     │
│  [swift] [networking] [nio] [concurrency] [+ Add tag]     │
├────────────────────────────────────────────────────────────┤
│  Notes:                                                    │
│  [ Use when discussing server-side Swift NIO details  ]    │
└────────────────────────────────────────────────────────────┘
```

---

## "Save to Glossary" Quick Flow

Triggered from the Context Tray right-click menu or from the Composer right-click on a segment.

```
┌────────────────────────────────────────┐
│  Save to Glossary                      │
├────────────────────────────────────────┤
│  Item: "SwiftNIO README"               │
│                                        │
│  Name:  [ SwiftNIO Overview     ]      │
│  Code:  [ @swiftnio              ]     │
│                                        │
│  Glossary:                             │
│  ● iOS Architecture Patterns           │
│  ○ Swift Performance                   │
│  ○ My Project                          │
│  ○ Default                             │
│  ─────────────────────────────         │
│  + Create new glossary…                │
│                                        │
│              [Cancel]  [Save]          │
└────────────────────────────────────────┘
```

---

## Context Capture — Extension UI

The Chrome extension popup gains a new **Capture** section below the existing connection status:

```
┌──────────────────────────────┐
│  ⚡ Vapor                    │
│  ● Connected                 │
├──────────────────────────────┤
│  SEND PROMPT                 │
│  [Send to ChatGPT ▼]         │
├──────────────────────────────┤
│  CAPTURE CONTEXT             │
│  [📄 Capture Article]        │
│  [🖼 Capture Images]         │
│  [✂️ Capture Selection]      │
│                              │
│  XHR Watch: OFF  [Enable]    │
├──────────────────────────────┤
│  Captured this session: 3    │
│  [View in Vapor]             │
└──────────────────────────────┘
```

- **Capture Article:** Runs Mozilla Readability on the current tab, sends the clean text body.
- **Capture Images:** Opens an image picker overlay on the page; the user clicks one or more images, then clicks "Send to Vapor".
- **Capture Selection:** Sends the current DOM text selection.
- **XHR Watch:** Enables interception of XHR/fetch responses matching patterns set in Vapor. Shows a live count of intercepted payloads.

---

## Compressed Output Format

When the user presses `⌘↩`, the Composer serialises all segments into a flat string and passes it through the existing `CompressionService`. The output rendered in the compressed preview (and copied to clipboard) looks like:

```
seniorSwiftdev reviewingNIOvsGCD focusmemoryalloc perf

[Context: SwiftNIO README — swift.org]
[Image: Architecture Diagram — cdn.example.com/diagram.png]

benchmarkdatabelow showmetricsalloc perfreqs

---
¹ swift.org — "Swift NIO" (2025-04-14)
² cdn.example.com/diagram.png — "Architecture Diagram"
```

- Text segments are compressed as normal.
- Context item text is included in the compression input (so the LLM gets the actual article text).
- Images are referenced by a `[Image: …]` placeholder in the compressed text (actual images are sent separately via the multi-modal API if applicable).
- Citations appear as a block after the `---` separator.

---

## Prompt History — Extended View

The existing `HistoryListView` is extended to show composed prompts in addition to plain prompts. A new toggle allows filtering:

```
  [All]  [Plain]  [Composed]

  ┌────────────────────────────────────────────────────────┐
  │ 🧩  "SwiftNIO vs GCD analysis" — 2025-04-14 10:32     │
  │     4 segments · 2 context items · ratio: 0.58        │
  │     Tags: swift · networking                           │
  │     [Re-use] [Copy compressed] [View] [★]             │
  └────────────────────────────────────────────────────────┘
  ┌────────────────────────────────────────────────────────┐
  │ 📝  "Explain async/await in Swift"  — 2025-04-13      │
  │     1 segment · ratio: 0.62                           │
  │     [Re-use] [Copy compressed] [View] [★]             │
  └────────────────────────────────────────────────────────┘
```

**Re-use:** Opens the `ComposedPrompt` in the Composer, restoring all segments (text is editable; context item links are resolved if the assets are still present, or shown as broken if evicted).

---

## Onboarding — First Use

The first time the user opens the Context Tray, a short onboarding overlay explains the workflow:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   📦  Context Management                                        │
│                                                                 │
│   Collect text, images, and data from any web page, then       │
│   weave them inline into your prompts — right here in Vapor.   │
│                                                                 │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐         │
│   │ 1. Capture  │ → │ 2. Compose  │ → │ 3. Compress │         │
│   │ Click the   │   │ Drag items  │   │ ⌘↩ to       │         │
│   │ extension   │   │ into your   │   │ compress +  │         │
│   │ Capture btn │   │ prompt      │   │ copy        │         │
│   └─────────────┘   └─────────────┘   └─────────────┘         │
│                                                                 │
│   💡 Tip: Use @ in the composer to insert glossary items.      │
│                                                                 │
│                              [Got it — let's go]               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Settings — Context Management Section

New section in `SettingsView`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Context Management
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [✓] Auto-vectorise captured items
  [✓] Show semantic suggestions while composing

  Citation format:      [URL only ▼]
  Blob storage limit:   [500 MB     ]  Used: 12 MB
  [Clear all captured items…]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Glossaries
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [Open Glossary Manager…]
  [Export Glossaries…]
  [Import Glossaries…]
```

---

## Additional Ideas

### Prompt Templates

Beyond glossaries, users could create **Prompt Templates** — skeletal prompts with named placeholder slots that glossary items or context captures snap into. For example:

```
You are a {{role}}.
Review the following {{artifact_type}}:

{{primary_context}}

Focus on: {{focus_keywords}}
```

The user fills placeholders by dragging glossary items or context captures onto them.

### Auto-Grouping Suggestion

After a session of capturing several items, Vapor can analyse entity overlap and suggest: "These 3 items all mention SwiftNIO — would you like to create a Glossary Item?" A non-intrusive toast or notification-centre notification surfaces this.

### Prompt Diff

When a user re-uses a `ComposedPrompt` and modifies it before compressing, Vapor could show a diff view: what changed since the last use, and how the compression ratio changed. This helps users understand which context items add the most token cost.

### Voice-Triggered Glossary Insertion

Integrate with the existing dictation pipeline: if the user says a registered short code (e.g., "at swift nio"), the system automatically inserts the corresponding `GlossaryItem` during transcription, similar to voice shortcuts on mobile.

### Context Item Expiry

Context items from XHR interception (API responses) can become stale quickly. Allow setting a per-item or per-source TTL. When an item expires, it is shown with a ⚠️ badge and the user is offered a one-click "Re-capture" option.

---

## Open UX Questions

1. **Tray position:** Left panel vs. bottom drawer vs. floating palette? Left panel maximises vertical text space in the composer; bottom drawer may feel more natural for media-heavy capture sessions.
2. **Segment granularity:** Should a single dictation session produce one segment, or should Vapor auto-split on natural pause boundaries? Finer segments give more precise reordering but create visual clutter.
3. **Image display in Composer:** Should images be shown inline at full thumbnail size, or should they always be collapsed to a small chip with an expand button? The latter keeps the composer compact.
4. **Glossary discoverability:** How do new users learn that `@` triggers autocomplete? Consider a subtle hint line at the bottom of the composer: *"Type @ to insert a glossary item"* that fades out after first use.
5. **XHR Interception consent:** Should Vapor display a per-domain confirmation dialog each time the user enables XHR watching, for transparency? This mirrors how browser extensions request permissions.
