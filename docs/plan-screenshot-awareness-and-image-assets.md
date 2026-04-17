# Plan: Screenshot Awareness and First-Class Image Assets

## Purpose

Vapor should treat images as first-class data, not as incidental blobs or ad hoc prompt text.

This design introduces a durable image asset model, a screenshot-aware intake workflow, and a prompt-time screenshot shelf that makes it trivial to reference recent screenshots without polluting the main context corpus.

The immediate user problem is:

- screenshots are a common power-user input while prompting
- the app should become aware of screenshots shortly after they are created
- the user should be able to click a screenshot and insert a useful prompt reference quickly
- images should also be capable of becoming durable context artifacts later

This design also lays the groundwork for:

- pasted images
- dropped image files
- browser/article image extraction
- future multimodal prompt composition and prompt preview

## Product Model

The system should distinguish between three related but different concepts:

### 1. Context Items

`ContextItem` remains the durable user-facing unit of captured knowledge.

Examples:

- article text
- selected text
- manual text
- page snapshot
- image-first context item

### 2. Image Assets

`ImageAsset` is a first-class durable image record.

It should exist independently of any single context item and be reusable across multiple contexts or prompt sessions.

Examples:

- a newly detected macOS screenshot
- an image pasted into Vapor
- an image dropped into Vapor
- an article image extracted from browser content

### 3. Screenshot Shelf Items

`ScreenshotObservation` is a recent operational UI object that represents a newly detected screenshot or image-like intake event.

It is optimized for prompt composition and quick action, not long-term corpus management.

This is what powers the screenshot shelf.

## Core Recommendation

### Images are first-class assets

Images should not be modeled only as tags or only as `ContextItem(kind: .image)`.

Instead:

- every ingested image becomes an `ImageAsset`
- a `ContextItem` may reference zero, one, or many `ImageAsset`s
- screenshots are identified by provenance, not merely by tag

### Screenshot detection does not auto-create context items

When Vapor detects a new screenshot, it should:

- create or register an `ImageAsset`
- surface it in the screenshot shelf
- not immediately create a durable `ContextItem`

Promotion into the durable context corpus should be an explicit action such as `Add to Context`.

This avoids polluting the left context tray with every screenshot the user takes.

### Prompt insertion uses annotated path text by default

Clicking a screenshot in the shelf should insert an annotated path reference into the prompt, not a naked path string.

Recommended default insertion:

```text
[Screenshot]
path: /Users/ddahl/Desktop/Screenshot 2026-04-17 at 11.58.45 AM.png
```

Also support a context-menu action for plain path insertion.

Even when v1 inserts plain text into the editor, the app should preserve enough structured metadata to know that the prompt now references a specific image asset.

## UX Recommendation

### Use a bottom screenshot shelf, not another sidebar

The screenshot workflow should live in a dedicated bottom shelf in the main window.

Reasons:

- screenshots are immediate prompt-time inputs more than corpus items
- they are visually horizontal and thumbnail-oriented
- the left context tray is already the durable context inbox/library
- a second sidebar would compete too strongly with the current layout

### Main window roles

- `Left Context Tray`: durable context items
- `Editor`: prompt composition
- `Bottom Screenshot Shelf`: recent visual inputs and quick insert/import actions
- `Context Explorer`: durable corpus browsing

### Screenshot shelf behavior

The shelf should be collapsible and sit near prompt composition.

Each screenshot card should show:

- thumbnail
- filename or short time label
- provenance badge, e.g. `Screenshot`
- state badge when useful, e.g. `new`, `inserted`, `imported`, `missing`

Primary actions:

- single click: insert annotated path block
- double click: open/preview image
- context menu:
  - `Insert annotated path`
  - `Insert plain path`
  - `Add to Context`
  - `Reveal in Finder`
  - `Open`
  - `Dismiss`

## Data Model

### ImageSourceKind

This is provenance, not just tagging.

Suggested values:

- `screenshot`
- `pastedImage`
- `droppedFile`
- `articleMedia`
- `browserCaptured`
- `manualImport`

### ImageAsset

First-class durable image record.

Suggested fields:

- `id`
- `contentHash`
- `mimeType`
- `pixelWidth`
- `pixelHeight`
- `byteSize`
- `originalFilename`
- `originalPath`
- `blobPath`
- `thumbnailPath`
- `createdAt`
- `importedAt`
- `sourceKind`
- `isEphemeral` or `lifecycleState`

Notes:

- `contentHash` should be SHA-256 of the raw bytes
- `blobPath` should eventually be content-addressed
- `thumbnailPath` may be cached/derived

### ContextItemImageLink

Join model between `ContextItem` and `ImageAsset`.

Suggested fields:

- `id`
- `contextItem`
- `imageAsset`
- `role`
- `sortIndex`
- `caption`
- `altText`
- `sourceURL`
- `createdAt`

Suggested roles:

- `primary`
- `attachment`
- `inlineArticleMedia`
- `promptAttachment`
- `screenshotReference`

