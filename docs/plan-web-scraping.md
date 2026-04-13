# Plan: Browser-Powered Web Scraping via Bidirectional Bridge

## Overview

Because Vapor already has a bidirectional communication channel to the Chrome extension (via the embedded NIO server + SSE), we can use that same channel to **instrument the browser as a scraping agent**. Vapor sends commands to the extension; the extension opens tabs, navigates, clicks, waits for page load, and extracts structured data — then sends the results back to Vapor as context that can be stitched into prompts or fed directly into an AI model.

This turns Vapor into a lightweight, Mac-native web research assistant: the user describes what they want in natural language, Vapor (optionally with an LLM) decomposes it into scraping commands, the browser executes them in the background, and the extracted data flows back into the prompt editor.

---

## User Stories

> As a developer, when I'm writing a prompt about a library I'm researching, I want to type "scrape the README from github.com/apple/swift-nio" and have the full README text appear in my prompt editor in seconds — so I can ask an LLM a specific question about it without leaving Vapor.

> As a technical writer, I want to say "open a Google search for 'SwiftNIO HTTP2', click the first three results, and give me the title + first paragraph from each" — all from within Vapor — so I can quickly gather reference material for a prompt.

> As a data analyst, I want to monitor an API's response JSON by intercepting XHR traffic on a web page and having Vapor receive the raw payloads as structured context I can query with an LLM.

---

## Architecture

```
┌──────────────────────────────┐   SSE: SCRAPE command      ┌────────────────────────────────┐
│        Vapor Mac App          │ ─────────────────────────► │  Chrome Extension (background) │
│                               │                             │                                │
│  ScrapeOrchestrator           │   POST /api/response        │  tab management                │
│  • buildScrapeJob(prompt)     │ ◄────────────────────────── │  navigation                    │
│  • receiveScrapeResult(data)  │                             │  XHR interception              │
│  • injectIntoEditor(result)   │                             │  DOM extraction                │
│                               │                             └──────────────┬─────────────────┘
│  ScrapeCache                  │                                            │
│  • store(job, result)         │                             executeScript  │
│  • retrieve(url)              │                                            ▼
│  • evict(olderThan: 1h)       │                             ┌────────────────────────────────┐
│                               │                             │    Content Script               │
└──────────────────────────────┘                             │   (scraper-agent.js)            │
                                                             │                                  │
                                                             │  • DOM serialisation             │
                                                             │  • article extraction            │
                                                             │  • link list                     │
                                                             │  • form fill + submit            │
                                                             │  • XHR listener                  │
                                                             └──────────────────────────────────┘
```

---

## Scrape Command Protocol

All commands are sent as SSE events on the existing `/api/stream` endpoint and acknowledged via POST to `/api/response`. Commands have a `jobId` field for correlation.

### Available Commands

#### `OPEN_URL`

Open a URL in a new background tab (or reuse an existing tab with that URL). Wait for `document.readyState === 'complete'` or a configurable timeout.

```json
{
  "type": "SCRAPE",
  "command": "OPEN_URL",
  "jobId": "job-001",
  "url": "https://github.com/apple/swift-nio",
  "waitForSelector": null,
  "timeout": 15000
}
```

#### `EXTRACT_TEXT`

Extract the main readable text from the active tab.

```json
{
  "type": "SCRAPE",
  "command": "EXTRACT_TEXT",
  "jobId": "job-001",
  "selector": null,
  "format": "markdown",
  "maxChars": 8000
}
```

`format` options: `"markdown"` (use Readability-style extraction), `"text"` (innerText), `"html"` (raw HTML, for downstream parsing).

#### `EXTRACT_LINKS`

Return all links from the page matching an optional CSS selector, with their text and href.

```json
{
  "type": "SCRAPE",
  "command": "EXTRACT_LINKS",
  "jobId": "job-001",
  "selector": "a[href]",
  "filter": "same-origin"
}
```

