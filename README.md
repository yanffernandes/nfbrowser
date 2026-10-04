<div align="center">
  <img width="128" height="128" src="/assets/icon.png" alt="NF Browser icon by NFLab">
  <h1>NF Browser</h1>
  <p>An experimental, native WebKit browser for macOS by <a href="https://nflab.org/">NFLab · No Filter Lab</a>.</p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/15+/blue" alt="macOS 15+"></a>
  <a href="https://developer.apple.com/xcode/"><img src="https://badgen.net/badge/Xcode/15+/blue" alt="Xcode 15+"></a>
  <a href="https://swift.org"><img src="https://badgen.net/badge/Swift/5.9/orange" alt="Swift 5.9"></a>
  <a href="LICENSE"><img src="https://badgen.net/badge/License/GPL-3.0/green" alt="GPL-3.0"></a>
</p>

> [!NOTE]
> NF Browser is experimental and is not ready for daily use yet.

## Overview

NF Browser is a native macOS browser built with SwiftUI, AppKit, and WebKit. This project is an open-source experiment by NFLab, a laboratory for building, testing, learning, and sharing projects without commercial pressure.

The codebase is derived from [Ora Browser](https://github.com/the-ora/browser). NF Browser retains the original project's GPL-3.0 license and upstream copyright notices.

## Highlights

- Native macOS interface and WebKit browsing
- Spaces, favorites, pinned tabs, and vertical open tabs
- Built-in content blocking and privacy controls
- Search engine customization, URL suggestions, and quick launcher
- Browser Agent terminal for locally installed agent CLIs, with bounded control of the active page
- Import browsing data from Arc

## Build from a checkout

```bash
git clone https://github.com/yanffernandes/nfbrowser.git
cd nfbrowser
./scripts/setup.sh
open Ora.xcodeproj
```

The setup script installs required tooling, installs git hooks, and regenerates the Xcode project. The app product is named `NF Browser.app`; the Xcode project file and internal target retain their upstream names for now.

## Development

- Main app target: `ora`
- Project configuration is managed with XcodeGen in `project.yml`
- Regenerate the project after configuration changes with `xcodegen`
- Run tests in Xcode with `Product > Test` or via `xcodebuild test -scheme ora -destination "platform=macOS"`

## Docs

- [Contributing](CONTRIBUTING.md)
- [Roadmap](ROADMAP.md)
- [Security](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## License

NF Browser is licensed under [GPL-3.0](LICENSE). Copyright and attribution notices from Ora Browser are retained. Third-party libraries are licensed under their own terms.
