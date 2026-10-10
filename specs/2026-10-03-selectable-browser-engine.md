# Spec: selectable browser engine per Space

**Status:** Implemented; only a notarized Release build remains (needs a Developer ID) (2026-10-10); see [Implementation status](#implementation-status)<br>
**Date:** 2026-10-03<br>
**Priority:** Second product track; feasibility spike first<br>
**Related:** [Research index](README.md), [Browser copilot terminal](2026-10-03-browser-copilot.md)

## Implementation status

Verified on 2026-10-10 against CEF 154.0.34 (Chromium 154.0.8037.98), arm64.

| Phase | State | Evidence |
|---|---|---|
| P0 spike | Done | Debug `--chromium-smoke-test` passes all 14 checks in about 6 s: two persistent profiles isolated, a second tab of a profile shares storage, an in-memory profile, back/forward, DevTools-protocol JavaScript, screenshot, binding, document-start script, download, `window.open` popup keeping `window.opener`, cookie import and per-site clearing. Init 76–90 ms; first load about 260 ms; framework 275 MB after locale trimming; four browsers about 1.2 GB resident. |
| P1 engine-neutral layer | Done | `BrowserPage` protocol with `WebKitBrowserPage` behind it; engine-neutral popups, downloads and profiles; 53 unit tests. |
| P2 CEF adapter | Done | `ChromiumBrowserPage` serves Chromium Spaces in the real UI (verified through the agent bridge: open, click, back, snapshot, screenshot; user agent `Chrome/154`). Native popups keep `window.opener`; cookies import and clear per Space; changing a Space's engine rebuilds its tabs; Cross-Engine Compare uses a real Chromium pane. |
| P3 parity and release | In progress | Done: helper process sandbox, Chromium net errors on the status page, JS dialogs, downloads, Cmd shortcuts, inside-out Release signing in `embed-cef.sh`; tabs opened in the background load before they are shown (offscreen parking window); closing a private window releases its Chromium profiles; tracker protection blocks the WebKit host list when loaded as a third party; the three cookie policies map to Chromium's own settings, in private and on-disk profiles; the multi-device grid runs Chromium devices; filter lists run in Chromium from the same compiled content-blocker rules as WebKit, interpreted natively with WebKit's semantics (EasyList: about 7 µs per request, 0.8 ms of element-hiding CSS per document); camera and microphone requests reach the app's permission flow. The smoke test now has 23 checks, including background loading, tracker blocking, each cookie policy (third-party probed with a cross-site frame on loopback) and filter lists (blocked script, hidden element, exception, blocked page). Open: notarized Release build (needs a Developer ID). |

Decisions taken while implementing:

- Embedded tabs are always Alloy style on macOS (CEF forces it for child views), so Chrome extensions are out of reach there.
- SwiftUI ignores `NSPrincipalClass`; `App/main.swift` makes `NFChromiumApplication` the `NSApp` before `NFBrowserApp.main()`.
- CEF starts lazily with the first Chromium page; dev builds use `Chromium-Dev` as root cache path because CEF allows one process per root.
- Page scripts reach Swift through `window.__oraBridge` over a DevTools binding; pages never see `window.webkit`.
- `window.open` popups that ask for a window open in native Chromium popup windows; other new-window requests open tabs.

## Summary

Let each Space use either the existing WebKit engine or an embedded Chromium engine. Different Spaces may use different engines in the same NF Browser window. Each Space has its own engine-specific persistent storage context. Existing Spaces remain on WebKit after upgrade.

The proposed Chromium implementation is CEF (Chromium Embedded Framework), not a Chrome window controlled from the outside and not a fork of Chromium. CEF has per-request contexts and cache paths, which are a plausible fit for Space isolation. First prove it can be embedded and shipped inside this app with two isolated contexts, native view hosting, helper processes, hardened runtime, signing, and notarization.

## Problem and user outcomes

Users want to choose the web engine that best fits each browsing context. They can keep a Space on WebKit, use Chromium in another Space for Blink-specific compatibility, and switch Spaces with NF Browser's existing navigation without opening another browser window. They understand that website data is isolated by engine and is not automatically shared or migrated between WebKit and Chromium.

## Current implementation

- `BrowserEngine` is a singleton factory/cache that currently creates concrete `BrowserEngineProfile` and `BrowserPage` instances.
- `BrowserEngineProfile` wraps `WKWebsiteDataStore`, using the Space UUID for persistent storage and a nonpersistent store for private browsing.
- `BrowserPage` owns a `WKWebView`, navigation delegates, page lifecycle, JavaScript, snapshots, and the `NSView` exposed to the app.
- `TabContainer` is the SwiftData Space model. `Tab` restores its transient `BrowserPage` from the owning container's UUID; there is no persisted engine selection yet.
- `BrowserPage` is referenced widely outside the engine folder. `BrowserPageDelegate`, browser views, tab restoration, download handling, privacy, and other services use WebKit types or behavior.
- `BrowserPrivacyService` uses WebKit content-rule lists and cookie policy. Download handling uses `WKDownloadDelegate`. Cookie import currently targets a WebKit cookie store. Some error and tab-search code also imports WebKit.
- `ModelConfiguration+Shared` declares the SwiftData schema explicitly. The engine field and migration/default behavior must be included in that schema path.
- The browser-agent terminal disables App Sandbox so local agent CLIs can use the user's tools and sign-in; the Release build retains hardened runtime. CEF helper processes, dynamic libraries, file locations, entitlements, signing, and notarization remain release requirements, not just local build details.

## Product and data decisions

### Engine ownership

- Engine selection belongs to a **Space**, not an individual tab. All tabs in one Space use the same engine and storage context.
- Different Spaces in the same app window can use different engines.
- `TabContainer` stores a stable engine kind (`webkit` or `chromium`). Existing records without a value resolve to `webkit`.
- Private Spaces use an ephemeral store/context for the selected engine and discard it when the private Space closes.
- No user Chrome installation, Chrome profile, or Chrome cookie database is opened or modified.

### Profile and storage isolation

- WebKit continues to use a persistent `WKWebsiteDataStore` keyed by the Space UUID.
- Chromium uses a distinct CEF request context for each persistent Space, with a unique, app-owned cache/data path beneath NF Browser's Application Support directory. Tabs in a Space share that Space's context.
- Private Chromium contexts must not write persistent cookies, cache, local storage, or other website data. Verify this with the pinned CEF version and tests; do not treat an empty cache path as ephemeral until proven for the selected API/configuration.
- Engine data is not copied when changing a Space's engine. If a user switches from WebKit to Chromium, preserve the WebKit data in place, create/use that Space's Chromium context, and reopen its tabs at their current URLs. Switching back reuses the preserved WebKit data.
- Before a user changes engine, explain that the other engine has a separate login/data store. Never silently copy cookies or claim that the user remains signed in.
- Clearing a Space's website data clears only the active engine's selected data and reports exactly which store was cleared.

### Engine change lifecycle

When a user changes a Space's engine:

1. Present a confirmation that sessions, cookies, local storage, permissions, and extensions are engine-specific and will not transfer.
2. Save each tab's URL and app-owned state that can be restored safely.
3. Stop downloads and pending page operations that cannot cross engines; report any interruption.
4. Tear down the old engine pages and create pages using the selected engine and the Space's corresponding storage context.
5. Restore URLs and reload. Do not copy passwords, cookies, or provider state.
6. If creation fails, keep the selected engine setting unchanged and restore the prior engine pages where possible.

## Architecture

### Shared interfaces and adapters

Introduce app-facing protocols or an equivalent stable abstraction, for example:

- `BrowserEngineProfileProviding`: engine kind, Space identifier, privacy state, data clearing, cookie/data import capabilities, and profile teardown.
- `BrowserPageProviding`: host `NSView`, tab/profile identity, URL/title/loading state, navigation, reload/stop, JavaScript or user-script capabilities, screenshot/snapshot, downloads, and lifecycle events.
- `BrowserEngineFactory`: creates and caches profiles/pages using `(engineKind, spaceID, privacyMode)` as the identity. Cache keys must include engine kind to prevent returning a WebKit object for a Chromium Space.

Keep shared browser features dependent on these contracts. Implement `WebKitBrowserPage` and `WebKitBrowserProfile` adapters around the current implementation before introducing CEF, so the abstraction change does not also change user-visible behavior. The copilot feature should use the shared page-control contract from its first version.

The contract should expose explicit capabilities for features that cannot be made common. Do not silently report success for an unsupported operation. Avoid handing raw WebKit or CEF objects to generic browser UI code.

### Chromium adapter

Use a pinned CEF release and an Objective-C++ bridge where required to host a CEF browser view in AppKit and expose navigation, events, script execution, snapshots, downloads, and request contexts to Swift. CEF's helper applications and resources must be included, signed, and notarized under the current release pipeline.

The app owns CEF initialization/shutdown lifecycle. It must not initialize multiple incompatible CEF runtimes in the same process. Each Space context is created and destroyed through a single profile manager with explicit lifetime rules.

### WebKit-specific features and parity

Audit and port or gate every direct WebKit dependency, including:

- `BrowserPrivacyService`: content blocking/rule lists, cookie policy, and injected protections.
- `BrowserDownloadTask` and download destinations/permissions.
- Cookie import and any browser-data importer. Imported cookies must be written to the selected Space's selected engine, or the importer must clearly state that Chromium cookie import is unavailable. It must not write into WebKit's global default store when the active profile is Chromium.
- WebKit-specific failure pages and error-domain handling.
- `BrowserPageConfiguration` and user-script registration.
- Tab search code that imports or inspects WebKit state.

The required first-release parity set is page load, back/forward, reload/stop, URL/title/loading events, new-tab/navigation policy, host view, screenshots or snapshots, approved JavaScript/user scripts, downloads, cookie policy, data clearing, and privacy/content-blocking behavior. For any feature not yet at parity, expose a capability state and explain it in the UI before the user chooses Chromium.

AirPlay, platform picture-in-picture, WebKit inspector integration, and Chrome Web Store extension support are not assumed to work in CEF. Full Widevine/DRM parity is not assumed. Treat those as separate, independently verified work.

## User interface

- Add an engine selector to Space settings with WebKit and Chromium choices.
- Show the selected engine in Space settings and in a discoverable browser/about surface.
- Explain engine-specific login/storage behavior before switching.
- While CEF is unavailable, initializing, or failed, show a recoverable error and allow returning to WebKit without losing the saved URLs or WebKit data.
- Do not expose Chromium as a stable choice until its required parity checklist and security/update gate pass.

## Acceptance criteria

1. Every existing Space opens on WebKit after the schema migration, with its current tabs, history, and website data intact.
2. A user can choose WebKit or Chromium per Space. Mixed-engine Spaces render in the same app window without opening Chrome windows.
3. Two persistent Chromium Spaces create isolated CEF request contexts: logging into a site in one does not authenticate the other; cookies and local storage do not cross contexts.
4. A WebKit Space and Chromium Space do not share website data. Switching engine preserves each engine's prior data separately and reloads the current URLs without claiming session migration.
5. Private Spaces do not persist cookies, cache, or site storage for either engine after closing. Verify at startup and shutdown, including crash-recovery behavior.
6. App navigation, tab restore, back/forward, reload/stop, page events, snapshots, downloads, and the required first-release privacy controls work for both engines or clearly report a documented capability gap before selection.
7. Cookie/data clearing and import target the selected Space and engine. One Space's action cannot clear or import into another Space's store.
8. The app can launch, use, close, sign, and notarize CEF helper applications in the actual distribution configuration with the current App Sandbox-disabled privilege model and hardened runtime enabled for Release.
9. Failed CEF initialization or engine switching leaves the Space recoverable and preserves WebKit data and saved tab URLs.
10. The release process pins and records the CEF/Chromium version, tracks upstream security updates, and blocks release when the embedded version is not within the project's approved security window.
11. Copilot page tools operate through the shared page-control interface on either engine; provider code does not depend on WebKit or CEF APIs.

## Delivery plan

### P0 — CEF feasibility spike (exit before broad refactor)

Build a small throwaway or isolated spike in this repository's app configuration that:

- Hosts one CEF page inside an AppKit view and navigates to a normal HTTPS page.
- Creates two persistent CEF request contexts with separate cache paths and demonstrates cookie/local-storage isolation.
- Creates and closes an ephemeral context and verifies its data is not retained.
- Exercises back/forward, JavaScript execution, screenshot/snapshot, and one download.
- Builds, launches, signs, and notarizes with the app's current App Sandbox-disabled/hardened-runtime constraints and CEF helpers.
- Records the exact CEF/Chromium version, framework and final app bundle sizes, startup time, idle/active memory, helper behavior, and any entitlement changes. These measurements are currently unknown and must not be guessed.

**Exit:** ship feasibility decision and measured trade-offs. If helper packaging or security constraints cannot be satisfied in the present app model, stop before the broad refactor and keep WebKit as the sole engine while evaluating alternatives.

### P1 — engine-neutral facade

- Add engine kind and profile identity to the factory model.
- Convert consumers of concrete `BrowserPage` and `BrowserEngineProfile` to the app-facing protocols or equivalent.
- Add a WebKit adapter and confirm no functional behavior changes.
- Add a SwiftData-compatible optional/default engine field and migration test plan.

### P2 — CEF adapter and per-Space UI

- Integrate the pinned CEF binaries, bridge, helpers, lifecycle, and request-context manager.
- Add engine selection and safe engine-switch/recovery flow.
- Add required navigation and lifecycle support.

### P3 — parity, privacy, and release readiness

- Port privacy, cookie policy, content blocking, downloads, data clearing/import, and error reporting.
- Complete private-mode lifecycle, crash recovery, performance, signing, notarization, and security-update checks.
- Enable Chromium in release builds only after all mandatory acceptance criteria pass.

## Verification matrix

Review implementation across these contexts; no single happy-path page is sufficient:

| Space configuration | Required checks |
|---|---|
| WebKit persistent | Existing profile data, page restore, clearing, downloads, privacy controls. |
| WebKit private | No data persistence after close; no history/conversation leakage. |
| Chromium persistent A + Chromium persistent B | Cookies, local storage, cache, clearing, and downloads isolated by Space. |
| WebKit persistent + Chromium persistent | Same-window mixed engine, separate logins/storage, page restore and switching. |
| Chromium private | No storage after normal close or crash recovery. |
| Engine switch and failed initialization | URLs recover; old backend data remains available; selection rolls back on failure. |

## Out of scope

- Modifying or maintaining a Chromium source fork.
- Embedding or controlling the user's installed Chrome app/profile.
- Per-tab engine selection inside one Space.
- Importing/synchronizing cookies between WebKit and Chromium automatically.
- Promising Chrome Web Store extension parity, Widevine/DRM, or every Chrome-specific API.
- A Windows/Linux port in this spec.

## Risks and maintenance

CEF reduces the need to maintain a Chromium fork, but it still requires regular runtime updates. The team owns the CEF binary pin, helper app packaging, code signing, notarization, and security update cadence. CEF support does not itself guarantee Chrome extension, DRM, or every browser API feature.

The app's current WebKit-specific types are spread across core navigation, privacy, download, import, and view code. The adapter migration is a real cross-app refactor. Keep it incremental: first preserve WebKit behavior behind a common interface, then add CEF, then port each system integration with explicit parity tracking.

## Effort estimate

After P0: approximately **4–8 weeks** for one developer, depending on CEF packaging and feature parity. The facade and WebKit adapter may take 3–5 days; CEF bridge and helpers 1–3 weeks; settings/migration/switching 2–4 days; privacy, downloads, import, and lifecycle 4–7 days; release hardening and matrix verification 5–10 days. The P0 spike itself is estimated at 2–4 days. These are planning ranges; bundle/signing results may move them materially.

## Rollback

Keep WebKit as the default and retain all WebKit stores. If CEF fails in production, disable Chromium selection with a feature flag, stop CEF helpers, restore affected tabs in WebKit at their saved URLs, and preserve CEF data for a later retry or user-managed removal. Do not delete either engine's data as part of rollback.