#### `CLICK`

Click a CSS selector on the active tab. Waits `postClickDelay` ms after click.

```json
{
  "type": "SCRAPE",
  "command": "CLICK",
  "jobId": "job-001",
  "selector": "button.submit",
  "postClickDelay": 1500
}
```

#### `FILL_AND_SUBMIT`

Fill a form field with a value and optionally submit the form (for search boxes).

```json
{
  "type": "SCRAPE",
  "command": "FILL_AND_SUBMIT",
  "jobId": "job-001",
  "inputSelector": "input[name='q']",
  "value": "SwiftNIO HTTP2 tutorial",
  "submitSelector": "input[type='submit']",
  "waitForNavigation": true
}
```

#### `WAIT_FOR_SELECTOR`

Wait until a CSS selector appears in the DOM (useful for SPAs that render asynchronously).

```json
{
  "type": "SCRAPE",
  "command": "WAIT_FOR_SELECTOR",
  "jobId": "job-001",
  "selector": "div.search-results",
  "timeout": 10000
}
```

#### `INTERCEPT_XHR`

Attach an XHR/fetch interceptor to the page. All matching responses are forwarded back to Vapor until `STOP_INTERCEPT` is received.

```json
{
  "type": "SCRAPE",
  "command": "INTERCEPT_XHR",
  "jobId": "job-001",
  "urlPattern": ".*api/completions.*",
  "captureMode": "response_json",
  "maxCaptures": 5
}
```

`captureMode` options:
- `"response_json"` — parse response body as JSON
- `"response_text"` — raw response text
- `"request_body"` — capture the request payload (useful for seeing what the page sends to an LLM API)
- `"both"` — request + response

#### `EXTRACT_IMAGES`

Find all images matching a selector and return their URLs and alt text (for future multimodal workflows).

```json
{
  "type": "SCRAPE",
  "command": "EXTRACT_IMAGES",
  "jobId": "job-001",
  "selector": "article img",
  "includeDataUrls": false
}
```

#### `CLOSE_TAB`

Close the scraping tab once the job is complete.

```json
{
  "type": "SCRAPE",
  "command": "CLOSE_TAB",
  "jobId": "job-001"
}
```

### Response Envelope

```json
{
  "type": "SCRAPE_RESULT",
  "jobId": "job-001",
  "command": "EXTRACT_TEXT",
  "success": true,
  "data": "…extracted text…",
  "metadata": {
    "url": "https://github.com/apple/swift-nio",
    "title": "GitHub - apple/swift-nio",
    "charCount": 4823,
    "extractedAt": 1712764800000
  },
  "error": null
}
```

---

## Mac App: `ScrapeOrchestrator`

```swift
@MainActor
@Observable
final class ScrapeOrchestrator {
    var jobs: [ScrapeJob] = []
    var scrapeCache: ScrapeCache

    private let bridge: BrowserBridge

    /// High-level: open URL, extract text, return result
    func fetchPage(url: URL, format: ScrapeFormat = .markdown) async throws -> ScrapeResult

    /// High-level: Google search → top N results → extract text from each
    func searchAndExtract(query: String, topN: Int = 3) async throws -> [ScrapeResult]

    /// High-level: intercept XHR on the currently active tab
    func interceptXHR(urlPattern: String, maxCaptures: Int) async throws -> [XHRCapture]

    /// Low-level: send arbitrary scrape command and await response
    func send(command: ScrapeCommand) async throws -> ScrapeResult

    /// Called by BrowserBridge when a SCRAPE_RESULT response arrives
    func handleResult(_ json: [String: Any])

    /// Inject result text into the prompt editor
    func injectIntoEditor(_ result: ScrapeResult, editorViewModel: EditorViewModel)
}
```

### Job Tracking

