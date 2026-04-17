# Plan: Context Explorer UX

## Purpose

The Context Explorer is the corpus browser for captured knowledge in Vapor.

It is not just a search window. It should let the user:

- open the explorer directly and understand what has been collected so far
- browse by structure: domains, authors, entities, URLs, tags, and item types
- drill down from any facet into matching context items
- pivot into keyword or semantic search without losing facet context
- open a context item detail window when deeper inspection is needed

## Product Model

- `Context Tray`: live inbox / recent operational feed
- `Context Item Detail`: single-item provenance and content view
- `Context Explorer`: corpus browser and retrieval dashboard

## Window Layout

The first version uses a simple two-pane layout:

- `Sidebar`: navigation and facet browsing
- `Main pane`: overview dashboard, facet browser, or filtered results

There is no right inspector in v1.

## Open Behavior

- Opening the explorer directly should land on `Overview`
- Opening from a pivot click should apply the relevant filter and show the matching drilldown/results state
- Explorer state should be persisted and restored on app restart
- If no saved state exists, the explorer should default to `Overview`

## Sidebar Sections

The sidebar should contain these top-level destinations:

- `Overview`
- `Recent`
- `Domains`
- `Authors`
- `Entities`
- `URLs`
- `Tags`
- `Types`
- `Processing`
- `Failed`

These are navigation destinations, not just filter toggles.

## Main Pane Modes

### 1. Overview

This is the home screen when the explorer is opened directly.

It should contain:

- search bar and search mode control
- corpus summary counts
- recent captures
- top domains
- top entities
- top tags
- top authors
- queue health when processing or failures exist

The overview should feel like a browse dashboard, not an analytics dashboard.

### 2. Facet Browser

Facet destinations such as `Domains`, `Authors`, `Entities`, `URLs`, `Tags`, and `Types` should show a browseable ranked list with counts.

Examples:

- `Domains`: `nytimes.com (12)`
- `Authors`: `John Gruber (5)`
- `Entities`: grouped by kind, then ranked
- `URLs`: source and mentioned URLs, canonicalized

Clicking a facet row should drill down into results for that value.

### 3. Results / Drilldown

When a facet value is selected or a query is active, the main pane should show filtered context items.

Each result row should show:

- title
- summary or content snippet
- kind
- date
- domain
- author if present
- entity count
- URL count
- status when not ready

Single click selects the row.
Double click opens the detail window.

## Shared Top Bar

All main-pane modes should share a top control area with:

- search field
- mode toggle: `Keyword` / `Semantic`
- sort control
- reset control
- breadcrumbs
- active filter chips

## Navigation Model

The explorer should use both:

- `Breadcrumbs` for navigation context
- `Filter chips` for active query constraints

Examples:

- breadcrumb: `Overview / Domains / nytimes.com`
- chips: `Domain: nytimes.com`, `Ready only`, `Keyword: ai safety`

## Persistence Model

Persist the explorer state in `UserDefaults`.

Persist:

- selected top-level section
- selected facet value where applicable
- search text
- semantic mode
- ready-only toggle
- sort mode

Do not persist transient selection inside the result list for v1.

## Click-through Behavior

When the user clicks a URL, author, domain, entity, or tag from another window:

- the explorer should open or focus
- the sidebar/main pane should switch to the appropriate section
- the corresponding facet filter should be applied
- the breadcrumb and filter chips should visibly reflect the new state

This action must produce visible state change inside the explorer so the click never feels like a no-op.

## Search Behavior

### Keyword

Used for exact and transparent matching across:

- titles
- summaries
- text content
- authors
- canonical URLs
- domains
- entities
- tags

### Semantic

Used for embedding-based search over context items.

Semantic search should combine with active structured filters where possible.

If semantic mode is active, the UI should clearly say so.

## First Implementation Scope

### Must Have

- direct-open explorer overview
- sidebar navigation
- overview dashboard sections
- facet browsers for domains, authors, entities, URLs, tags, and types
- results list with drilldown
- breadcrumbs and filter chips
- persisted explorer state
- click-through from detail window

### Can Wait

- right inspector pane
- saved searches
- hybrid keyword + semantic ranking
- compare mode
- co-occurrence views

## Interaction Principles

- open fast
- make provenance visible
- keep counts everywhere
- prefer browse-first over form-first
- let users narrow by clicking rather than typing whenever possible
- keep the tray simple; do not duplicate the explorer there
