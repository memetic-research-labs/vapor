# Plan: Secure Browser Extension Auto-Pairing

## Overview

This design replaces the current manual copy-paste bearer token setup between Vapor and the Chrome extension with a guided auto-pairing flow.

The goal is to keep first-run setup simple while avoiding the unsafe bootstrap pattern of handing the long-lived bearer token to whichever unauthenticated localhost client connects first.

The design introduces:

- an explicit short-lived pairing mode in the app
- a one-time pairing code instead of directly exposing the long-lived bearer token
- pinning to the extension origin that completed pairing
- a long-lived bearer token only after the pairing exchange succeeds

This is a design-only document. It does not change the current implementation.

## Current Problem

Today Vapor generates a long-lived bearer token and the user copies it from `Settings > Browser` into the extension popup.

This works, but it adds setup friction.

The tempting alternative is to auto-send the bearer token to the extension on first connection. That is not safe enough because the app currently has no authenticated identity for the first client. Before the token exists on the extension side, the app cannot distinguish:

- the intended Vapor extension
- another browser extension
- a local script or app talking directly to `127.0.0.1`

If Vapor gives the long-lived token to the first unauthenticated client, that client becomes trusted permanently until the token is reset.

## Goals

- Remove manual copy-paste token setup for normal users.
- Keep the trust boundary explicit during first-time pairing.
- Prevent arbitrary localhost clients from silently obtaining the long-lived bearer token.
- Support the existing SSE plus HTTP bridge architecture with minimal disruption.
- Keep reconnects seamless after successful pairing.

## Non-Goals

- Replacing the local HTTP/SSE bridge with Native Messaging in this iteration.
- Solving multi-user machine isolation beyond the current localhost threat model.
- Providing cryptographic mutual attestation of the browser runtime.

## Threat Model

The design assumes the app is listening only on `127.0.0.1`, but localhost is still a shared trust boundary on the machine.

We want to make these attacks materially harder:

- a local process connecting to Vapor and stealing the browser token during first-run setup
- another extension attempting to pair silently before the real Vapor extension
- accidental pairing with the wrong browser profile or extension instance

We do not fully defend against:

- malware already running with the user’s privileges and the ability to read app or browser storage directly
- a compromised browser runtime

## Security Principles

1. Do not hand out the long-lived bearer token to an unauthenticated first client.
2. Use a short-lived, one-time bootstrap secret for pairing.
3. Require an explicit user-approved pairing window.
4. Pin the extension origin that successfully completes pairing.
5. Rotate or replace pairing artifacts once pairing succeeds.

## Proposed User Experience

### First-Time Setup

1. User opens `Settings > Browser`.
2. Vapor shows `Pair Extension` instead of a copyable token as the primary action.
3. User clicks `Pair Extension`.
4. Vapor enters pairing mode for 60 seconds and shows a waiting state.
5. The extension popup detects that Vapor is available but not yet paired.
6. The extension requests pairing.
7. Vapor validates the request, issues a one-time pairing code, and records the requesting extension origin as a candidate.
8. The extension redeems the one-time pairing code.
9. Vapor generates or rotates the long-lived bearer token, persists the trusted extension origin, and returns the bearer token to that extension only.
10. The extension stores the token in `chrome.storage.local` and reconnects over SSE using the token.
11. Vapor marks the browser as paired and connected.

### Normal Reconnects

After pairing:

- the extension reconnects automatically using the stored bearer token
- Vapor accepts requests only when both the bearer token and the pinned extension origin match

### Token Reset

When the user clicks `Reset Browser Pairing`:

- Vapor clears the trusted extension origin
- Vapor rotates the bearer token
- Vapor clears any active pairing session
- the extension must pair again

## Protocol Design

### New Concepts

#### Trusted Extension Origin

Persist the exact origin that completed pairing, for example:

```text
chrome-extension://abcdefghijklmnopabcdefghijklmnop
```

This becomes the allowed browser-side origin for future pairing and authenticated HTTP requests.

#### Pairing Session

A short-lived server-side record containing:

- `sessionID`
- `createdAt`
- `expiresAt`
- `candidateOrigin`
- `bootstrapSecretHash`
- `status` (`pending`, `redeemed`, `expired`, `cancelled`)

The bootstrap secret itself is returned once and never persisted in plaintext after initial issuance.

### New Endpoints

#### `POST /api/pair/start`

Purpose:

- extension asks whether the app is currently accepting a new pairing

Requirements:

- only available while app-side pairing mode is active
- request must have an `Origin` that starts with `chrome-extension://`
- no bearer token required

Response:

```json
{
  "status": "pending",
  "sessionId": "...",
  "bootstrapSecret": "...",
  "expiresIn": 60
}
```

Server behavior:

- reject if pairing mode is not active
- reject if another active pairing session exists for a different origin
- record the requesting origin as the candidate origin for the session

#### `POST /api/pair/redeem`

Purpose:

- extension redeems the one-time pairing secret and receives the long-lived bearer token

Requirements:

- valid active pairing session
- exact same `Origin` as the one that called `POST /api/pair/start`
- valid `sessionId`
- valid bootstrap secret

Response:

