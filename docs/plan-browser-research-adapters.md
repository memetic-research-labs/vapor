# Plan: Browser Research Adapters

## Purpose

Vapor already has a bidirectional browser bridge that can:

- send commands from the app to the extension over SSE
- inject scripts into authenticated browser tabs
- post structured data back to Vapor over local HTTP

The next step is to evolve that bridge from simple page capture into a **site-aware research extraction system**.

The first concrete use case is Amazon product reviews:

- open a product page
- extract all reviews atomically
- ingest each review as its own searchable record
- vectorize the review corpus
- run retrieval and summarization over the reviews for that product

This should not be built as a one-off Amazon scraper. It should be designed as a reusable adapter system for structured, site-specific research extraction.

## Product Framing

This feature family is best understood as:

### Browser Research Adapters

Adapters that let Vapor customize how it extracts, structures, and indexes information from specific websites.

Examples:

- Amazon product reviews
- Reddit threads and comments
- GitHub pull request review comments
- YouTube transcripts and comments
- Hacker News or forum discussion threads
- e-commerce Q&A systems
- authenticated internal dashboards and tools visible only in the browser

## Core Principle

Do not model these extractions as one giant captured page blob.

Instead, model them as:

- one **Research Collection**
- many **atomic extracted records**

For Amazon:

- collection = one product review corpus
- records = individual reviews

That is what makes vector search, filtering, clustering, and prompt-time analysis actually useful.

## Current Bridge Capability

The existing browser architecture already provides the right transport skeleton.

### App -> Extension

Via SSE on `/api/stream`, Vapor can already send structured commands such as:

- `QUERY_TABS`
- `VERIFY_TARGET`
- `OPEN_TAB`
- `ACTIVATE_PICKER`

### Extension -> App

Via authenticated HTTP POST, the extension can already send structured JSON payloads back to Vapor through:

- `/api/response`
- `/api/context`

### Why this is enough to build on

That means the browser stack already supports the core shape needed for a research extraction workflow:

1. Vapor sends an extraction command
2. the extension activates a site adapter in the current authenticated tab
3. the adapter extracts structured data in batches
4. the extension POSTs progress and records back to Vapor
5. Vapor persists and indexes the extracted corpus

## Proposed Architecture

## 1. Research Job

Introduce a richer extraction layer above one-shot context capture.

A `ResearchJob` represents one structured extraction workflow initiated by Vapor.

Suggested fields:

- `jobId`
- `jobType`
- `targetURL`
- `siteAdapter`
- `options`
- `status`
- `progress`
- `recordCount`
- `startedAt`
- `completedAt`
- `error`

Examples of `jobType`:

- `amazonReviews`
- `redditThread`
- `githubPRComments`

### Why it is needed

The current `CONTEXT_CAPTURE` flow is built around a single item payload. This new feature needs:

- progress tracking
- pagination
- chunked record delivery
- completion/failure states
- cancellation

## 2. Site Adapter

Implement site-specific extraction logic inside the extension as a pluggable adapter system.

Each adapter should know how to:

- recognize whether it can handle a URL
- discover the extraction scope
- collect structured records
- paginate or scroll for additional data
- emit records back to Vapor in batches

### Conceptual interface

```text
canHandle(url)
discoverScope()
run(jobConfig, emitBatch)
cancel()
```

### Initial adapters

- `amazon-reviews`

Future adapters:

- `reddit-thread`
- `github-pr-comments`
- `youtube-comments`
- `forum-thread`

### Recommendation

Do not hardcode this logic directly inside `background.js`. Add an adapter registry and keep `background.js` focused on transport, orchestration, and messaging.

## 3. Extraction Strategy

For complex sites like Amazon, the adapter should support both DOM-driven extraction and limited network-aware extraction.

### DOM-first

Use the rendered page and review UI for the baseline extraction path:

- review title
- review body
- author
- star rating
- date
- verified purchase
- helpful count
- variant / format metadata where visible

### Network-aware second

Allow adapters to observe or reuse relevant site responses when that is materially better than scraping rendered DOM.

This can help with:

- reducing DOM brittleness
- faster pagination
- accessing structured metadata not visibly rendered

### Recommendation

Do not start with general-purpose arbitrary network interception.

Start with:

- adapter-scoped network awareness
- only for requests/responses relevant to the active research job

## App / Extension Protocol Changes

## App -> Extension Commands

Introduce browser research commands alongside the existing prompt/browser commands.

Suggested commands:

- `START_RESEARCH_JOB`
- `CANCEL_RESEARCH_JOB`
- `QUERY_SITE_CAPABILITIES`

Example:

```json
{
  "type": "START_RESEARCH_JOB",
  "jobType": "amazonReviews",
  "jobId": "rev-123",
  "url": "https://www.amazon.com/...",
  "options": {
    "maxPages": 50,
    "captureMode": "networkPreferred"
  }
}
```

## Extension -> App Responses

Suggested response events:

- `RESEARCH_JOB_STARTED`
- `RESEARCH_JOB_PROGRESS`
- `RESEARCH_RECORD_BATCH`
- `RESEARCH_JOB_COMPLETED`
- `RESEARCH_JOB_FAILED`

This is better than trying to overload the current one-item `/api/context` ingestion model.

## Vapor Data Model

## 1. ResearchCollection

Represents the extracted corpus for one site entity.

For Amazon reviews, one collection should represent one product review corpus.

Suggested fields:

