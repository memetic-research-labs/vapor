# Vapor Browser Extension

Chrome extension for [Vapor](https://github.com/memetic-research-labs/comp-tok-stt) — injects compressed prompts directly into AI chat interfaces.

## Install

1. Open Chrome and go to `chrome://extensions/`
2. Enable **Developer mode** (top-right toggle)
3. Click **Load unpacked** and select this `vapor-extension` folder

## Configure

The extension requires an auth token to connect to the Vapor Mac app.

1. Open Vapor → **Settings** → **Browser** tab
2. Copy the **Bearer token** from the Authentication section
3. Click the Vapor extension icon in Chrome → click the **⚙ Settings** button
4. Paste the token → click **Save**
5. The status should change to **Connected**

**If the extension shows "Token mismatch":** The token in the extension is outdated. Repeat steps 1–4 above to copy the current token.

## Features

- **Capture Page** (`Cmd+Shift+C`): Captures the current page content and sends it to Vapor's context queue
- **Capture Selection**: Captures only the highlighted text
- **Prompt Injection**: Receives compressed prompts from Vapor and injects them into AI chat tabs
- **Research Interrogation**: Inspects pages for data sources (tables, XHR feeds, articles)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "No auth token" warning | Copy the token from Vapor Settings → Browser → Authentication |
| "Token mismatch" warning | The token was reset in Vapor — copy the new one from Settings |
| "Waiting for Vapor" | Make sure Vapor is running and browser integration is enabled in Settings |
| Badge shows "!" | Extension is disconnected — check that Vapor is running and the token matches |

## Test Connection

Click **Test Connection** in the extension popup (main view or Settings) to verify the token and connection are working.