```json
{
  "status": "paired",
  "token": "long-lived-bearer-token",
  "trustedOrigin": "chrome-extension://..."
}
```

Server behavior:

- mark the session as redeemed
- persist the trusted extension origin
- rotate and persist the long-lived bearer token
- invalidate any previous trusted token/origin pair

#### Existing endpoints after pairing

Authenticated requests keep using the existing routes:

- `GET /api/stream?token=...`
- `POST /api/response`
- `POST /api/context`

But they must now satisfy both:

- bearer token is correct
- extension origin matches the pinned trusted origin when an origin is present

## Request Validation Rules

### Pairing Requests

For `/api/pair/start` and `/api/pair/redeem`:

- require `Origin`
- require `Origin` to start with `chrome-extension://`
- reject `http://127.0.0.1` and other local web origins for production pairing
- reject if pairing mode is not currently enabled in the app

### Authenticated Requests

For `/api/response` and `/api/context`:

- require `Authorization: Bearer <token>`
- if `Origin` exists, require exact match with `trustedExtensionOrigin`
- continue rejecting unauthorized requests with `401`

### SSE Requests

For `GET /api/stream`:

- keep using the token query parameter because `EventSource` cannot set custom headers
- validate the token as today
- if an `Origin` header is present, require exact match with `trustedExtensionOrigin`

## Why This Is Safer Than Naive First-Connection Bootstrap

The unsafe design is:

- unauthenticated client connects
- app sends the permanent bearer token to that client

The safer design is:

- app only allows bootstrap while the user has explicitly enabled pairing mode
- bootstrap is bound to one short-lived session
- bootstrap is bound to one extension origin
- the long-lived bearer token is only created or returned after the bootstrap secret is redeemed successfully

This reduces the risk of a random local client becoming permanently trusted just by connecting first.

## Extension ID and Origin Strategy

There are two practical options.

### Option A: Pin the Exact Installed Origin at Pair Time

This is the recommended first iteration.

Benefits:

- works with unpacked development builds
- does not require shipping a static manifest key immediately
- keeps setup simple

Tradeoff:

- trusted origin is per installed extension instance, not a globally known constant

### Option B: Ship a Stable Manifest Key and Known Extension ID

Benefits:

- lets Vapor hardcode the expected extension origin
- tighter validation before pairing begins

Tradeoff:

- more operational overhead while the extension is still primarily installed unpacked in development

Recommended direction: start with Option A, then optionally move to Option B once distribution is more stable.

## App Changes

### `BrowserBridge`

Add state for:

- `trustedExtensionOrigin`
- `pairingSession`
- `isPairingEnabled`
- `pairingExpiresAt`

New methods:

- `beginPairingWindow()`
- `cancelPairingWindow()`
- `completePairing(origin:token:)`
- `resetBrowserPairing()`

### `VaporHTTPHandler`

Add routing for:

- `POST /api/pair/start`
- `POST /api/pair/redeem`

Update auth/origin validation to:

- support pairing-mode bootstrap rules
- pin authenticated requests to the trusted extension origin

### `SettingsView`

Browser settings should show:

- `Pair Extension` button
- pairing status text
- trusted extension origin once paired
- `Reset Browser Pairing` button

The raw bearer token can be removed from the primary UX and kept only as an advanced/debug affordance if needed.

## Extension Changes

### `background.js`

Add a pairing bootstrap path:

1. try normal authenticated connection using saved token
2. if token missing and app reports pairing mode is active, call `/api/pair/start`
3. redeem via `/api/pair/redeem`
4. save returned token
5. reconnect via SSE with token

### `popup.js`

Replace manual token entry as the primary flow with:

- `Pair with Vapor` state
- pairing progress / waiting UI
- paired / unpaired status

Manual token paste can remain temporarily as a fallback during migration if desired, but it should not be the main UX once auto-pairing ships.

## Failure Modes

### Pairing window expired

- extension receives a clear `pairing expired` response
- user is prompted to click `Pair Extension` again in Vapor

### Different extension origin attempts redeem

- reject with `403`
- keep session active only for the original candidate origin

### User resets pairing while extension is connected

- current SSE connection drops
- future authenticated requests fail with `401` or `403`
- extension returns to unpaired state and prompts for re-pairing

### Multiple browsers or profiles race to pair

- first successful redeem wins for the active pairing window
- all later attempts are rejected until the user explicitly resets or starts a new pairing window

## Telemetry and Logging

Log these events locally:

- pairing window started
- pairing request received with candidate origin
- pairing redeemed successfully
- pairing rejected due to expired session
- pairing rejected due to origin mismatch
- browser pairing reset

Do not log the bootstrap secret or bearer token.

## Acceptance Criteria

- User can pair the extension without copying a token manually.
- Vapor never returns the long-lived bearer token to an unauthenticated request outside an active pairing window.
- Pairing is bound to the extension origin that initiated it.
- Existing authenticated SSE and POST flows continue working after pairing.
- Resetting pairing invalidates the current extension token and requires re-pairing.
- Browser settings show a clear paired / unpaired / pairing state.

## Rollout Notes

Suggested rollout order:

1. implement server-side pairing session support
2. implement extension bootstrap and token persistence
3. update Browser settings and popup UI
4. keep manual token entry behind an advanced fallback temporarily
5. remove the fallback once auto-pairing proves reliable

## Implementation Checklist

This section breaks the work into concrete implementation slices so the feature can be picked up later without re-planning.

### Phase 1: Core Pairing State in Vapor

#### `Vapor/Vapor/Services/BrowserBridge.swift`

- Add persisted state for:
  - `trustedExtensionOrigin`
  - long-lived bearer token reuse/rotation
  - active pairing window metadata
- Add in-memory pairing session state for:
  - `sessionID`
  - `expiresAt`
  - `candidateOrigin`
  - hashed bootstrap secret
  - session status
- Add methods:
  - `beginPairingWindow(duration:)`
  - `cancelPairingWindow()`
  - `pairingStatusSnapshot()`
  - `startPairing(for origin:)`
  - `redeemPairing(sessionID:secret:origin:)`
  - `resetBrowserPairing()`
- Ensure `resetBrowserPairing()` clears trusted origin, expires any pairing session, rotates the bearer token, and restarts the bridge if needed.

#### `Vapor/Vapor/Services/VaporHTTPHandler.swift`

- Add routing for:
  - `POST /api/pair/start`
  - `POST /api/pair/redeem`
- Refactor auth validation so there are separate code paths for:
  - pairing bootstrap requests
  - authenticated post-pairing requests
- Add helper methods:
  - `requestOrigin(_:)`
  - `isChromeExtensionOrigin(_:)`
  - `isTrustedExtensionOrigin(_:)`
  - `checkPairingAllowed(head:)`
- Keep `GET /api/stream` token auth, but require trusted-origin validation when `Origin` is present.
- Require exact trusted-origin match for `POST /api/response` and `POST /api/context` when `Origin` is present.

### Phase 2: Browser Settings UI

#### `Vapor/Vapor/Views/SettingsView.swift`

- Replace the current token-first Browser auth UI with:
  - `Pair Extension` primary button
  - pairing countdown / waiting state
  - `Paired with <origin>` state
  - `Reset Browser Pairing` button
- Keep the raw bearer token hidden by default.
- If we keep manual token entry during migration, place it under an `Advanced` disclosure.
- Show clear state labels for:
  - unpaired
  - pairing window active
  - paired but disconnected
  - paired and connected

### Phase 3: Extension Bootstrap Flow

#### `vapor-extension/background.js`

- Preserve current reconnect behavior when a saved token already exists.
- Add pairing bootstrap logic:
  - if no token is stored, probe whether Vapor pairing mode is active
  - call `POST /api/pair/start`
  - redeem with `POST /api/pair/redeem`
  - store returned bearer token in `chrome.storage.local`
  - reconnect SSE using the token
- Ensure the extension clears stale bootstrap state after:
  - expiry
  - reset pairing
  - origin mismatch
  - unauthorized responses
- Centralize token lifecycle helpers so reset and re-pair paths do not diverge.

#### `vapor-extension/popup.js`

- Replace primary token paste UX with pairing-centric states:
  - `Ready to pair`
  - `Waiting for Vapor pairing window`
  - `Pairing in progress`
  - `Paired`
  - `Pairing failed`
- Keep a temporary manual-token fallback only if needed for migration/testing.
- Show a recoverable message when Vapor is running but not currently in pairing mode.

### Phase 4: Origin Pinning and Migration Cleanup

#### Shared follow-up tasks

- Decide whether to support exactly one trusted origin or a small allowlist.
- Decide whether unpacked dev builds should pin the first origin dynamically or whether we should move to a stable manifest key.
- Remove broad `chrome-extension://` acceptance in favor of exact trusted-origin checks once pairing is live.
- Update docs:
  - `docs/browser-extension.md`
  - onboarding/setup copy in the app if present

### Phase 5: Tests and Verification

#### App-side checks

- Add unit tests for pairing session lifecycle if practical.
- Add request-auth tests for:
  - unauthenticated pairing outside pairing mode rejected
  - wrong origin rejected during redeem
  - wrong token rejected after pairing
  - wrong origin rejected after pairing
  - reset invalidates prior token

#### Manual verification

- Fresh install: pair without copy-pasting a token.
- Restart Vapor: extension reconnects automatically.
- Reset pairing: extension loses access and must re-pair.
- Competing local client: cannot obtain the long-lived token outside the active pairing flow.
- Different extension/profile after pairing: rejected unless explicitly re-paired.

### Suggested implementation order

1. `BrowserBridge` pairing state and token/origin persistence
2. `VaporHTTPHandler` pairing endpoints and origin validation
3. `SettingsView` pairing UI
4. `background.js` bootstrap flow
5. `popup.js` pairing-first UX
6. migration cleanup and docs
7. tests and manual verification

## Open Questions

- Should manual token entry remain available behind an `Advanced` disclosure for debugging?
- Should Vapor allow exactly one trusted extension origin, or a small allowlist for multiple browser profiles?
- Should the pairing window be 60 seconds, or shorter?
- Should we add a stable manifest key now, or defer until the extension distribution path stabilizes?
