# NF Browser: research and specs

**Research checked:** 2026-10-03<br>
**Project:** NF Browser, derived from the Ora Browser codebase<br>
**Status:** browser agent terminal integrated; provider runtime smoke checks remain

## Core product tracks

1. [Browser copilot terminal](2026-10-03-browser-copilot.md): a native terminal pane that runs the user's local agent CLI and can perform bounded browser actions through the browser-control skill.
2. [Selectable browser engine per Space](2026-10-03-selectable-browser-engine.md): keep WebKit as the default and add a Chromium-based backend that can be selected independently for each Space/profile.
3. [QA & Developer Mode](2026-10-05-qa-developer-mode.md): responsive viewport simulator, one-click session/cookie import, mirrored multi-device grid, and world-first cross-engine (WebKit vs Chromium) side-by-side comparison.

These tracks build upon each other. The terminal and browser-control bridge work with the current WebKit page. The QA mode leverages containerized Space cookies and introduces responsive simulation and cross-engine testing. The engine proposal adds a CEF backend that powers cross-engine live diffing.

## Repository findings

The current browser is a native macOS SwiftUI/AppKit application. WebKit is the only page engine in the project today. `BrowserEngine` creates concrete `BrowserEngineProfile` and `BrowserPage` instances; `BrowserPage` owns `WKWebView` and provides the app-facing navigation, JavaScript, snapshot, and view-hosting operations. `TabContainer` is the persistent Space model, and `Tab` restores its page using that container's UUID. That gives the engine work a clear seam, but the existing concrete page type is used across the app and would need a protocol or equivalent adapter migration.

The WebKit implementation also reaches beyond the engine folder: privacy/content blocking and cookie policy, download delegates, cookie import, error handling, and some tab/search code use WebKit types directly. The copilot uses the existing page-control surface. Its embedded shell requires App Sandbox to be disabled; hardened runtime remains configured for Release. A CEF plan must account for this current privilege model and still prove helper signing, notarization, security updates, and engine isolation.

The terminal implementation is part of the main branch. Follow-up work should continue in this checkout.

## Market and architecture research

| Reference | What it demonstrates | What to reuse or verify |
|---|---|---|
| [Orca](https://github.com/stablyai/orca) | A local terminal/worktree orchestrator that runs provider CLIs with the user's own sign-in, plus an embedded browser. Its `orca-cli` skill teaches agents the browser command loop (`snapshot`, refs, `click`, `fill`, tabs, screenshots); Design Mode can also send a clicked element's HTML/CSS and screenshot to the terminal agent. | Reuse the embedded terminal + provider CLI + browser-control skill pattern. NF Browser can call its own WebKit tab through a small local control endpoint instead of Orca's Chromium CLI. |
| [GStack browser message flow](https://github.com/garrytan/gstack/blob/main/docs/designs/SIDEBAR_MESSAGE_FLOW.md) and [browser internals](https://github.com/garrytan/gstack/blob/main/docs/BROWSER_INTERNALS.md) | A Chromium browser side panel connected to a local agent session, with browser actions, page context, and activity reported in the panel. This is the closest reference to the first goal and matches the supplied screenshot. | Reuse the interaction pattern and inspect the implementation/license before borrowing code. Its Chrome/Playwright/CDP plumbing does not directly fit a native WebKit app. |
| [BrowserOS](https://github.com/browseros-ai/BrowserOS) | An open-source Chromium browser organized around browser agents and MCP integration; it is another market reference for local browser tools and agent connectivity. | Compare its browser-tool contract and onboarding. Treat its AGPL-3.0 code as a reference unless a deliberate license review approves reuse. |
| [Apple `WKWebsiteDataStore`](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init%28foridentifier%3A%29) | WebKit supports persistent website data stores created by identifier, which is already how the app can isolate Space data. | Preserve the existing mapping from a Space identity to its WebKit store. |
| [CEF request contexts](https://cef-builds.spotifycdn.com/docs/152.0/classCefRequestContext.html) and [CEF usage guide](https://chromiumembedded.github.io/cef/general_usage.html) | CEF can create distinct request contexts with separate cache paths. The contexts can live inside the app's CEF integration; separate Chrome profile windows are not required for this design. | Prototype two isolated contexts in one host window. Confirm the exact behavior, helper packaging, hardened runtime, signing, and notarization for the pinned CEF release. |

### Provider and account constraint

The first proposal targets locally authenticated provider runtimes rather than extracting browser cookies or copying OAuth tokens. Claude Code officially supports use with Pro/Max plans, and Codex CLI supports signing in with ChatGPT. Google changed the Gemini CLI consumer-subscription path in June 2026 and its current Antigravity terms disallow third-party software from piggybacking on consumer CLI OAuth. Therefore Google support must use an explicitly supported Gemini API key or Enterprise path unless Google publishes an approved subscription integration. The UI must label API-key billing clearly; it must not imply that a personal Google AI subscription is supported.

Official references: [Claude Code with Pro/Max](https://support.anthropic.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan), [Codex CLI](https://developers.openai.com/codex/cli), [Google's Gemini CLI transition notice](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/), and [Antigravity FAQ](https://www.antigravity.google/docs/faq/).

### Corrections to earlier assumptions

- A Chrome extension cannot replace Chrome's native browser frame, but the copilot belongs in NF Browser's own app UI, so this extension restriction does not block the feature.
- Chromium does not require one OS window per isolated context when embedded through CEF. CEF request contexts offer a plausible per-Space storage boundary; the remaining cost is integrating and maintaining the CEF runtime and platform-specific packaging.
- CEF should not be described as having full Chrome Web Store extension parity or Widevine/DRM support without a separate, verified spike.

## Recommended order

1. Build the terminal-first browser copilot on WebKit, with a managed workspace skill and local page-control command.
2. Run a small CEF spike in parallel or immediately after the browser-tool contract: host one browser view, create two request contexts, and validate app packaging and signing.
3. Only then estimate the full Chromium adapter and privacy/import parity work.

This sequence provides useful copilot functionality without waiting for Chromium and keeps the CEF decision grounded in a runnable prototype.
