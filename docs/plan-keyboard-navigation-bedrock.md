# Plan: Keyboard Navigation Bedrock

## Purpose

Vapor should support a coherent keyboard-driven interaction model across its main window and supporting windows.

The goal is not just to sprinkle more shortcuts on top of the UI. The goal is to define a small set of focus zones, a shared interaction grammar, and consistent movement/activation semantics so the entire app becomes predictable from the keyboard.

This plan focuses first on the main window. The `Context Explorer` should later adopt the same grammar, but it is a follow-up implementation phase.

## Product Decisions Locked In

- `Focus Context Tray` should auto-open the tray if it is hidden.
- Explicit screenshot-navigation mode should stay in screenshots after insertion.
- The screenshot shelf should show a lightweight hint explaining how to return to the editor.
- The editor remains the default and fallback focus zone.

## Main Window Focus Zones

The main window should have a single active keyboard zone at a time.

Suggested zones:

- `editor`
- `screenshots`
- `contextTray`
- `toolRail`

Optional later:

- `toolbar`

The toolbar should remain command-driven for now rather than becoming a primary keyboard zone.

## Architecture

### Add a shared focus coordinator

Create a shared main-window focus store.

Suggested type:

```swift
enum MainWindowFocusZone {
    case editor
    case screenshots
    case contextTray
    case toolRail
}

@Observable
final class MainWindowFocusStore {
    var activeZone: MainWindowFocusZone = .editor
    var previousZone: MainWindowFocusZone?
}
```

This store should own only the active zone, not the per-zone selection state.

### Keep selection state local to each zone

Per-zone local state should remain inside the relevant surface:

- editor: text cursor / insertion point
- screenshot shelf: selected screenshot asset ID
- context tray: selected context item ID
- tool rail: selected tool index

This keeps global focus management clean and avoids a monolithic store.

## Global Focus Commands

Add explicit zone-entry commands.

Recommended shortcuts:

- `Cmd-Shift-I` → Focus Editor
- `Cmd-Shift-S` → Focus Screenshots
- `Cmd-Shift-C` → Focus Context Tray
- `Cmd-Shift-T` → Focus Tool Rail

### Command behavior

#### Focus Editor

- switch active zone to `editor`
- refocus the native text editor
- clear transient selection-mode affordances in other zones

#### Focus Screenshots

- expand the screenshot shelf if needed
- switch active zone to `screenshots`
- select the most recent screenshot if nothing is currently selected

#### Focus Context Tray

- reveal the tray if hidden
- switch active zone to `contextTray`
- select the first visible row or restore the last tray selection

#### Focus Tool Rail

- switch active zone to `toolRail`
- select the first actionable icon or restore the last tool selection

## Shared Interaction Grammar

Each zone should use the same high-level semantics.

### Arrows

- selection-based zones use arrows for movement
- editor keeps normal cursor behavior

### Return

- primary action for the currently selected item in selection-based zones

### Space

- same as Return where no stronger secondary semantic exists

### Escape

- leave the current non-editor zone and return focus to the editor
- if already in the editor, preserve existing higher-level app behavior such as minimizing if that is still desired

### Tab / Shift-Tab

Do not rely on default SwiftUI tab ordering as the primary navigation model in the first pass.

Later, once zones are stable, consider using:

- `Tab` to move to the next zone
- `Shift-Tab` to move to the previous zone

## Zone-Specific Semantics

### Editor Zone

Purpose:

- primary writing/editing area

Commands and keys:

- normal text editing behavior
- `Cmd-Shift-I` focuses the editor from anywhere
- `Escape` from editor may continue to minimize if that remains the chosen top-level behavior

Visual focus:

- use the current editor glow as the strongest focus treatment in the app

### Screenshot Shelf Zone

Purpose:

- quick prompt enrichment with recent screenshots/images

Entry:

- `Cmd-Shift-S`

Keys:

- left/right arrows move selection
- `Return` inserts annotated screenshot reference
- `Space` inserts annotated screenshot reference
- `Escape` returns focus to editor

Behavior:

