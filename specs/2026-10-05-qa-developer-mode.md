# Spec: QA & Developer Mode (Viewport Simulator, Mirrored Multi-Device & Cross-Engine Comparison)

**Status:** Implemented (2026-10-05); since 2026-10-10 Cross-Engine Compare runs real Chromium and the multi-device grid renders devices with the Space's engine. Chromium devices are emulated through the DevTools protocol: the CSS viewport scaled to the grid, and for phones and tablets mobile layout rules, touch and Chrome for Android's user agent.<br>
**Date:** 2026-10-05<br>
**Priority:** High-value product differentiator<br>
**Related:** [Research Index](README.md), [Selectable Browser Engine per Space](2026-10-03-selectable-browser-engine.md), [Browser Copilot Terminal](2026-10-03-browser-copilot.md)

---

## 1. Executive Summary

Web developers, QA engineers, designers, and product teams spend hours daily testing layouts across device screen sizes and cross-browser engines. Today, this requires cumbersome tools: resizing browser windows, opening separate apps (Safari + Chrome), paying for specialized tools (Polypane, Sizzy, LambdaTest), or using heavy Electron apps (Responsively App).

**NFBrowser** already possesses two foundational superpowers:
1. A blazing-fast native macOS WebKit core with containerized Spaces and Split Tabs.
2. An active architectural track for **selectable dual engines** (WebKit + Chromium).

This specification defines **QA & Developer Mode** for NFBrowser: a native suite of testing tools built directly into the browser. It introduces:
- **Instant Viewport Sizing & Responsive Presets** (`Mobile S`, `Mobile M`, `Mobile L`, `Tablet`, `Laptop`, `Desktop`, `Custom`).
- **One-Click Session & Cookie Importer** (seamless login extraction from Arc, Chrome, and JSON files into any Space).
- **Mirrored Multi-Device View** (simultaneous testing across phone, tablet, and desktop with synchronized scrolling, clicking, and typing).
- **Cross-Engine Comparison Mode (The Unfair Advantage)**: Side-by-side WebKit (Safari) vs Chromium (Blink) with synchronized interaction for instant layout, rendering, and bug diffing.
- **Integrated QA Toolkit**: 1-click full-page screenshots, auto-detection of site CSS breakpoints, accessibility/color blindness simulation, and visual annotations.

---

## 2. Competitive Landscape & Reference Architecture

| Tool | Strengths | Weaknesses | How NFBrowser Wins |
| :--- | :--- | :--- | :--- |
| **Responsively App** (Open-source, Electron) | Multi-device mirrored scroll/click, screenshot suite, network throttle. | Heavy Electron memory footprint (1.5GB+ RAM), Chromium-only, sluggish with many devices. | **Native macOS Swift/AppKit performance**, lightweight memory, zero Electron lag, plus WebKit engine. |
| **Polypane** (Commercial) | Gold standard for a11y (WCAG, contrast, color blindness), CSS breakpoint auto-discovery, social card previews. | Paid proprietary subscription, Electron-based, Chromium-only. | Built directly into NFBrowser with **Zero subscription**, instant hotkeys, and native Apple Silicon efficiency. |
| **Sizzy** (Commercial) | Device switcher, universal console, presentation mode. | Paid proprietary, Chromium-only. | Native Split View, Space isolation, and cross-engine testing. |
| **Worker Browser (Orca / AI IDEs)** | Clean top toolbar with Viewport Size presets, cookie import, inspect, and annotation tools. | Bound to IDE canvas, limited customization, single viewport at a time. | Matches the frictionless toolbar UX while offering both single-device simulation and multi-device matrix. |
| **NFBrowser Cross-Engine Split** *(Unique)* | **None exists on the market.** | No browser can run WebKit and Chromium side-by-side. | **World's first cross-engine live diff** browser. |

---

## 3. Core Modules & Functional Specifications

```
┌────────────────────────────────────────────────────────────────────────┐
│                        NFBrowser QA & Dev Suite                        │
├─────────────────┬───────────────────┬───────────────────┬──────────────┤
│ 1. Viewport Sim │ 2. Multi-Device   │ 3. Cross-Engine   │ 4. Cookie    │
│    (Single/Bar) │    Mirroring      │    (WebKit vs CEF)│    Importer  │
└─────────────────┴───────────────────┴───────────────────┴──────────────┘
```

