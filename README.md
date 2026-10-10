<div align="center">
  <img width="128" height="128" src="/assets/icon.png" alt="NFBrowser icon by NFLab">
  <h1>NFBrowser</h1>
  <p>A fast, fluid, native dual-engine browser for macOS with AI Agent capabilities by <a href="https://nflab.org/">NFLab · No Filter Lab</a>.</p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/14+/blue" alt="macOS 14+"></a>
  <a href="https://developer.apple.com/xcode/"><img src="https://badgen.net/badge/Xcode/15+/blue" alt="Xcode 15+"></a>
  <a href="https://swift.org"><img src="https://badgen.net/badge/Swift/5.9/orange" alt="Swift 5.9"></a>
  <a href="LICENSE"><img src="https://badgen.net/badge/License/GPL-3.0/green" alt="GPL-3.0"></a>
</p>

> [!NOTE]
> NFBrowser is an experimental macOS browser by NFLab designed for maximum fluid navigation, spaces productivity, and integrated local AI Agent pairing.

## Overview

NFBrowser is a native macOS browser built with SwiftUI, AppKit, WebKit, and Chromium (through CEF, the Chromium Embedded Framework). It is an open-source experiment by NFLab — a laboratory for building, testing, learning, and sharing projects without commercial pressure.

The codebase is derived from [Ora Browser](https://github.com/the-ora/browser). NFBrowser retains the original project's GPL-3.0 license and upstream copyright notices.

## Key Features

- **Dual Engine Architecture**: Each Space runs on **WebKit** (the default, energy-efficient Safari engine) or **Chromium** (Blink and V8 from Chromium 154 via CEF). Every Space keeps its own cookies and storage, and Cross-Engine Compare shows a page in both engines side by side.
- **Peek Floating Preview**: Click links to open a floating preview window over the current page (Arc-style Peek). Review the content quickly, close with `Esc` / `✕`, or promote it to a permanent tab with one click.
- **Arc Spaces & Migration**: Effortlessly import Arc spaces, tabs, and favorites. Organize workspaces with custom and special icons (Check, X, etc.) and individual engine settings.
- **Fluid Tab Management**:
  - Smooth, spring-animated drag-and-drop tab reordering.
  - Zero-delay tab closing.
  - Undo closed tabs instantly with `Cmd+Z` / `Ctrl+Z`.
- **Integrated AI Agent Terminal**: Side-by-side terminal panel to run local AI coding and research agents (Gemini, Antigravity, Shell) with bounded control of the active page.
- **Content Blocking & Privacy**: Built-in ad blocking, tracker protection, and per-space privacy sandboxing.
- **Customizable Layout**: Resizable sidebar, flexible agent panel splitters, and distraction-free full-screen modes.

## Chromium Engine

Chromium Spaces embed the real Chromium engine, so sites see Chrome and DevTools speaks the Chrome DevTools Protocol. The prebuilt CEF that NFBrowser uses has limits:

- No H.264, AAC or HEVC (licensing), so some video does not play; VP9, AV1 and Opus do.
- No Widevine DRM (Netflix, Disney+, Spotify web).
- No Chrome Web Store extensions in embedded tabs.
- Google may refuse account sign-in in embedded browsers, and Chrome sync is not available.
- Ad and tracker blocking currently applies to WebKit Spaces only.
- The engine adds about 275 MB to the app.

Use a WebKit Space for anything that needs those. To update the engine, change the pinned version and SHA-1 in `scripts/setup-cef.sh`.

## Build and Install

```bash
git clone https://github.com/yanffernandes/nfbrowser.git
cd nfbrowser
./scripts/setup.sh
./scripts/install.sh --launch
```

`setup.sh` installs the tools and prepares Chromium (`scripts/setup-cef.sh` downloads the pinned CEF build, checks its SHA-1 and builds the C++ wrapper; it needs `cmake` and `ninja`). The install script compiles the project, codesigns the bundle ad-hoc, and installs it directly to `/Applications/NFBrowser.app`.

## Development

- **App Target**: `NFBrowser` (produces `NFBrowser.app`)
- **Project Generation**: XcodeGen via `project.yml` (`xcodegen`)
- **Testing**: `TEST_RUNNER_CFFIXED_USER_HOME=$(mktemp -d) xcodebuild test -scheme NFBrowser -destination "platform=macOS" -only-testing:NFBrowserTests` (the isolated home keeps the test host away from your real session)
- **Chromium smoke test** (Debug builds): `CFFIXED_USER_HOME=$(mktemp -d) NFBrowser.app/Contents/MacOS/NFBrowser --chromium-smoke-test /tmp/nf-smoke` exercises the engine end to end and writes `report.json`

## Open Source & Credits

NFBrowser is licensed under [GPL-3.0](LICENSE). It builds upon the foundational work of the [Ora Browser](https://github.com/the-ora/browser) team and its open-source contributors. All original copyrights and author attributions are preserved in the git history and license files.
