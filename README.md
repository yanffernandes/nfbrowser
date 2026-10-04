<div align="center">
  <img width="128" height="128" src="/assets/icon.png" alt="NF Browser icon by NFLab">
  <h1>NF Browser</h1>
  <p>A fast, fluid, native dual-engine browser for macOS with AI Agent capabilities by <a href="https://nflab.org/">NFLab · No Filter Lab</a>.</p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/14+/blue" alt="macOS 14+"></a>
  <a href="https://developer.apple.com/xcode/"><img src="https://badgen.net/badge/Xcode/15+/blue" alt="Xcode 15+"></a>
  <a href="https://swift.org"><img src="https://badgen.net/badge/Swift/5.9/orange" alt="Swift 5.9"></a>
  <a href="LICENSE"><img src="https://badgen.net/badge/License/GPL-3.0/green" alt="GPL-3.0"></a>
</p>

> [!NOTE]
> NF Browser is an experimental macOS browser by NFLab designed for maximum fluid navigation, spaces productivity, and integrated local AI Agent pairing.

## Overview

NF Browser is a native macOS browser built with SwiftUI, AppKit, WebKit, and Chromium. It is an open-source experiment by NFLab — a laboratory for building, testing, learning, and sharing projects without commercial pressure.

The codebase is derived from [Ora Browser](https://github.com/the-ora/browser). NF Browser retains the original project's GPL-3.0 license and upstream copyright notices.

## Key Features

- **Dual Engine Architecture**: Run spaces on ultra-fast, energy-efficient native **WebKit** or high-compatibility native **Chromium**.
- **Peek Floating Preview**: Click links to open a floating preview window over the current page (Arc-style Peek). Review the content quickly, close with `Esc` / `✕`, or promote it to a permanent tab with one click.
- **Arc Spaces & Migration**: Effortlessly import Arc spaces, tabs, and favorites. Organize workspaces with custom and special icons (Check, X, etc.) and individual engine settings.
- **Fluid Tab Management**:
  - Smooth, spring-animated drag-and-drop tab reordering.
  - Zero-delay tab closing.
  - Undo closed tabs instantly with `Cmd+Z` / `Ctrl+Z`.
- **Integrated AI Agent Terminal**: Side-by-side terminal panel to run local AI coding and research agents (Gemini, Antigravity, Shell) with bounded control of the active page.
- **Content Blocking & Privacy**: Built-in ad blocking, tracker protection, and per-space privacy sandboxing.
- **Customizable Layout**: Resizable sidebar, flexible agent panel splitters, and distraction-free full-screen modes.

## Build and Install

```bash
git clone https://github.com/yanffernandes/nfbrowser.git
cd nfbrowser
./scripts/setup.sh
./scripts/install.sh --launch
```

The install script compiles the project, codesigns the bundle ad-hoc, and installs it directly to `/Applications/NF Browser.app`.

## Development

- **App Target**: `ora` (produces `NF Browser.app`)
- **Project Generation**: XcodeGen via `project.yml` (`xcodegen`)
- **Testing**: `xcodebuild test -scheme ora -destination "platform=macOS"`

## Open Source & Credits

NF Browser is licensed under [GPL-3.0](LICENSE). It builds upon the foundational work of the [Ora Browser](https://github.com/the-ora/browser) team and its open-source contributors. All original copyrights and author attributions are preserved in the git history and license files.
