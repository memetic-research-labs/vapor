# Voice Dictation

Vapor uses Apple's on-device speech recognition to transcribe your voice in real-time. All processing happens locally on your Mac — no audio is sent to the cloud.

## How to Dictate

**Hold the Fn key** to start dictating. **Release the Fn key** to stop.

That's it. There's no toggle, no click-to-start, no mode to enter. Hold Fn = recording. Release Fn = done.

**Screenshot needed:** `screens/pill-dictating.png` — the pill view during dictation showing the red mic icon, audio level bars, "Listening" status, and the glowing border.

## What Happens During Dictation

1. The status bar shows **"Listening"** with a red microphone icon and audio level bars
2. The editor glow border **pulses with your voice** — louder speech makes it brighter (like a VU meter)
3. Text appears in the editor **in real-time** as you speak
4. The editor **auto-scrolls** to keep the latest text visible

## What Happens When You Release Fn

1. The current transcription is **committed as final** — no text is lost
2. A **space is automatically inserted** between the previous text and the next dictation segment
3. The status returns to **"Ready"**
4. The editor glow returns to its **idle cycling animation**

## Multiple Dictation Segments

You can dictate in multiple segments by pressing and releasing Fn repeatedly. Vapor handles the transitions intelligently:

### Auto-Space
If the existing text doesn't end with whitespace, Vapor inserts a space before the new segment. So "write a python script" + (release) + (hold Fn) + "that uses pandas" becomes "write a python script that uses pandas" — not "write a python scriptthat uses pandas".

### Smart Capitalization
Apple's speech recognizer capitalizes the first word of each new recognition session. Vapor detects this and adjusts:

- **Continuing mid-sentence**: The first character is lowercased. "write a script" + "That uses pandas" becomes "write a script that uses pandas"
- **After sentence-ending punctuation** (`. ! ? :`): The capital is preserved. "Write a script." + "Then test it" stays "Write a script. Then test it"
- **Empty editor**: The first word keeps its original case.

## Microphone Button

Clicking the microphone icon in the toolbar does **not** start dictation. It shows a toast message: "Hold the Fn key to dictate, release to stop." This prevents accidentally leaving the microphone on.

## Permissions

Vapor requires two permissions for dictation:

1. **Microphone Access** — to capture audio from your microphone
2. **Speech Recognition** — to transcribe audio to text using Apple's on-device recognizer

If either permission is denied, Vapor shows a permissions overlay with instructions to grant access in System Settings.

**Screenshot needed:** `screens/permissions-overlay.png` — the permissions overlay view with the microphone and speech recognition status.

### Resetting Permissions

If microphone access gets stuck in a denied state, you can reset it from Terminal:

```bash
tccutil reset Microphone lol.mrl.app.Vapor
```

Then relaunch Vapor — the system permission prompt will appear again.

## Technical Notes

- Dictation uses `SFSpeechRecognizer` with `SFSpeechAudioBufferRecognitionRequest`
- Audio is captured via `AVAudioEngine` at the default sample rate
- All speech recognition happens on-device — the recognizer uses the `on-device` mode
- The audio engine starts when Fn is pressed and stops when Fn is released
- Partial transcription results update the editor in real-time; final results commit the text
- The Fn key is monitored via `NSEvent.addGlobalMonitorForEvents` and `addLocalMonitorForEvents`
