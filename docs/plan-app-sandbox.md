# Plan: Enable macOS App Sandbox

## Why the App Is Not Sandboxed

`Vapor.entitlements` currently has `com.apple.security.app-sandbox` set to `false`. The sandbox is disabled because the app relies on several APIs and behaviors that are incompatible with a sandboxed environment in their current form.

### Primary Blockers

#### 1. `OllamaDaemonManager` — Subprocess Spawning (`Process()`)

The most significant blocker. `OllamaDaemonManager` uses `Foundation.Process` to launch the bundled `ollama` binary directly:

```swift
// Vapor/Vapor/Services/OllamaDaemonManager.swift
let proc = Process()
proc.executableURL = URL(fileURLWithPath: ollamaBinaryPath)
proc.arguments = ["serve"]
try proc.run()
```

Sandboxed apps **cannot spawn arbitrary subprocesses**. Attempting to call `Process().run()` in a sandboxed app throws a permission error at runtime.

#### 2. PID File Written to `~/.vapor-ollama.pid`

`OllamaDaemonManager` writes a PID file to the user's home directory:

```swift
FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".vapor-ollama.pid")
```

In a sandboxed app `homeDirectoryForCurrentUser` resolves to the app's container (`~/Library/Containers/<bundle-id>/Data/`), not the real home directory. This means the PID file location changes and cross-session PID adoption stops working. The intent of using a well-known path in `~` must change.

### Secondary Considerations (Already Compatible)

| Feature | Status | Notes |
|---|---|---|
| Embedded NIO HTTP server (port 8766) | ✅ Ready | `com.apple.security.network.server` entitlement covers it |
| Network client (URLSession, Ollama API) | ✅ Ready | `com.apple.security.network.client` entitlement covers it |
| Microphone / audio input | ✅ Ready | Entitlements already present |
| Speech recognition | ✅ Ready | Entitlement already present |
| `BlobStore` (Application Support) | ✅ Ready | Writes to app container – works in sandbox |
| `CompressionService` models (Application Support) | ✅ Ready | Same as above |
| Clipboard (`NSPasteboard.general`) | ✅ Ready | Allowed in sandbox without extra entitlements |
| SwiftData / `ModelContainer` | ✅ Ready | Writes to app container – works in sandbox |
| `KeyboardShortcuts` (global hotkeys) | ⚠️ Check | Requires `com.apple.security.temporary-exception.apple-events` or `accessibility` entitlement for global key monitoring outside the app window |

---

## Implementation Plan

### Option A — Externalize Ollama (Recommended for App Store)

Stop bundling and managing the ollama binary. Instead, connect to an ollama instance already running on the machine (user-installed via `brew install ollama` or the official installer).

**Changes:**
1. Remove `ollamaBinaryPath` / `Bundle.main.resourceURL?.appendingPathComponent("ollama")` references.
2. Remove `OllamaDaemonManager.start()` / `stop()` / `writePidFile()` / PID-file logic.
3. Replace `OllamaDaemonManager.isHealthy()` with a simple `GET /api/tags` health check against the user-configured host.
4. Add a Settings UI field for the Ollama base URL (default `http://127.0.0.1:11434`).
5. Show a setup prompt ("Ollama not found — install it at ollama.com") during onboarding when the health check fails.
6. Remove the model download flow from `CompressionService` (or keep it as a separate helper tool outside the sandbox).
7. Set `com.apple.security.app-sandbox` to `true` in `Vapor.entitlements`.

**Pros:** Simplest path to App Store. App becomes lightweight. Users who already have Ollama running benefit immediately.  
**Cons:** Users must install Ollama separately. The in-app download-model flow disappears.

---

### Option B — XPC Helper Process (Keep Bundled Ollama)

Move ollama lifecycle management to a separate macOS XPC service that runs outside the sandbox boundary.

**Changes:**
1. Add a new `OllamaHelper` target (command-line tool or XPC service) to the Xcode project.
2. Define an XPC protocol (`OllamaHelperProtocol`) with `start(port:)`, `stop()`, `isHealthy()` methods.
3. Move all `Process()`, `kill()`, and PID-file logic from `OllamaDaemonManager` into the helper.
4. In the main app, replace `OllamaDaemonManager` with an XPC connection to `OllamaHelper`.
5. Add an `SMPrivilegedExecutables` / `XPC` entitlement to the main app and the helper.
6. Move the PID file into the helper's own working directory (outside the sandbox).
7. Set `com.apple.security.app-sandbox` to `true` in `Vapor.entitlements`.

**Pros:** Keeps the bundled ollama model management UX.  
**Cons:** Significantly more engineering work. XPC services require careful lifecycle and crash recovery handling. App Store review scrutiny for helper processes.

---

### Option C — macOS Hardened Runtime (No App Store, Direct Distribution)

If App Store distribution is not a goal, the sandbox requirement can be deferred. Instead:
- Enable **Hardened Runtime** (`com.apple.security.hardened-runtime = true`) for notarization.
- Keep `com.apple.security.app-sandbox = false`.
- The PID file and Process() usage continue to work.

This is the current de-facto state. Notarization is still possible and required for Gatekeeper on macOS 10.15+.

---

## Recommended First Steps (Option A)

- [ ] Remove `OllamaDaemonManager.start()` call from `VaporApp.setupBrowserBridge()`
- [ ] Remove `OllamaDaemonManager.stop()` call from `VaporAppDelegate.applicationShouldTerminate`
- [ ] Remove Ollama binary from the app bundle resources (reduce app size)
- [ ] Add a `ollamaBaseURL` preference to `UserPreferences`
- [ ] Update `CompressionService` to use `ollamaBaseURL` instead of the hardcoded localhost endpoint
- [ ] Update `EntityExtractionService` similarly
- [ ] Add an onboarding step / Settings warning when `GET <ollamaBaseURL>/api/tags` returns an error
- [ ] Set `com.apple.security.app-sandbox` to `true` in `Vapor.entitlements`
- [ ] Test all features under sandbox (Instruments → Sandbox Violations profile is useful)
- [ ] Add `com.apple.security.temporary-exception.apple-events` if global keyboard shortcuts break

## References

- [Apple: Enabling the App Sandbox](https://developer.apple.com/documentation/security/app_sandbox/enabling_app_sandbox)
- [Apple: Designing for App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Apple: XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
- [Ollama installation docs](https://ollama.com/download/mac)
