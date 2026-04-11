# Getting Started with Vapor

Vapor is a macOS app for voice-to-text dictation and AI-powered prompt compression. It floats above all your windows so you can dictate prompts and paste them into any app — your terminal, an AI chat, a code editor, or anywhere else.

## Requirements

- macOS 26.0 (Tahoe) or later
- Apple Silicon Mac (M1 or later recommended)
- Apple Intelligence enabled (for Foundation Models compression)
- Microphone access
- Speech Recognition access

## First Launch

When you first open Vapor, macOS will ask for two permissions:

1. **Microphone Access** — Vapor needs this to hear your voice during dictation. Click "Allow" when prompted.
2. **Speech Recognition** — Vapor uses Apple's on-device speech recognizer to transcribe your words. Click "Allow" when prompted.

> If you accidentally denied a permission, go to **System Settings > Privacy & Security > Microphone** (or Speech Recognition) and enable Vapor.

**Screenshot needed:** `screens/permissions-prompt.png` — the macOS microphone permission dialog with Vapor's name.

## The Two Views

Vapor has two modes:

### Compact View (Pill)

A small floating window (320 x 200) with:
- A live text editor at the top
- A status bar showing the current state (Ready, Listening, Compressing, Copied)
- Control buttons at the bottom (Compress, Copy, Clear, Help, Expand)

This is where you'll spend most of your time. Dictate, compress, paste.

**Screenshot needed:** `screens/pill-view-idle.png` — the pill view in idle state with some text.

### Full Editor View

A larger window (500 x 400) with:
- A toolbar with all controls
- A full-size text editor
- Token count stats bar
- Compressed preview panel

Use this when you want more editing space or need to see the compression output side-by-side.

**Screenshot needed:** `screens/expanded-view.png` — the full editor with toolbar, text, and compressed preview.

### Switching Between Views

| Action | How |
|---|---|
| Compact → Full | Click the expand button (↗) in the pill, or press `⌘ \` |
| Full → Compact | Click the minimize button (↙) in the toolbar, press `Escape`, or press `⌘ \` |
| Focus from any app | Press `⌃ ⌥ Space` (Control + Option + Space) |

## Quick Workflow

1. Press `⌃ ⌥ Space` to focus Vapor from any app
2. Hold `Fn` to dictate your prompt
3. Release `Fn` when done
4. Press `⌘ ↩` to compress and copy to clipboard
5. Switch to your target app and press `⌘ V` to paste

That's it. Your prompt is compressed and ready to use.

## Next Steps

- [Voice Dictation](voice-dictation.md) — learn how dictation works
- [Prompt Compression](prompt-compression.md) — understand how compression works
- [Keyboard Shortcuts](keyboard-shortcuts.md) — see all available shortcuts
- [Settings](settings.md) — configure compression backends and preferences