- `id`
- `collectionType`
- `externalKey` (for Amazon: ASIN)
- `sourceURL`
- `title`
- `siteName`
- `metadataJSON`
- `capturedAt`
- `lastUpdatedAt`
- `recordCount`

## 2. ResearchRecord

Represents one atomic normalized extracted record.

For Amazon, one record represents one review.

Suggested fields:

- `id`
- `collectionID`
- `recordType`
- `externalID`
- `title`
- `body`
- `author`
- `rating`
- `createdAt`
- `metadataJSON`

Suggested Amazon review metadata inside `metadataJSON`:

- verified purchase
- helpful votes
- variant / style / size / color
- locale / market
- adapter version

## 3. Embeddings

Each record should be vectorized independently.

For Amazon, that means one embedding per review.

Embedding input should combine:

- review title
- rating
- body
- variant if useful

Suggested namespaced IDs:

- `review:<collectionID>:<reviewID>`

### Why per-record vectorization matters

This enables:

- semantic search over reviews
- clustering by theme
- retrieval for prompt-time analysis
- subsetting by metadata before vector search

## How This Fits with ContextItem

Do not force all extracted review rows directly into `ContextItem`.

`ContextItem` is becoming the user-facing durable artifact model. Review rows are better treated as structured research atoms.

Recommended relationship:

- optional summary `ContextItem` for the overall collection
- structured review records stored adjacent to, not inside, the context-item model

That keeps the system cleaner and avoids polluting the main context tray with thousands of records.

## UX Recommendation

This should not feel like generic page capture.

It should feel like a site-specific research tool.

## Suggested user flow

1. user opens an Amazon product page in Chrome
2. Vapor sees the active page is compatible with an adapter
3. Vapor offers an action such as:
   - `Research This Page`
   - `Extract Reviews`
4. Vapor starts a research job
5. progress appears in the status bar / activity log
6. once complete, the extracted review corpus is searchable and analyzable inside Vapor

## Suggested UI surfaces

### Main app action

- `Research This Page`
- if site capability is known, also show site-specific label like `Extract Amazon Reviews`

### Collection browser

Eventually, these collections should appear in a browser/explorer surface where the user can:

- search within one collection
- filter by structured metadata
- run semantic search over records
- summarize selected subsets

## Amazon Reviews: First Adapter

## Phase 1 scope

The first adapter should target Amazon product reviews only.

### Extracted data

- product title
- ASIN
- review entries
- review title
- review body
- author
- rating
- date
- verified purchase
- helpful votes
- variant/format when available

### Adapter controls

Start small.

Recommended first version:

- one-click extraction from the active product page
- simple internal options, but no user-facing pre-run configuration yet

This keeps v1 simple while leaving room for future options such as:

- max pages
- sort mode
- rating filters

## Why this is powerful

Once extracted, a user should be able to ask Vapor things like:

- find the most common complaints in 1-star reviews
- summarize recurring praise in 5-star reviews
- compare comments about durability vs comfort
- cluster complaints about battery life
- identify outlier or suspicious review language

## Other Strong Use Cases

This architecture generalizes well beyond Amazon.

### GitHub PRs

- extract review comments and discussion
- vectorize each comment
- search for recurring blockers, concurrency issues, test feedback, naming discussions

### Reddit threads

- extract post and comments
- vectorize comments atomically
- cluster opinions and themes

### YouTube

- transcript segments
- comments
- theme extraction across audience feedback

### Forums / Hacker News / Discourse

- flatten discussions into atomic comment records
- preserve parent references in metadata

### Other review systems

- Yelp
- Airbnb
- App Store reviews
- product Q&A systems

### Internal authenticated tools

This is one of the strongest advantages of the browser-based architecture.

The extension already runs in the user’s authenticated browser session, which means adapters can work on:

- internal dashboards
- support systems
- back-office tools
- private SaaS pages

without separately recreating login/session logic inside Vapor.

## Risks and Constraints

### Site brittleness

DOM changes will break brittle site scrapers.

That is why the adapter model matters.

### Network capture scope

General arbitrary network interception is too broad and messy as a first abstraction.

Adapter-scoped network awareness is safer and easier to maintain.

### Volume

A large review corpus can be substantial.

Need:

- chunked ingestion
- progress
- cancellation
- dedupe/update logic

### Dedupe and updates

If the same product is re-extracted:

- merge on external review ID where available
- update collection metadata
- avoid duplicate review records

### Terms / ethics

This should remain clearly framed as:

- user-initiated extraction
- from the user’s own browser session
- for local analysis/research

## Recommended Implementation Order

### Phase A: Protocol and job foundation

- add research-job command/response types
- add progress and completion messaging
- add adapter registry structure in the extension

### Phase B: Amazon reviews adapter

- recognize Amazon product pages
- extract reviews with pagination
- normalize and emit review batches back to Vapor

### Phase C: Vapor structured storage

- add `ResearchCollection`
- add `ResearchRecord`
- add review-record vectorization
- add dedupe/update behavior

### Phase D: Collection analysis UI

- browse collections
- search within one collection
- filter by rating/metadata
- semantic search over extracted records
- summarize subsets

### Phase E: Additional adapters

- Reddit
- GitHub
- forums
- other review sites

## Recommendation Summary

Build this as:

- site adapter -> research job -> research collection -> atomic records -> vectorized analysis

Do **not** build it as:

- one giant captured page blob

That distinction is what turns this from a one-off scraper into a durable browser-powered research platform.