### ScreenshotObservation

Operational recent-item record used by the screenshot shelf.

Suggested fields:

- `id`
- `detectedPath`
- `detectedAt`
- `fileCreatedAt`
- `sourceKind`
- `status`
- `imageAssetID`
- `thumbnailPath`

Suggested statuses:

- `new`
- `inserted`
- `imported`
- `missing`
- `dismissed`

## Prompt Integration

### v1

The editor still uses text insertion, but screenshot insertion should be deliberate and human-readable.

Default action:

- insert annotated path block

Secondary action:

- insert plain path only

### Future-proofing

Even in v1, prompt composition should preserve a seam for future structured prompt segments.

The system should be able to later represent:

- raw text
- compressed text segments
- URL references
- screenshot/image references

This is important for a future prompt viewer that can inline images and show compressed vs. non-compressed regions.

## Detection and Intake

## Sandbox constraint

Vapor is sandboxed and only has user-selected file read permission today. It cannot assume unrestricted Desktop watching.

Therefore screenshot awareness must be based on explicit user-approved watched folders.

### Recommended folder watching model

Support watched folders via security-scoped bookmarks.

Initial watched-folder options:

- Desktop screenshots
- Downloads
- custom folders later

### Detection pipeline

When a new file appears in a watched folder:

1. debounce until the write is stable
2. verify it decodes as an image
3. apply screenshot heuristics where relevant
4. generate a thumbnail
5. register or upsert an `ImageAsset`
6. create/update a `ScreenshotObservation`
7. surface it in the screenshot shelf

### Screenshot heuristics

Likely signals:

- filename resembles `Screenshot ...`
- image file type is acceptable
- creation/modification time is recent
- dimensions resemble likely screen capture shapes

This should be heuristic-driven, not only filename-driven.

## Other Intake Paths

The screenshot/image system should be broader than Desktop watching.

### Paste image into Vapor

If the pasteboard contains image data:

- create or upsert an `ImageAsset`
- surface it in the screenshot shelf
- optionally insert annotated prompt reference immediately

### Drag and drop image file

If a user drops an image into Vapor:

- create or upsert an `ImageAsset`
- surface it in the screenshot shelf
- offer `Insert`, `Add to Context`, or both

### Browser/article image extraction later

Eventually browser-captured article media should use the same `ImageAsset` system.

That keeps screenshots, pasted images, dropped images, and extracted article media on one shared backend.

## Durable Corpus Behavior

### Add to Context

When the user chooses `Add to Context` for an image asset:

- create `ContextItem(kind: .image)`
- link the item to the underlying `ImageAsset`
- persist any prompt or provenance relationship data

Only then should the image become part of the main context corpus and context tray.

### Explorer support later

The `Context Explorer` should eventually gain:

- `Images` section
- screenshot facet/filter
- source-kind browsing
- image-first detail rendering

## Storage Direction

Current `BlobStore` is UUID-based and not content-addressed.

For images, move toward content-addressed storage.

### Recommended CAS approach

- hash raw bytes using SHA-256
- store files under hash-based paths
- preserve extension or MIME type metadata
- dedupe identical images automatically

This should become the shared storage foundation for:

- screenshots
- pasted images
- dropped files
- article media

## Suggested Phases

### Phase 1: Image asset foundation

- define `ImageAsset`
- define `ContextItemImageLink`
- define `ImageSourceKind`
- add content-hash-aware image storage direction

### Phase 2: Screenshot awareness

- watched-folder settings
- security-scoped bookmark handling
- screenshot detection pipeline
- bottom screenshot shelf UI

### Phase 3: Prompt insertion

- insert annotated path block by default
- plain path as secondary action
- preserve structured image-reference metadata for future prompt viewing

### Phase 4: Promotion into context

- `Add to Context`
- create image-first `ContextItem`
- link to `ImageAsset`

### Phase 5: Paste/drop image intake

- paste image support
- drag/drop file support
- same shared image pipeline

### Phase 6: Browser/article image extraction

- article media extraction
- browser image capture reuse
- link article items to `ImageAsset`s

## Relationship to Existing Issues

- `#52` screenshot awareness
- `#45` article media capture, CAS storage, and detail rendering
- `#42` context data models + BlobStore groundwork

Recommended interpretation:

- `#52` should cover screenshot awareness, watched folders, screenshot shelf, and prompt-time screenshot UX
- `#45` should cover article/browser-extracted media capture and rendering on the same asset backend
- `#42` and related storage work should support the image asset/CAS foundation

## Acceptance Criteria for Screenshot Awareness v1

- user can grant Vapor access to one or more watched screenshot folders
- new screenshots appear in a bottom screenshot shelf shortly after creation
- clicking a screenshot inserts an annotated path block into the prompt
- user can insert a plain path through a secondary action
- user can promote a screenshot into a durable image context item with `Add to Context`
- screenshots do not automatically spam the left context tray
- screenshot/image data model is compatible with future article media extraction and prompt viewer work
