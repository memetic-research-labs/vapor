# Plan: Browser Research Sources

## Purpose

Vapor's browser bridge should evolve beyond one-shot page capture and beyond purely curated site adapters into a **browser-native research source system**.

The idea is:

- let the user choose a browser tab to interrogate
- inspect what the page already exposes through DOM, structured JSON, tables, images, and observed XHR/fetch feeds
- allow the user to prompt over that data temporarily
- allow the user to extract that data into durable collections of atomic records
- support both curated adapters and later user-defined sources

This document complements `docs/plan-browser-research-adapters.md`.

That earlier document defines the curated adapter architecture. This document generalizes the system so Vapor can eventually support:

- curated site adapters
- user-defined DOM/network extraction recipes
- enterprise-specific authenticated data sources
- prompt-assisted source generation and mapping

Related design doc:

- `docs/plan-browser-research-adapters.md` focuses on the curated adapter architecture and the Amazon-reviews-first extraction path that this broader source model builds on.

## Product Framing

This feature family should be thought of as:

## Browser Research Sources

A browser research source is any structured or semi-structured data source available in an authenticated browser tab that Vapor can inspect, preview, query, or extract.

Examples:

- visible DOM content
- repeated DOM record structures
- embedded JSON and JSON-LD blobs
- observed XHR/fetch responses
- table-like page structures
- images/media payloads
- curated site-specific extraction workflows
- user-defined enterprise API sources

The browser is not only a capture surface. It becomes a **research interrogation surface**.

## Core Principles

### 1. Interrogate first, extract second

Do not force users to run a scraper or adapter blindly.

The system should first surface what kinds of data are available on the page.

### 2. Curated adapters are one kind of source, not the whole system

An Amazon reviews adapter is valuable, but it is one example of a more general idea.

The system should distinguish between:

- discovered sources
- curated adapters that operate on them
- user-defined sources that can later be saved and reused

### 3. Build around atomic records, not giant blobs

Whenever possible, extracted data should become:

- one **Research Collection**
- many **atomic Research Records**

That supports search, filtering, vectorization, and traceable prompt-time reasoning.

### 4. Browser context is the advantage

The extension already runs inside the user's authenticated browser session.

That means Vapor can leverage:

- live page state
- DOM
- cookies/session context
- requests the page already makes
- internal/private app surfaces only visible in the browser

### 5. This is not a DevTools clone

The goal is not to reproduce browser developer tools.

The goal is to help the user answer research questions such as:

- what data is available on this page?
- which source is the useful one?
- what can I prompt over immediately?
- what should become a durable collection?

## Relationship to Browser Research Adapters

`docs/plan-browser-research-adapters.md` describes the curated adapter architecture.

This document expands the idea by separating:

- **Research Sources**: what data is available
- **Research Adapters**: how to extract/normalize it
- **Research Jobs**: how the extraction runs

In other words:

- a source is a discovered data surface
- an adapter is one way of turning that source into a useful corpus

## User Experience

## Entry Flow

### Step 1: Choose a tab to interrogate

Use a flow similar to the current browser target UI.

The user should be able to:

- open `Research This Page`
- filter browser tabs
- choose the tab to interrogate

This keeps the browser research system consistent with the existing bridge model.

### Step 2: Open an interrogation workspace

After selecting a tab, Vapor should open a dedicated interrogation workspace for that tab.

This workspace should answer:

- what does this page contain?
- what structured sources are available?
- what curated adapters apply?
- what can I prompt over or extract?

### Step 3: Surface available sources

The workspace should display discovered sources such as:

- DOM summary/content
- structured JSON candidates
- table/repeated-record candidates
- observed XHR/fetch feeds
- image/media sources
- suggested curated adapters

### Step 4: Let the user choose an action

For any surfaced source, the user should be able to:

- inspect it
- prompt over it temporarily
- extract it into a durable collection
- run a curated adapter over it
- save it as a reusable source later

## Interrogation Workspace

This workspace should be a research-oriented browser inspection UI, not a raw developer tool.

## Recommended Layout

### Left Column: Source Inventory

A navigable list of available sources in the selected tab.

Suggested sections:

- Suggested Adapters
- Page Summary
- DOM Content
- Structured JSON
- Tables
- Observed XHR / Fetch
- Images / Media
- Saved / Custom Sources later

Each source row should show:

- source type
- label
- rough record estimate if known
- freshness/activity signal
- confidence or source quality where applicable

### Main Preview Pane

Shows an inspection-friendly preview of the selected source.

Examples:

