# Spec: browser agent terminal

**Status:** Integrated in the shared NF Browser worktree; local provider runtime flows need a smoke check
**Date:** 2026-10-03<br>
**Priority:** First product track<br>
**Related:** [Research index](README.md), [Selectable browser engine](2026-10-03-selectable-browser-engine.md)

## Summary

Add a resizable terminal pane beside the current page. It runs the user's locally installed agent CLI so Claude Code, Codex, and Google's CLI can use their own interactive sign-in, supported plans, terminal UI, and native agent features. NF Browser does not proxy model requests, read provider tokens, or build a separate chat UI.

Bundle an `ora-browser` command and an agent skill. The CLI talks to a short-lived loopback endpoint owned by the active NF Browser window. The skill teaches the running agent to read the page, take a screenshot, list/switch tabs, navigate, scroll, click, and fill fields using the active tab already rendered by NF Browser's WebKit engine.

This follows Orca's terminal + local CLI + browser skill model. The browser surface remains WebKit-first; a future Chromium backend can use the same browser command contract.

## User outcomes

- Show/hide a terminal beside the page or home screen with a resizable divider.
- Choose Claude Code, Codex, Gemini CLI, Antigravity CLI (`agy`), or a normal shell.
- Reuse authentication and plan usage already configured for that local CLI where the provider allows third-party terminal use.
- Ask the agent to inspect, explain, extract, or operate the page through the NF Browser skill.
- Continue typing directly into the provider's terminal UI; use its normal stop, approval, session, and account controls.
- Keep the terminal session alive when the pane is hidden; stop or restart it from the pane.

## Research and design reference

The current Orca CLI guide describes its embedded browser as a first-class command surface for agent CLIs, with a skill that documents the snapshot/reference/action loop. Orca's terminal documentation describes terminal panes, and its README describes Design Mode for selecting a Chromium element and sending its DOM/CSS/screenshot to an agent. NF Browser can reuse the interaction model without borrowing code: its page controls call the in-process `Tab`/`BrowserPage` facade directly. See the [Orca CLI guide](https://github.com/stablyai/orca/blob/main/skill-guides/orca-cli.md), [browser command reference](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/cli/reference.mdx), and [terminal overview](https://github.com/stablyai/orca/blob/main/docs/site/content/docs/terminal.mdx).

SwiftTerm provides an AppKit terminal view and a local PTY-backed process host. Its documentation warns that App Sandbox prevents a terminal child from accessing most normal user commands and files. The NF Browser app must disable App Sandbox for this feature to use the user's installed CLIs, home-directory auth, shell setup, and keychain-connected agent behavior. The browser's WebKit content processes remain subject to WebKit's own restrictions. This is a deliberate security change because an embedded general-purpose shell is itself an unrestricted local tool surface.

