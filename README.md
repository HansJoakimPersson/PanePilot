# PanePilot

<p>
  <a href="https://github.com/HansJoakimPersson/PanePilot/actions/workflows/ci.yml"><img src="https://github.com/HansJoakimPersson/PanePilot/actions/workflows/ci.yml/badge.svg" alt="CI"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--only-blue.svg?style=flat" alt="license"/></a>
  <a href="https://github.com/HansJoakimPersson/PanePilot"><img src="https://img.shields.io/badge/platform-macOS-0A84FF.svg?style=flat" alt="platform"/></a>
  <a href="https://github.com/HansJoakimPersson/PanePilot"><img src="https://img.shields.io/badge/Swift-6%20toolchain-F05138.svg?style=flat&logo=swift&logoColor=white" alt="Swift 6 toolchain"/></a>
  <a href="https://github.com/sponsors/hansjoakimpersson"><img src="https://img.shields.io/badge/GitHub%20Sponsors-Support-EA4AAA.svg?style=flat&logo=githubsponsors&logoColor=ffffff" alt="GitHub Sponsors"/></a>
</p>

PanePilot is a macOS menu bar utility for snapping windows into visual layouts. Hold your chosen drag modifier to open a compact layout picker, hover a zone to preview the result, and release to place the window. You can also use Keyboard Snap to choose a layout and zone with number keys.

![PanePilot icon](docs/assets/panepilot-icon.svg)

## System Requirements

PanePilot supports macOS 13 or later.

Accessibility permission is required. PanePilot uses the public macOS Accessibility APIs to identify, move, and resize windows. Keyboard Snap also uses a CoreGraphics event tap so its trigger, layout digits, zone digits, and Escape handling do not leak into the active app while snap mode is active.

## Installation

Download the latest release archive:

- [PanePilot-latest-macOS.zip](https://github.com/HansJoakimPersson/PanePilot/releases/latest/download/PanePilot-latest-macOS.zip)
- [Project website](https://hansjoakimpersson.github.io/PanePilot/)
- [Releases page](https://github.com/HansJoakimPersson/PanePilot/releases/latest)

Then:

1. Unzip the archive.
2. Move `PanePilot.app` to `/Applications`.
3. Launch PanePilot.
4. Grant Accessibility access in `System Settings` > `Privacy & Security` > `Accessibility`.
5. Open `Settings...` from the menu bar icon to choose shortcuts and manage layouts.

Pre-release note: public notarized downloads and an App Store submission path are not set up yet.

## How to Use It

### Drag Snap

1. Hold the configured Drag Modifier while dragging a window.
2. PanePilot shows a numbered layout picker at the top of the current display.
3. Hover a zone to preview the final window frame.
4. Release the mouse button to snap the window.

The default Drag Modifier is `Command`. You can record a different modifier combination in Settings, or clear the value to disable Drag Snap until a new modifier is recorded.

### Keyboard Snap

1. Press the configured Keyboard Snap shortcut.
2. Press a layout number.
3. Press a zone number.
4. Press `Escape` while choosing a zone to return to layout selection.
5. Press `Escape` while choosing a layout to cancel.

The default Keyboard Snap shortcut is `Option + Escape`. You can record a different shortcut in Settings, or clear the value to disable Keyboard Snap until a new shortcut is recorded.

### Layouts

PanePilot includes built-in layouts such as `40 / 60`, `60 / 40`, mirrored widescreen layouts, and multi-column layouts inspired by Amethyst.

In Settings, you can:

- Create custom layouts.
- Split, resize, merge, and rename zones.
- Reorder layouts with drag and drop.
- Hide layouts from the picker without deleting them.

## Common Known Issues

### PanePilot does nothing after launch

Check Accessibility access:

1. Open `System Settings` > `Privacy & Security` > `Accessibility`.
2. Enable PanePilot.
3. Quit and relaunch PanePilot if events still are not received.

After rebuilding or changing signing identity, macOS can keep a stale Accessibility entry. Remove the old PanePilot entry from Accessibility, launch the app again, and grant access again.

### Picker does not appear while dragging

Try these checks first:

1. Confirm Accessibility is enabled.
2. Confirm the configured Drag Modifier is set and held down.
3. Start dragging from the window title bar.
4. Move the window far enough to pass the drag threshold.
5. Check whether the target app exposes a normal, movable window through Accessibility.

### Keyboard Snap does not start

Try these checks first:

1. Confirm Keyboard Snap has a recorded shortcut in Settings.
2. Try a shortcut that is not already claimed by macOS or another app.
3. Confirm Accessibility is enabled.
4. Check the log for `unable to create an Accessibility event tap`.

If the event tap cannot be created, Keyboard Snap fails closed and does not start.

### A specific app snaps inconsistently

Some apps enforce minimum window sizes or custom resize rules. Electron apps can also expose different Accessibility behavior across windows and app versions. Test the same layout with TextEdit or Finder to separate PanePilot issues from app-specific window behavior.

## View Debug Logging

Open `Settings...` > `Debug` and use `Open Log`.

The log is stored at:

```text
~/Library/Logs/PanePilot/PanePilot.log
```

You can also inspect it from Terminal:

```bash
tail -n 200 "$HOME/Library/Logs/PanePilot/PanePilot.log"
```

Do not paste window titles, full file paths, or other personal activity data into public issues without reviewing the log first.

## Preferences Storage

PanePilot stores small preferences in `UserDefaults` under the app bundle identifier:

```text
com.panepilot.app
```

Custom layouts and layout catalog metadata are stored in:

```text
~/Library/Application Support/PanePilot/
```

Debug logs are stored in:

```text
~/Library/Logs/PanePilot/
```

## Uninstallation

Quit PanePilot and move `PanePilot.app` to the Trash.

To remove stored preferences:

```bash
defaults delete com.panepilot.app
```

To remove custom layouts, delete:

```text
~/Library/Application Support/PanePilot/
```

Back up that folder first if you want to keep custom layouts.

## Running the App in Xcode (for developers)

Requirements:

- Xcode command line tools
- Swift 6 toolchain with SwiftPM tools support for 6.1

Useful commands:

```bash
swift build
swift test
make app
make run
```

You can also open `PanePilot.xcodeproj` in Xcode for app target management, signing, entitlements, archive, and export work.

If a local agent or CI sandbox blocks SwiftPM cache access, use project-local caches:

```bash
mkdir -p .cache/clang .cache/swiftpm
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/swiftpm" \
swift test --disable-sandbox
```

## Contributing

PanePilot is still pre-release. Issues and focused pull requests are welcome, especially around:

- Window compatibility reports with specific apps.
- Keyboard Snap regressions.
- Accessibility and event tap behavior.
- Layout editor and picker usability.
- Distribution, signing, and packaging improvements.

Before opening a pull request, run:

```bash
swift test
xcodebuild -scheme PanePilot -configuration Debug -destination 'platform=macOS' build
```

## Support

If you want to support PanePilot or whatever I build next:

- [GitHub Sponsors](https://github.com/sponsors/hansjoakimpersson)

## License

PanePilot is licensed under `AGPL-3.0-only`.

Unless explicitly stated otherwise, the source code in this repository and binaries produced from it are distributed under that same license.