- DOM summary preview
- sample JSON payload
- table preview
- list of observed endpoints
- sample adapter-emitted records

The point is not just to inspect raw bytes. The point is to help the user decide whether this source is worth prompting over or extracting.

### Action Surface

For the selected source, Vapor should offer actions such as:

- `Prompt Over This`
- `Extract as Collection`
- `Run Curated Adapter`
- `Save as Source` later
- `Watch Live` later
- `Configure Mapping` later

In v1 this can be a toolbar or action strip rather than a full right inspector.

## Source Types

The system should support a small set of source kinds.

### 1. DOM Source

Structured or semi-structured content extracted from the visible or rendered page.

Examples:

- article content
- product review cards
- forum replies
- repeated result rows

### 2. Structured JSON Source

Structured data embedded in the page.

Examples:

- `application/ld+json`
- global bootstrapped page state
- embedded page config blobs

### 3. Table Source

Visible tabular or repeated structured rows that are better handled as a row set than as a page blob.

Examples:

- enterprise dashboards
- product specs tables
- issue lists

### 4. XHR Feed Source

An observed or promoted XHR/fetch response stream relevant to the page.

Examples:

- review payloads
- comment feeds
- support ticket lists
- report data

### 5. Image / Media Source

Images or media discovered on the page or returned through relevant network responses.

This should be included in the architecture but not necessarily in the first implementation wave.

### 6. Curated Adapter Source

A curated site-aware adapter that can extract a useful collection from one or more other sources.

Examples:

- Amazon Reviews Adapter
- Reddit Thread Adapter
- GitHub PR Comments Adapter

## ResearchSource Model

`ResearchSource` should be more general than a curated adapter.

Suggested conceptual fields:

- `sourceId`
- `sourceKind`
- `tabId`
- `pageURL`
- `title`
- `label`
- `summary`
- `previewType`
- `recordEstimate`
- `backingMechanism`
- `confidence`
- `metadata`

Possible `sourceKind` values:

- `dom`
- `structuredJSON`
- `table`
- `xhrFeed`
- `imageFeed`
- `curatedAdapter`
- `userDefinedSource`

Possible `backingMechanism` values:

- `dom`
- `embeddedJSON`
- `networkObserved`
- `hybrid`

## Adapters vs Sources

This distinction is central.

### Research Source

Represents discovered data available from the page.

Examples:

- visible review card list
- `/reviews?...` JSON payload
- JSON-LD product metadata block

### Research Adapter

Represents extraction logic that turns one or more sources into a normalized collection of records.

Examples:

- Amazon Reviews Adapter
- Reddit Thread Adapter
- GitHub PR Comments Adapter

An adapter may consume:

- one source
- or multiple sources combined

## Prompt-Driven System vs Structured Runtime

The system should be prompt-assisted, but not prompt-only.

### Recommendation

Do not use raw markdown skills files or freeform prompts as the runtime execution layer.

Instead:

- use structured adapter/source definitions for execution
- use prompts and LLM assistance to help author, map, or suggest those definitions

This gives you the flexibility of a skills-like system while preserving safety and runtime clarity.

## Adapter / Source Spec Layer

The long-term flexible version of this system should support structured, declarative source definitions.

These specs can be:

- curated and shipped by Vapor
- authored by advanced users
- generated with LLM assistance

Potential formats:

- YAML
- JSON
- JS manifest + handler code

### Curated adapter example

```yaml
id: amazon-reviews
kind: curated-adapter
matches:
  - host: amazon.com
    pathPattern: "*/dp/*"

actions:
  - id: extractReviews
    label: Extract Reviews
    emits:
      collectionType: amazonReviews
      recordType: review
    capabilities:
      dom: true
      network: true
    options:
      maxPages:
        type: integer
        default: 10
```

### User-defined network source example

```yaml
id: internal-feedback-api
kind: network-source
matches:
  - host: corp.example.com

actions:
  - id: extractFeedback
    label: Extract Feedback
    requestMatch:
      urlContains: "/api/feedback"
      method: GET
    responseShape:
      root: "data.items"
    fields:
      id: "id"
      title: "subject"
      body: "comment"
      author: "user.name"
      createdAt: "created_at"
```

## LLM / Prompt-Assisted Layer

This is where prompt-driven flexibility becomes powerful.

The LLM should help with:

- choosing a curated adapter
- identifying which observed XHR is interesting
- generating a source definition from sample JSON
- suggesting field mappings from raw payloads
- helping enterprise users configure internal data sources

### Good examples of prompt-assisted behaviors

