<img src="Sources/PanePilot/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="180" alt="PanePilot icon" align="left"/>

<div>
<h3>PanePilot</h3>
<p>A macOS menu bar utility for snapping windows into practical layouts. Hold a modifier while dragging a window and PanePilot shows a layout picker at the top of the screen — hover any zone to preview it, then release to snap. You can also snap without touching the mouse using the keyboard shortcut.</p>
</div>

<br/><br/>

<div align="center">
<a href="https://github.com/HansJoakimPersson/PanePilot/actions/workflows/ci.yml"><img src="https://github.com/HansJoakimPersson/PanePilot/actions/workflows/ci.yml/badge.svg" alt="CI"/></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--only-blue.svg?style=flat" alt="license"/></a>
<a href="https://github.com/HansJoakimPersson/PanePilot"><img src="https://img.shields.io/badge/platform-macOS-0A84FF.svg?style=flat" alt="platform"/></a>
<a href="https://github.com/HansJoakimPersson/PanePilot"><img src="https://img.shields.io/badge/Swift-6%20toolchain-F05138.svg?style=flat&logo=swift&logoColor=white" alt="Swift 6 toolchain"/></a>
<a href="https://buymeacoffee.com/hansjoakimpersson"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-Support-FFDD00.svg?style=flat&logo=buymeacoffee&logoColor=000000" alt="Buy Me a Coffee"/></a>
</div>

<br/>

> [!IMPORTANT]
> PanePilot is still evolving quickly. Releases are available from GitHub, and the project overview also lives on GitHub Pages.

## Download

Download the latest release here:

- [PanePilot-latest-macOS.zip](https://github.com/HansJoakimPersson/PanePilot/releases/latest/download/PanePilot-latest-macOS.zip)
- [Project website](https://hansjoakimpersson.github.io/PanePilot/)

Releases are published through GitHub. Public notarized downloads and an App Store submission path are not set up yet.

## Major features

- Runs from the macOS menu bar.
- **Snap picker popup** — hold the configured modifier while dragging and a thumbnail row appears at the top of the screen showing all available layouts. Hover any zone to see a full-screen preview, then release to snap.
- **Keyboard snap** — press modifier + Escape (no drag needed) to open the picker, then type the layout number followed by the zone number (e.g. `1` then `2` for layout 1, zone 2).
- **Numbered zones** — every zone displays its number in the picker thumbnail and in the full-screen preview so keyboard navigation is always visible.
- Includes built-in `40 / 60`, `60 / 40`, mirrored widescreen layouts, and multi-column layouts inspired by Amethyst.
- Exposes Start at Login for signed app bundles.
- Includes debug logging when you need to inspect permissions or window movement failures.

## Website

PanePilot also has a project site on GitHub Pages:

- [hansjoakimpersson.github.io/PanePilot](https://hansjoakimpersson.github.io/PanePilot/)

## How to install and use the app

1. Download the latest release archive.
2. Move `PanePilot.app` to the `Applications` folder.
3. Launch `PanePilot`.
4. Grant Accessibility access in `System Settings` > `Privacy & Security`.
5. Open `Settings…` to choose the snap modifier.

**Drag to snap:**
1. Hold the configured modifier and start dragging a window.
2. A layout picker appears at the top of the screen with all available layouts as numbered thumbnails.
3. Hover any zone — a full-screen preview highlights where the window will land.
4. Release the mouse button to snap.

**Keyboard snap (no drag required):**
1. Hold the modifier and press Escape.
2. The picker appears over the frontmost window.
3. Press the layout number (shown in the top-left badge of each thumbnail).
4. Press the zone number (shown centred in each zone).
5. The window snaps and the picker closes.

PanePilot uses the macOS Accessibility APIs to detect the active window, inspect its current frame, and move or resize it when a snap is confirmed.

### macOS compatibility

| PanePilot version | macOS version |
| ----------------- | ------------- |
| current           | 13 or newer   |

## Current limits

- Target platform: macOS 13 or newer.
- Accessibility permission is required before snapping works.
- Some apps enforce minimum window sizes, so PanePilot may need to correct the final frame after a snap attempt.
- The keyboard snap modifier + Escape shortcut cannot be intercepted — it also reaches the frontmost app. Choose a modifier that does not conflict with global shortcuts in your commonly used apps.
- Start at Login is only available when PanePilot is running from a signed `.app` bundle.
- Public notarized distribution and an App Store submission path are not set up yet.

## How to build

### Requirements

- Xcode command line tools
- A Swift 6 toolchain with SwiftPM tools support for 6.1

### Build steps

```bash
swift build
swift test
make app
make run
```

You can also open `PanePilot.xcodeproj` in Xcode for app target management, signing, entitlements, and archive/export work.

## Support

If you want to support PanePilot or whatever I end up building next, you can do that here:

- [Buy Me a Coffee](https://buymeacoffee.com/hansjoakimpersson)

## License

PanePilot is licensed under `AGPL-3.0-only`.

Unless explicitly stated otherwise, the source code in this repository and binaries produced from it are distributed under that same license.
