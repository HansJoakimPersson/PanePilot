<img src="Sources/PanePilot/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="180" alt="PanePilot icon" align="left"/>

<div>
<h3>PanePilot</h3>
<p>A macOS menu bar utility for snapping windows into practical layouts. Hold a modifier while dragging a window and PanePilot reveals drop zones for fast, repeatable placement across your displays.</p>
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
> PanePilot is staying private for now while the core drag-and-snap workflow is being refined. The README is the main project overview; there is no public GitHub Pages site.

## Download

Download the latest release here:

- [PanePilot-latest-macOS.zip](https://github.com/HansJoakimPersson/PanePilot/releases/latest/download/PanePilot-latest-macOS.zip)

You need access to this private repository to download it.
Public notarized downloads are not available yet.

## Major features

- Runs from the macOS menu bar.
- Reveals snap regions only while you drag with a configurable modifier key.
- Includes built-in `40 / 60`, `60 / 40`, `Wide`, mirrored widescreen layouts, and multi-column layouts inspired by Amethyst.
- Lets each connected display keep its own preferred layout.
- Supports top-half and bottom-half snaps inside a matching region.
- Exposes Start at Login for signed app bundles.
- Includes debug logging when you need to inspect permissions or window movement failures.

## How to install and use the app

1. Download the latest release archive.
2. Move `PanePilot.app` to the `Applications` folder.
3. Launch `PanePilot`.
4. Grant Accessibility access in `System Settings` > `Privacy & Security`.
5. Open `Settings…` to choose the snap modifier and review display layouts.
6. Hold the configured modifier while dragging a window.
7. Hover a region and release to snap.

PanePilot uses the macOS Accessibility APIs to detect the active window, inspect its current frame, and move or resize it when a drop lands inside a snap region.

### macOS compatibility

| PanePilot version | macOS version |
| ----------------- | ------------- |
| current           | 13 or newer   |

## Current limits

- Target platform: macOS 13 or newer.
- Accessibility permission is required before snapping works.
- Some apps enforce minimum window sizes, so PanePilot may need to correct the final frame after a snap attempt.
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