Apple requires App Sandbox for Mac App Store distribution. The embedded terminal targets the current Developer ID distribution; a future Mac App Store build would need a different process-host design or would need to disable the terminal. See [Apple's App Sandbox documentation](https://developer.apple.com/documentation/security/app-sandbox).

## CLI and account behavior

| Selector | Executed program | Account behavior |
|---|---|---|
| Claude Code | `claude` in a login zsh session | Uses the existing Claude Code sign-in and plan. |
| Codex CLI | `codex` in a login zsh session | Uses the existing Codex sign-in and ChatGPT plan. |
| Gemini CLI | `gemini` in a login zsh session | Runs the installed CLI. Google ended Gemini CLI access through consumer AI subscriptions; NF Browser displays that a supported API key or Enterprise account is required. |
| Antigravity CLI | `agy` in a login zsh session | Uses the installed first-party CLI. Google currently says personal Antigravity accounts must not be accessed through third-party tools; NF Browser displays this limitation. Google Enterprise access is the supported third-party path. |
| Shell | `/bin/zsh -l -i` | User can run or install any CLI themselves. |

NF Browser launches each command without copying, parsing, or storing provider credentials. The user signs in through that provider's own CLI UI. NF Browser never runs an installation script automatically. Missing commands remain visible as normal shell errors, with setup links available from the selector.

**Google account constraint:** Google's transition notice says Gemini CLI stopped serving consumer AI Pro/Ultra subscription access on June 18, 2026; the FAQ recommends a supported API key or Enterprise account for third-party coding agents. Antigravity's current terms say using third-party software/tools/services to access it with a personal account is a violation and may lead to account suspension. NF Browser displays these limits and does not represent a personal Google subscription as supported. Source: [Antigravity terms](https://antigravity.google/terms), [FAQ](https://www.antigravity.google/docs/faq/), [CLI transition notice](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/).

## Browser skill and workspace

Create an app-owned workspace under the existing `~/Library/Application Support/Ora/Browser Agent/` path. Keeping this inherited path preserves the current profile and application-support layout. It contains the NF Browser skill in the agent discovery locations:

- `.agents/skills/ora-browser/SKILL.md` for Codex and Antigravity CLI.
- `.claude/skills/ora-browser/SKILL.md` for Claude Code.
- `.gemini/skills/ora-browser/SKILL.md` for the legacy Gemini CLI.

Put the `ora-browser` helper in the same workspace's `Tools/` directory and prepend that directory to the spawned shell's `PATH`. Keep these files private to NF Browser's workspace; do not modify the user's repository or global agent skill folders. The provider CLI's normal home-directory configuration and authentication remain the user's own.

The bundled skill teaches these commands:

- `ora-browser tabs`, `ora-browser switch <tab-id>`
- `ora-browser snapshot`, `ora-browser screenshot [--output <path>]`
- `ora-browser navigate <http-or-https-url>`, `back`, `forward`, `reload`
- `ora-browser scroll <up|down|left|right> [pixels]`
- `ora-browser click <reference> [--confirm]`
- `ora-browser fill <reference> <text>`

The default page snapshot contains the active tab/Space, URL, title, readable text, and at most 120 visible interactive-element references. It does not return cookies, passwords, hidden fields, or other tabs' page content. References expire when the page changes. A snapshot must be refreshed after navigation, tab switch, or a stale-reference response.

## Local browser-control service

- Start a temporary HTTP listener on `127.0.0.1` only when an agent terminal session starts. Bind to an OS-assigned port.
- Generate a cryptographically random session token, pass the endpoint and token only to the launched terminal process through its environment, and reject requests without an exact bearer token.
- Accept JSON requests for the listed browser commands only. Close the listener and clear refs/token when the agent process exits or the user stops the session.
- Use in-process WebKit calls through the active `Tab`; do not enable WebKit remote debugging or expose arbitrary JavaScript, selectors, coordinates, general HTTP, or file access as NF Browser browser commands.
- Clamp scroll to 3,000 pixels. Only allow `http`/`https` navigation. Cap request sizes and page text length.
- `click` can directly activate normal links. For buttons and other controls that may submit or change state, require `--confirm`; the skill instructs the agent to ask the user first. `fill` never submits and refuses password, hidden, and file inputs.
- Treat all page text as untrusted. Page content cannot alter the skill's tool policy or authorize shell actions.
- Do not log page snapshots, screenshots, terminal output, or bearer tokens. The user's selected provider CLI may retain data under its normal provider settings.

## Current implementation anchors

- `BrowserView` composes the current tab sidebar and page content.
- `BrowserSplitView` already uses a draggable `HSplit` for the browser sidebar and page.
- `BrowserPage` wraps `WKWebView` and exposes navigation, JavaScript, snapshot, and view hosting.
- `Tab` exposes the active page, URL, navigation, JavaScript, and screenshot calls through app-level methods.
- `project.yml` declares dependencies, resources, signing, hardened runtime, and the disabled App Sandbox required by the embedded CLI process.

The terminal panel should use `BrowserPage`/`Tab` APIs via the active `TabManager`; it must not depend on WebKit types in its CLI contract.

## UX behavior

- Add a terminal button to the browser URL bar and an app command to toggle the pane.
- Keep the toggle discoverable from the home screen before a page is active.
- Use the existing resizable split control; remember its fraction in UserDefaults.
- The terminal header has a provider/shell menu, Start/Stop, and Hide controls. Show the running process title/status when available.
- Selecting a provider starts its CLI in an embedded SwiftTerm view, using `/bin/zsh -l -i -c "exec <known command>"`. The `Shell` choice starts `/bin/zsh -l -i`. A session can start from the home screen; browser commands report when there is no active page.
- Keep the PTY alive while the pane is hidden. Stop it when the user presses Stop or closes the owning browser window.
- Show an empty state if no process is running, setup errors if resources/bridge are unavailable, and the relevant Google account restriction when a Google CLI is selected.
- Keep the existing page visible and interactive while the user works in the terminal. Terminal focus must not steal keyboard input from the page unexpectedly.

## Acceptance criteria

1. The user can toggle a native terminal pane beside the active page or home screen and resize it. Hiding/showing the pane retains terminal output and process state.
2. The user can start a shell, Claude Code, Codex CLI, `gemini`, or `agy`. The provider CLI displays its own TUI and login flow; NF Browser does not copy credentials or make provider requests.
3. If a CLI is missing or exits, the terminal displays its actual error/output and can start again without restarting NF Browser.
4. The supported skills are present in the app-owned workspace and the `ora-browser` command is available on the agent's PATH.
5. `ora-browser snapshot` returns the active tab, URL, title, page text, and visible refs. `tabs`/`switch`, `screenshot`, navigation, scrolling, click, and fill operate the active NF Browser window.
6. A stale reference, wrong Space/tab ID, unsupported URL scheme, oversized request, or missing token fails without touching the page.
7. A normal link click works without `--confirm`. A page control click without `--confirm` fails; a confirmed click works. Password/hidden/file inputs cannot be filled; field fill never submits a form.
8. The local HTTP server is loopback-only, token-protected, and unavailable after session shutdown. Tokens and page content do not appear in logs.
9. App Sandbox is disabled in the signed app configuration. Release notes and security documentation explain that the embedded terminal runs local commands with the user's account permissions.
10. Google CLI selection discloses the current account restrictions; NF Browser does not claim that consumer Gemini or personal Antigravity subscription access is supported.

## Delivery and verification plan

### Implemented — terminal and page-control surface

- Embed SwiftTerm 1.20.0 and launch a login shell in the existing window.
- Add the terminal pane, local CLI selectors, managed browser skill, and loopback browser-control bridge.
- Compile the app and confirm the skill/helper resources are in the app bundle.

Provider sign-in, browser actions, multiwindow isolation, and release signing remain runtime checks on a machine with the CLIs installed.

### P1 — first usable release follow-up

- Validate provider command launching, workspace skill discovery, and stop/restart lifecycle in each local CLI.
- Validate snapshot, tabs/switch, screenshot, navigation, scrolling, click confirmation, and fill controls interact with the active WebKit page.
- Review signing, notarization, and release messaging for the App Sandbox change.

### P2 — hardening and polish

- Check keyboard focus, process shutdown on window close, repeated hide/show, CLI startup failures, shell profile compatibility, screenshot size, malformed requests, and agent-session exit cleanup.
- Test Claude, Codex, Gemini, and Antigravity CLI paths on a machine where those CLIs are installed; missing-provider behavior is a normal terminal error, not a blocker to other providers.

## Out of scope

- A separate in-app model chat or provider REST/API adapter.
- Reading provider auth files, swapping provider accounts, or displaying private usage data.
- Installing/updating third-party CLIs or authenticating the user automatically.
- General computer-use access outside the active NF Browser browser window.
- Chromium engine support; the future engine adapter should preserve the `ora-browser` command behavior.

## Effort estimate

The terminal-first MVP is roughly **1–2 weeks** for one developer after the process/sandbox path is proven. SwiftTerm and panel integration: 2–3 days; local page-control endpoint and helper: 3–5 days; skill/workspace lifecycle and providers: 2–3 days; security/focus/error hardening: 2–4 days. Provider TUI behavior, code signing, and sandbox changes can move the estimate.

## Rollback

A feature flag can hide the panel. Stopping the manager terminates its PTY and closes the temporary browser endpoint. The app-owned workspace only contains NF Browser's skill and helper; deleting that folder removes those generated files. Existing user provider configuration and CLI credentials remain untouched.