```swift
struct ScrapeJob: Identifiable {
    let id: String           // jobId
    let command: String
    let url: String?
    var status: ScrapeJobStatus  // .pending, .running, .completed, .failed
    var result: ScrapeResult?
    var startedAt: Date
    var completedAt: Date?
}

enum ScrapeJobStatus { case pending, running, completed, failed }
```

### Scrape Cache

```swift
actor ScrapeCache {
    private var entries: [URL: (result: ScrapeResult, cachedAt: Date)] = [:]
    private let ttl: TimeInterval = 3600  // 1 hour

    func store(url: URL, result: ScrapeResult)
    func retrieve(url: URL) -> ScrapeResult?
    func evict()     // remove entries older than ttl
}
```

Cache key is the normalised URL (stripped of tracking parameters). The cache avoids duplicate network activity when the user re-runs the same scrape in the same session.

---

## Chrome Extension: `scraper-agent.js`

The content script is injected into the scraping tab by the background script. It handles `EXTRACT_TEXT`, `EXTRACT_LINKS`, `CLICK`, `FILL_AND_SUBMIT`, `WAIT_FOR_SELECTOR`, and `EXTRACT_IMAGES` commands via `chrome.runtime.onMessage`.

### Readability-Based Article Extraction

For `EXTRACT_TEXT` with `format: "markdown"`, the script uses Mozilla's **Readability** algorithm (bundled with the extension as `lib/Readability.js`) to extract the main article text, stripping navigation, ads, and boilerplate. The extracted DOM is then converted to Markdown via a small `htmlToMarkdown()` utility.

```javascript
function extractMarkdown() {
  const doc = document.cloneNode(true);
  const reader = new Readability(doc);
  const article = reader.parse();
  if (!article) return { text: document.body.innerText, title: document.title };
  return {
    title: article.title,
    text: htmlToMarkdown(article.content),
    byline: article.byline,
    siteName: article.siteName,
  };
}
```

### XHR Interception

```javascript
function attachXHRInterceptor(urlPattern, captureMode, maxCaptures) {
  const re = new RegExp(urlPattern);
  let count = 0;

  const origFetch = window.fetch;
  window.fetch = async function(...args) {
    const response = await origFetch(...args);
    const url = typeof args[0] === 'string' ? args[0] : args[0]?.url;
    if (re.test(url) && count < maxCaptures) {
      count++;
      const clone = response.clone();
      clone.json().then(data => {
        chrome.runtime.sendMessage({
          type: 'XHR_CAPTURE',
          url,
          data,
          capturedAt: Date.now()
        });
      }).catch(() => {});
    }
    return response;
  };

  // Also patch XMLHttpRequest for legacy pages
  const origXHROpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    if (re.test(url)) {
      this.addEventListener('load', function() {
        if (count >= maxCaptures) return;
        count++;
        try {
          const data = JSON.parse(this.responseText);
          chrome.runtime.sendMessage({ type: 'XHR_CAPTURE', url, data, capturedAt: Date.now() });
        } catch {}
      });
    }
    origXHROpen.call(this, method, url, ...rest);
  };
}
```

---

## Background Script Changes

The background script gains a `runScrapeJob(command)` function that:

1. Calls `chrome.tabs.create({ url, active: false })` for `OPEN_URL`.
2. Waits for `chrome.tabs.onUpdated` to fire with `status === 'complete'`.
3. Calls `chrome.scripting.executeScript` to inject `scraper-agent.js`.
4. Sends the command via `chrome.tabs.sendMessage` and waits for the reply.
5. POSTs the reply as a `SCRAPE_RESULT` to `/api/response`.
6. Optionally closes the tab after the job sequence is done.

```javascript
async function runScrapeJob(job) {
  const tab = await openOrReuseTab(job.url);
  await waitForLoad(tab.id);
  await injectScraper(tab.id);
  const result = await chrome.tabs.sendMessage(tab.id, job);
  await postResponse({ type: 'SCRAPE_RESULT', jobId: job.jobId, ...result });
}
```

---