### Module 1: Viewport Simulator & Responsive Presets

Provides single-viewport device simulation directly in the active tab canvas.

#### Presets & Breakpoints
The presets match modern device standards and common responsive breakpoints:

| Name | CSS Dimensions | Typical Hardware Reference |
| :--- | :--- | :--- |
| **Default** | *Fluid (100% window)* | Standard fluid desktop viewport |
| **Mobile S** | 320 × 568 px | iPhone SE 1st gen, small Androids |
| **Mobile M** | 375 × 667 px | iPhone 6 / 7 / 8 / SE (2nd/3rd gen) |
| **Mobile L** | 425 × 812 px | iPhone X / 11 / 12 / 13 / 14 / 15 / 16, Galaxy S series |
| **Tablet** | 768 × 1024 px | iPad Mini / iPad 10.2" / Surface vertical |
| **Laptop** | 1024 × 768 px | Standard 4:3 / Base desktop breakpoint |
| **Laptop L** | 1440 × 900 px | MacBook Air / Standard widescreen laptop |
| **Desktop** | 1920 × 1080 px | Full HD Monitor (1080p) |
| **Custom** | *User defined W × H* | Direct numeric input with drag handles |

#### Canvas UI & Device Chrome
- **Isolated Device Frame**: When a non-default viewport is active, the tab area renders a dark canvas (`#161618`) centering the webview.
- **Device Header Strip**:
  - Displays: Device Name + Dimensions (e.g. `Mobile L — 425 × 812 px`).
  - **Rotate Button (⇄)**: Flips Width and Height instantly (Portrait ↔ Landscape).
  - **Zoom / Fit Toggle**: Auto-scales large resolutions (e.g. 1920×1080) to fit within a smaller MacBook display using CSS zoom or AppKit layer scale.
  - **Touch Emulation Toggle**: Simulates touch gestures (touch events vs mouse click) and shows touch cursor.
  - **Close Button (✕)**: Restores fluid full-window layout (`Default`).

---

### Module 2: Mirrored Multi-Device View (The Responsively Experience)

Allows viewing a web page simultaneously across 2 to 5 device viewports with synchronized interactions.

#### Layout Modes
- **Horizontal Carousel**: Devices side-by-side with horizontal scroll.
- **Adaptive Matrix Grid**: 2x2 or 3-column grid adapting to window width.

#### Interaction Mirroring Engine (`DeviceSyncBridge.js`)
An injected lightweight script coordinates peer viewports via WebKit message handlers:

1. **Scroll Synchronization**:
   - Computes normalized scroll percentage:
     $$\text{PercentY} = \frac{\text{scrollY}}{\text{scrollHeight} - \text{innerHeight}}$$
   - Broadcasts to peer webviews, ensuring proportional scrolling across different device heights without jitter.
2. **Click & Tap Mirroring**:
   - Generates unique CSS/DOM selector path for clicked targets.
   - Triggers programmatic click/focus on corresponding elements in peer viewports.
3. **Form Input Mirroring**:
   - Tracks `input` and `change` events on text fields, checkboxes, and dropdowns.
   - Mirrors typed values in real-time across all viewports.
4. **Navigation Lockstep**:
   - Clicking a link navigates all viewports to the new URL simultaneously while retaining their individual viewports.
5. **Per-Device Sync Toggle**:
   - Each device frame has an independent "Sync" toggle icon (enabled by default) to allow interacting with one device in isolation when desired.

---

### Module 3: Cross-Engine Split Mode (WebKit vs Chromium)

