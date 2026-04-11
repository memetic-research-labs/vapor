# Window Management

Vapor uses a single floating window that resizes between two views: compact (pill) and full editor. The window stays above all other windows and joins all Spaces, so it's always accessible.

## Compact View (Pill)

The compact view is a 320 x 200 floating window with:
- A title bar showing "Vapor"
- A live text editor (editable — you can type or dictate)
- A status bar (Ready, Listening, Compressing, Copied)
- Control buttons (Compress, Copy, Clear, Help, Expand)

This is the default working view. Most workflows happen here: dictate, compress, paste.

**Screenshot needed:** `screens/pill-with-controls.png` — the pill view showing all control buttons in the bottom bar.

## Full Editor View

The full editor is a 500 x 400 window with:
- A title bar showing "Vapor"
- A toolbar with Compress & Copy, Copy Original, Clear, Settings, and Minimize buttons
- A full-size text editor with the cycling color glow border
- Token count stats bar (shown after first compression)
- Compressed preview panel (shown after first compression)

Use this when you need more editing space or want to see the compression output.

**Screenshot needed:** `screens/expanded-with-preview.png` — the full editor showing text, stats bar, and compressed preview.

## Switching Between Views

| Action | Shortcut | Notes |
|---|---|---|
| Toggle between compact and full | `⌘ \` | Works in either view |
| Minimize to compact | `Escape` | Works in full editor only |
| Minimize to compact | Click ↙ button in toolbar | Full editor only |
| Expand to full | Click ↗ button in pill controls | Pill only |

### Animation

The window smoothly animates between sizes over 0.25-0.3 seconds. It grows from and shrinks to its current position — no jumping or repositioning.

## Focus from Any App

Press `⌃ ⌥ Space` (Control + Option + Space) from **any app** to bring Vapor to the front and give it keyboard focus. This is a global hotkey that works everywhere — even when Vapor is behind other windows or on a different Space.

The global hotkey:
- **Focuses** the window (makes it key and activates the app)
- **Does not change** the window size — it stays in whatever view you left it in
- Can be **customized** in Settings > Global Hotkey

> This is separate from `⌘ \` which toggles the view size. `⌃ ⌥ Space` is for summoning Vapor; `⌘ \` is for resizing it.

**Screenshot needed:** `screens/focus-from-other-app.png` — a screenshot showing Vapor floating above another app (e.g., a terminal) after pressing ⌃⌥Space.

## Window Behavior

### Always on Top

Vapor's window uses `.floating` level, which means it stays above normal windows. This is intentional — Vapor is a tool you use alongside other apps, not an app you switch to and from.

### All Spaces

Vapor joins all Spaces (virtual desktops). No matter which Space you're on, Vapor is there.

### Moveable

Both views can be dragged by the title bar. The window remembers its position between launches.

### No Dock Icon (Menu Bar App)

Vapor runs as a menu bar app with a waveform icon in the system menu bar. It does not show a Dock icon.

**Screenshot needed:** `screens/menu-bar-icon.png` — the macOS menu bar showing Vapor's waveform icon.

## Editor Glow Border

When the text editor is focused, a subtle color-cycling glow border appears around the editor area. The colors cycle through 4 shades from the Vapor app icon:

1. Blue → Cyan → Purple → Magenta → Blue (5 second cycle)

During dictation, the border:
- Becomes thicker (4px instead of 2px)
- Pulses in opacity with your voice level (VU meter effect)
- Continues cycling through colors

When the editor loses focus (you click outside Vapor or switch to another app), the glow disappears.

**Screenshot needed:** `screens/editor-glow-idle.png` — the editor with the subtle cycling glow border (capture mid-cycle showing purple/cyan).

**Screenshot needed:** `screens/editor-glow-dictating.png` — the editor during dictation with the thicker pulsing border.