## Vapor UI: Scrape Panel

### Trigger

In the expanded view toolbar, a new "🔍 Research" button opens an inline scrape input below the editor (similar to the existing compressed-preview area). Alternatively, typing `//scrape <url>` as the first line of a prompt triggers an automatic fetch.

### Inline Research Panel

```
┌────────────────────────────────────────────────────────┐
│  🔍 Web Research                              [✕ Close] │
├────────────────────────────────────────────────────────┤
│  URL or search query:                                   │
│  [ https://docs.swift.org/swift-book/   ] [Fetch]       │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  ✓  Swift Book — The Swift Programming Language  │  │
│  │     4,200 chars · cached 3 min ago               │  │
│  │     [Insert into prompt]  [Copy]  [Discard]      │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  Recent: swift-nio README · anthropic/sdk · perplexity  │
└────────────────────────────────────────────────────────┘
```

"Insert into prompt" appends the scraped content to the editor with a Markdown header:

```markdown
---
Source: https://docs.swift.org/swift-book/
Fetched: 2025-04-12

[main article text here]
---
```

### Search Mode

When the user types a query (no URL), Vapor sends a `FILL_AND_SUBMIT` command targeting Google search, waits for results, extracts the first N result links with `EXTRACT_LINKS`, and then fans out parallel `OPEN_URL` + `EXTRACT_TEXT` jobs for each link. Results are shown as a list in the research panel with checkboxes; the user picks which pages to insert into the prompt.

---

## Advanced Use Case: LLM-Directed Scraping

The user types a high-level question in the Vapor prompt editor, then invokes `⌘⇧R` ("Research this"). Vapor:

1. Sends the user's question to the configured LLM compressor with a **research decomposition prompt**:
   > "Given this question, produce a JSON array of URLs or search queries needed to answer it."
2. Receives a list of URLs/queries.
3. Dispatches parallel scrape jobs to the browser via SSE.
4. Collects results, compresses each one (using the same compression pipeline), and assembles a context block.
5. Inserts the context block above the original question in the editor.
6. Compresses the whole thing again before copying.

This is a lightweight agentic loop entirely within the Vapor + Chrome extension pair — no external APIs are required beyond the LLM for step 1.

---

## XHR Monitor: Passive Network Listener

A dedicated "Network Monitor" mode lets the user observe what data flows through the page they are on — useful for:

- Capturing the exact request that a web AI sends to its backend (to replicate it directly)
- Detecting authentication headers or tokens in requests so sensitive values can be redacted while debugging request shapes and integration issues
- Observing structured data returned by SPAs for scraping

In this mode, the extension intercepts all XHR/fetch traffic matching a user-specified URL pattern. Captured payloads appear in a live log panel in Vapor, colour-coded by content type (JSON, text, binary). The user can click any captured entry to insert it into the prompt editor as a code block.

---

## Security and Privacy Considerations

| Concern | Mitigation |
|---|---|
| Scraping pages the user hasn't consented to | Commands can only be triggered by the Vapor app (localhost server); there is no way for a web page to inject scrape commands |
| XHR interception exposing sensitive data | The interceptor is only active when the user explicitly enables it for a specific tab; it is never persistent across sessions |
| Cached data leaking between users | Cache is in-memory (not persisted to disk) by default; optionally persisted to a sandboxed app-group container |
| Extension accessing arbitrary pages | `host_permissions` in Manifest V3 requires the user to grant per-site access at install time; scraping tabs are opened programmatically and closed after extraction |
| Replaying captured credentials | Vapor warns the user when captured XHR data appears to contain auth tokens/API keys |
| Rate limiting / ToS compliance | No rate-limit enforcement in v1; the user is responsible for complying with the terms of service of scraped sites |

---

## Implementation Phases

### Phase 1 — Basic URL Fetch