The unique differentiator of NFBrowser: testing Safari (WebKit) and Chrome (Chromium) side-by-side.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Cross-Engine Compare Mode                       │
├───────────────────────────────────┬────────────────────────────────────┤
│         WebKit (Safari)           │         Chromium (Blink)           │
│   • Apple typography & font AA    │   • Google Blink rendering         │
│   • WebKit CSS prefixes & quirks  │   • Chromium standard CSS          │
│   • macOS native form controls    │   • Blink form rendering           │
├───────────────────────────────────┴────────────────────────────────────┤
│  [⇆ Mirror Scroll & Click]  [🔍 Diff Overlay]  [📐 Synchronized Zoom]  │
└────────────────────────────────────────────────────────────────────────┘
```

#### Capabilities:
- **Side-by-Side Split**: 50/50 vertical split pane with WebKit on the left and Chromium on the right.
- **Mirrored Interaction**: Scroll and click synchronized across engine boundaries.
- **Engine Bug Detection**:
  - Highlights font metric differences.
  - Exposes CSS differences (`-webkit-` prefixes, flexbox wrapping, sticky positioning bugs).
  - Verifies cross-engine auth and cookies.
- **Visual Diff Overlay (Optional)**: Inverts or overlays rendering at 50% opacity to reveal 1px misalignments between Safari and Chrome.

---

### Module 4: One-Click Cookie & Session Importer

QA testers frequently test protected dashboards, admin panels, and payment checkouts. Re-authenticating manually in every test container is a major productivity bottleneck.

#### Import Sources:
1. **Local Arc Browser**: Reads SQLite cookie store at `~/Library/Application Support/Arc/User Data/Default/Network/Cookies`.
2. **Local Google Chrome / Brave**: Reads `~/Library/Application Support/Google/Chrome/Default/Network/Cookies`.
3. **JSON Cookie Export**: Standard format exported by developer extensions (`Cookie-Editor`, `EditThisCookie`).
4. **Netscape cookies.txt**: Standard format used by curl, Postman, and automated test runners.

#### Target Injection:
- Injects cookies directly into the active Container's `WKWebsiteDataStore.httpCookieStore`.
- Supports domain filtering: import all cookies or only cookies for the currently active tab's domain.
- Prompts user with a confirmation sheet listing imported count and domain scope.

---

### Module 5: QA Testing & Inspection Toolset

1. **One-Click Full-Page Screenshot**:
   - Native WebKit `takeSnapshot` stiched capture.
   - Saves full scrollable document as high-resolution PNG with metadata stamp (URL, resolution, date).
   - "Capture All Devices": in Multi-Device mode, captures all viewports into a zip file or single composite image.
2. **CSS Breakpoint Auto-Detection**:
   - Inspects `document.styleSheets` for `@media (min-width: ...)` and `@media (max-width: ...)`.
   - Generates quick-click filter pills in the QA toolbar (e.g. `[480px] [768px] [1024px] [1280px]`).
3. **Accessibility (a11y) & Vision Defect Filters**:
   - Live SVG color filters applied over the webview:
     - *Protanopia* (red-blindness)
     - *Deuteranopia* (green-blindness)
     - *Tritanopia* (blue-blindness)
     - *Achromatopsia* (monochromacy)
     - *Blur / Low Contrast* (visual impairment simulation)
   - Checks contrast ratios and warns on non-compliant WCAG AA/AAA elements.
4. **User-Agent & Feature Emulation**:
   - User-Agent presets: iPhone Safari, iPad Safari, Android Chrome, Desktop Safari, Desktop Chrome.
   - Emulate `prefers-color-scheme`: Force Dark Mode or Force Light Mode regardless of macOS system setting.
   - Emulate `prefers-reduced-motion`.

---

## 4. UI / UX Design & Workflows

### 1. The QA Entry Points
- **In URLBar `...` Menu**:
  - `Viewport Size >` submenu with all 8 standard presets.
  - `QA & Dev Mode >` submenu (Multi-Device, Cross-Engine, Cookie Importer).
- **Dedicated QA Toolbar Icon**:
  - Optional `sparkles.tv` or `display.2` icon on the right side of the URL bar.
- **Global Keyboard Shortcuts**:
  - `Cmd + Shift + M`: Toggle Viewport Simulator (Standard DevTools shortcut).
  - `Cmd + Shift + Q`: Toggle Multi-Device Mirrored View.
  - `Cmd + Option + E`: Toggle Cross-Engine Split View.

### 2. The QA Control Strip
When Viewport Simulator or Multi-Device mode is active, an elegant floating glass toolbar docks at the top or bottom of the canvas:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ [📱 Mobile M ▾] [⇄ Rotate] [100% ▾] │ [🔗 Sync: ON] [📸 Capture] [👁 a11y ▾] │ [✕ Close]│
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Technical Architecture & File Structure

```
NFBrowser/
├── Features/
│   ├── QA/
│   │   ├── Models/
│   │   │   ├── ViewportPreset.swift          // Dimensions, device icons, orientations
│   │   │   ├── QAModeState.swift             // Active viewport, mirroring, zoom, a11y filter
│   │   │   └── BreakpointScanner.swift       // Injected CSS media query parser
│   │   ├── Services/
│   │   │   ├── DeviceSyncBridge.swift        // WKScriptMessageHandler for scroll/click/input
│   │   │   ├── CookieImportService.swift     // Arc/Chrome SQLite & JSON cookie importer
│   │   │   └── FullPageScreenshotService.swift
│   │   ├── Scripts/
│   │   │   ├── qa-sync-bridge.js             // Real-time event capture and dispatch
│   │   │   ├── qa-breakpoints.js             // CSS rule discovery script
│   │   │   └── qa-a11y-filters.css           // SVG vision deficiency filters
│   │   └── Views/
│   │       ├── ViewportCanvasView.swift      // Framed canvas container with scale/zoom
│   │       ├── MultiDeviceGridView.swift     // 2-5 mirrored viewports in grid/carousel
│   │       ├── CrossEngineSplitView.swift    // WebKit vs Chromium synchronized view
│   │       ├── QAControlStrip.swift          // Floating HUD bar
│   │       └── CookieImportSheet.swift       // Confirmation and browser selection sheet
```

---

## 6. Implementation Phasing & Roadmap

### Phase 1: Viewport Simulator & Presets (Immediate Milestone)
- `ViewportPreset` definitions (`Mobile S`, `Mobile M`, `Mobile L`, `Tablet`, `Laptop`, `Laptop L`, `Desktop`, `Custom`).
- Canvas container in `BrowserWebContentView` with frame clipping and centered layout.
- Floating device header with resolution badge, Rotate (Portrait ↔ Landscape), and Reset.
- URLBar `... > Viewport Size` menu integration and `Cmd + Shift + M` shortcut.

### Phase 2: Session & Cookie Importer
- Extract and generalize Arc cookie reader into `CookieImportService`.
- Support Chrome/Brave cookie database reading and JSON file drag-and-drop.
- Injection into active container's `WKHTTPCookieStore`.
- UI sheet in URLBar menu: `Import Cookies > From Arc / From Chrome / From File...`.

### Phase 3: Mirrored Multi-Device Grid
- `MultiDeviceGridView`: render 3 viewports simultaneously (Mobile, Tablet, Desktop).
- `qa-sync-bridge.js`: inject scroll percentage, click selector, and input sync.
- Per-viewport sync toggle and responsive card header.
- Full-page screenshot generator.

### Phase 4: Cross-Engine Split View
- Link WebKit tab with CEF Chromium tab in a 50/50 split container.
- Connect `DeviceSyncBridge` between the two distinct engine instances.
- Visual diff toggle and synchronized inspection.

### Phase 5: Advanced QA Suite
- CSS media query auto-detection and breakpoint pills.
- Accessibility / Color blindness SVG filters.
- `prefers-color-scheme` force toggle.

---

## 7. Verification & Success Criteria

1. **Responsiveness Accuracy**: Injected viewport dimensions report exact `window.innerWidth` and `window.innerHeight` to JavaScript and trigger corresponding CSS `@media` breakpoints.
2. **Performance**: Multi-device mirroring maintains 60 FPS scrolling with zero lag or circular event feedback loops.
3. **Session Continuity**: Imported cookies authenticate the user immediately without page errors or expired session invalidations.
4. **Cross-Engine Isolation**: In Cross-Engine mode, WebKit and Chromium run in their respective memory spaces without interfering with each other's security origins.
5. **Native macOS Polish**: All animations, controls, and canvas scaling match macOS Human Interface Guidelines with smooth spring transitions.