- stay in screenshot zone after insertion
- auto-scroll focused screenshot into view
- show a subtle in-shelf hint such as `Press ⌘⇧I to return to the editor`

Visual focus:

- selected screenshot should use a medium-strength focus treatment derived from the editor glow family
- no enlarged floating preview tied to hover or focus in the initial keyboard-driven model

### Context Tray Zone

Purpose:

- browse and insert durable context items

Entry:

- `Cmd-Shift-C`

Keys:

- up/down arrows move selection
- `Return` opens detail
- `Space` inserts selected context item into the editor
- `Escape` returns focus to editor
- later: `/` or `Cmd-F` focuses tray filter field

Behavior:

- auto-open tray when focused from command
- restore prior selection when reasonable

Visual focus:

- selected row should have a clear selected state
- tray-zone activation can add subtle accent emphasis, but should not be as strong as the editor glow

### Tool Rail Zone

Purpose:

- compact vertical action rail for browser target, post, and dictation

Entry:

- `Cmd-Shift-T`

Keys:

- up/down arrows move selection
- `Return` or `Space` activates selected tool
- `Escape` returns focus to editor

Visual focus:

- selected icon gets stronger outline/accent
- dictation can still reflect live state independently of keyboard focus

## Focus Visual Hierarchy

Use a focus hierarchy instead of making every focus state visually identical.

### Strong focus

Used for:

- editor

### Medium focus

Used for:

- selected screenshot in active screenshot zone
- selected tool in active tool rail zone

### Standard selection

Used for:

- context tray rows
- explorer result rows later

This preserves the editor as the primary focus surface while still making secondary zones feel active.

## Notifications and Command Routing

The current notification-based command routing is an acceptable bridge, but the focus system should move toward a more deliberate coordinator.

### Short-term

Use notifications to trigger focus-zone changes:

- `vaporFocusEditor`
- `vaporFocusScreenshots`
- `vaporFocusContextTray`
- `vaporFocusToolRail`

Selection movement notifications can remain short-term helpers while the zone model is being introduced.

### Long-term

Move toward:

- a shared `MainWindowFocusStore`
- app-level key routing based on `activeZone`
- per-zone selection handling owned by each zone view

## Implementation Checklist

### Phase A: Main window focus architecture

- add `MainWindowFocusZone`
- add `MainWindowFocusStore`
- inject it into the main window environment
- route explicit focus commands through it

### Phase B: Screenshot shelf integration

- replace ad hoc screenshot navigation flags with zone-based focus activation
- keep screenshot selection local to the shelf
- add shelf hint text for `Cmd-Shift-I`
- keep insertion in screenshot zone after `Return`

### Phase C: Context tray keyboard support

- add row selection state to the tray
- support up/down movement
- `Return` opens selected item detail
- `Space` inserts selected item into editor
- `Escape` returns to editor
- `Cmd-Shift-C` reveals tray if hidden and focuses it

### Phase D: Tool rail keyboard support

- add tool selection state
- support up/down movement
- support activation via `Return` / `Space`
- `Escape` returns to editor

### Phase E: Editor fallback and Escape semantics

- ensure all non-editor zones return cleanly to editor on `Escape`
- keep editor as default/fallback zone
- preserve any window-level escape behavior only after editor fallback is handled

### Phase F: Explorer follow-up

Apply the same grammar later to `Context Explorer`:

- browse sections
- result list
- search field focus
- facet selection

This should be a separate pass after the main-window focus model is stable.

## Acceptance Criteria

- the main window always has at most one active keyboard zone
- `Cmd-Shift-I` focuses the editor
- `Cmd-Shift-S` focuses screenshots and selects the most recent screenshot
- `Cmd-Shift-C` reveals and focuses the context tray
- `Cmd-Shift-T` focuses the tool rail
- arrows operate only inside the active non-editor zone
- `Return` activates the selected item in the active non-editor zone
- `Escape` always returns from a non-editor zone to the editor
- screenshot insertion keeps focus in screenshots during explicit screenshot-navigation mode
- the screenshot shelf shows a visible hint for returning to the editor