- "Extract all reviews from this Amazon page"
- "Find the network feed that contains the comments"
- "Treat `data.items[]` as records and map fields"
- "Create a reusable source for this internal dashboard"

### Recommendation

Use prompts to assist authoring and selection.
Do not rely on freeform prompt interpretation alone for runtime extraction.

## Enterprise / Corporate Use Cases

This system is especially strong for enterprise scenarios.

### Mode A: User knows the backend

The user knows:

- the endpoint pattern
- response root
- likely field mappings

This should map cleanly onto user-defined source definitions.

### Mode B: User does not know the backend

The system helps discover:

- which XHRs are interesting
- which responses contain arrays of records
- which payloads look like comments, tickets, metrics, or other research-relevant data

This is where the interrogation workspace becomes a differentiator.

### Recommendation

Do not build a full DevTools clone.

Instead:

- surface observed endpoints
- preview payload shape and sample records
- let the user promote an endpoint into a reusable source definition later

## Protocol Additions

The existing browser bridge should gain a discovery layer in addition to extraction.

## App -> Extension

Suggested new commands:

- `INTERROGATE_TAB`
- `LIST_RESEARCH_SOURCES`
- `PREVIEW_RESEARCH_SOURCE`
- `START_RESEARCH_JOB`
- `CANCEL_RESEARCH_JOB`

## Extension -> App

Suggested new events:

- `RESEARCH_SOURCES_DISCOVERED`
- `RESEARCH_SOURCE_PREVIEW`
- `RESEARCH_JOB_STARTED`
- `RESEARCH_JOB_PROGRESS`
- `RESEARCH_RECORD_BATCH`
- `RESEARCH_JOB_COMPLETED`
- `RESEARCH_JOB_FAILED`

This creates three clear layers:

- discovery
- preview
- extraction

## Vapor Data Model

The earlier adapter document already introduced:

- `ResearchCollection`
- `ResearchRecord`

This still stands.

This broader source model likely also needs:

### `ResearchSourceDefinition`

For saved user-defined or promoted sources.

Suggested conceptual fields:

- `definitionId`
- `sourceKind`
- `matchingRules`
- `requestMatchRules`
- `responseShape`
- `fieldMappings`
- `label`
- `authoringMode`

Possible authoring modes:

- `curated`
- `userDefined`
- `llmGenerated`

## Recommended User Flow

## V1 flow

1. user chooses `Research This Page`
2. Vapor opens tab-selection UI similar to the existing browser target flow
3. user selects a tab to interrogate
4. Vapor opens an interrogation workspace
5. workspace surfaces:
   - suggested adapters
   - DOM summary
   - structured JSON candidates
   - tables / repeated record candidates
   - observed XHR feeds
6. user selects a source or a curated adapter
7. user either:
   - prompts over it temporarily
   - or extracts it into a durable collection

## Recommended Implementation Order

### Phase A: Interrogation foundation

- tab interrogation command flow
- source discovery protocol
- source inventory UI
- source preview UI

### Phase B: Curated adapter foundation

- adapter registry
- research job model
- progress protocol
- first adapter slot

### Phase C: Amazon reviews first adapter

- one-click extraction from active product page
- review records
- collection storage
- vectorization per review

### Phase D: Collection analysis UI

- collection browser
- keyword and semantic search
- metadata filters
- summarization over selected subsets

### Phase E: User-defined sources

- promote observed XHR feed into a source definition
- configure record mappings
- save reusable source definitions

### Phase F: Prompt-assisted source authoring

- suggest source definitions from observed data
- generate field mappings from sample payloads
- recommend adapters or source definitions based on prompt intent

## Recommendation Summary

Build this as:

- tab interrogation
- research source discovery
- curated adapters first
- atomic record extraction
- user-defined sources later
- prompt-assisted source authoring on top

Do **not** build it as:

- only an Amazon scraper
- only a raw network inspector
- only a prompt-only black box

The strongest version of this feature is a browser-native research system that helps the user understand what the page and its network are already exposing, then choose how to turn that into analyzable collections.

## Open Questions

1. In the interrogation workspace, what should be the default first tab?
   - suggested adapters
   - source inventory
   - DOM summary
   - observed XHR feeds

   Recommendation:
   - `Suggested Adapters` first, with `Sources` as the main secondary surface

2. For observed XHRs, should Vapor initially:
   - only preview payload shape
   - or also allow live watching immediately

   Recommendation:
   - preview first, live watching later

3. For the first Amazon version, should extraction start from:
   - adapter button only
   - or from selecting a review-like source candidate too

   Recommendation:
   - adapter button first, source-driven extraction later