- [ ] Add `OPEN_URL` + `EXTRACT_TEXT` commands to SSE protocol
- [ ] Create `scraper-agent.js` content script with Readability bundled
- [ ] Handle scrape commands in `background.js` (tab create, wait, inject, extract, POST result)
- [ ] Create `ScrapeOrchestrator.swift` with `fetchPage(url:format:)`
- [ ] Add "🔍 Research" button and inline research panel to `ToolbarView`
- [ ] Manual test: fetch `https://github.com/apple/swift-nio` and insert README into editor

### Phase 2 — Link Extraction and Search

- [ ] Add `EXTRACT_LINKS`, `FILL_AND_SUBMIT`, `WAIT_FOR_SELECTOR` commands
- [ ] Implement `searchAndExtract(query:topN:)` in `ScrapeOrchestrator`
- [ ] Search mode in research panel
- [ ] Multi-result checkbox UI

### Phase 3 — XHR Interception

- [ ] Add `INTERCEPT_XHR` command + `scraper-agent.js` interceptor
- [ ] Network monitor panel in Vapor
- [ ] Auth token detection warning

### Phase 4 — LLM-Directed Scraping

- [ ] Research decomposition prompt template
- [ ] `⌘⇧R` shortcut → LLM query → parallel scrape jobs → context assembly
- [ ] Context block formatting in editor

### Phase 5 — Image Extraction

- [ ] Add `EXTRACT_IMAGES` command
- [ ] Integrate with Screenshot Awareness feature (see `docs/plan-screenshot-awareness.md`) so scraped images appear in the thumbnail strip

---

## Files to Create

| File | Purpose |
|---|---|
| `vapor-extension/content-scripts/scraper-agent.js` | DOM extraction, XHR interception, form fill |
| `vapor-extension/lib/Readability.js` | Mozilla Readability (bundled, MIT licence) |
| `vapor-extension/lib/readability-utils.js` | `htmlToMarkdown()` helper |
| `Vapor/Vapor/Services/ScrapeOrchestrator.swift` | Job dispatch, result collection, cache |
| `Vapor/Vapor/Services/ScrapeCache.swift` | In-memory TTL cache for scrape results |
| `Vapor/Vapor/Models/ScrapeJob.swift` | Job + result data models |
| `Vapor/Vapor/Views/ResearchPanelView.swift` | Inline research panel SwiftUI view |

## Files to Modify

| File | Change |
|---|---|
| `vapor-extension/background.js` | Handle `SCRAPE` SSE commands; `runScrapeJob()` orchestration; `XHR_CAPTURE` message relay |
| `vapor-extension/manifest.json` | Add `"tabs"` and `"scripting"` permissions (already present); ensure `host_permissions` covers scraping targets |
| `Vapor/Vapor/Services/BrowserBridge.swift` | Route `SCRAPE_RESULT` and `XHR_CAPTURE` responses to `ScrapeOrchestrator` |
| `Vapor/Vapor/Views/ToolbarView.swift` | Add Research button; show active job count badge |
| `Vapor/Vapor/VaporApp.swift` | Instantiate and inject `ScrapeOrchestrator` |

---

## Acceptance Criteria

- [ ] User can type a URL in the research panel and receive extracted article text within 15 seconds
- [ ] Extracted text is Markdown-formatted with source URL header
- [ ] Cache prevents re-fetching the same URL within 1 hour
- [ ] Search query triggers a Google search, extracts top 3 result URLs, and presents them for selection
- [ ] XHR interception captures fetch and XMLHttpRequest traffic matching a user-specified pattern
- [ ] Scraping tabs are opened in the background and closed after extraction (no visible tab flicker for user)
- [ ] LLM-directed scraping (`⌘⇧R`) produces a context block in under 30 seconds for a typical query
- [ ] Auth token warning fires when captured XHR data contains known token patterns
- [ ] All scraping activity is logged in the Vapor console / OSLog for debugging
- [ ] Disabling browser integration disables all scraping functionality cleanly
