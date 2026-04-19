# PanePilot Architecture

Project-specific architecture, conventions, priorities, and verification rules. Takes precedence over `AGENTS.md` when they conflict.

## Project Summary

- PanePilot is a macOS 13+ menu bar utility for snapping windows into layouts.
- The app relies on macOS Accessibility APIs to inspect and move windows.
- The repo uses Swift Package Manager, a `Makefile`, and an Xcode project.
- The committed Xcode project is `PanePilot.xcodeproj`.
- `Sources/PanePilotKit` contains the app logic, AppKit settings UI, layout logic, permissions, packaging helpers, and platform integration.
- `Sources/PanePilot` contains the executable entry point and `MenuBarExtra`.
- `Tests/PanePilotKitTests` contains logic tests.

## Platform Facts

| Key | Value |
|-----|-------|
| Minimum platform | macOS 13 |
| SwiftPM tools version | 6.2 |
| Xcode Swift language mode | Swift 6 |
| Main executable target | `PanePilot` |
| Main library target | `PanePilotKit` |
| Xcode project | `PanePilot.xcodeproj` |
| App bundle (dev) | `.build/PanePilot.app` |
| Release archive | `dist/PanePilot-<version>-macOS.zip` |
| Packaging entry point | `Makefile` |

## Core Priorities

When tradeoffs are unclear, prefer this order:

1. Preserve correct snap behavior and permission handling.
2. Preserve App Store and signed-distribution viability.
3. Make the code easier for a human to read and debug.
4. Keep hot paths efficient.
5. Minimize architectural churn.

## Module Structure

| Path | Role |
|------|------|
| `Sources/PanePilot/` | App entry point, `MenuBarExtra` scene only |
| `Sources/PanePilotKit/` | All application logic, UI controllers, system integration, utilities |
| `Tests/PanePilotKitTests/` | Unit tests for logic and behavior exercisable without UI automation |
| `PanePilot.xcodeproj/` | Xcode target wiring, signing, entitlements, embedding, archive/export |
| `Config/` | Entitlements and export/signing configuration files |

Keep the executable target thin. Feature logic belongs in `PanePilotKit`.

Keep feature-specific helpers near their owner until reuse clearly justifies extraction.

## Architecture Rules

- Treat `PanePilotKit` as the main home for application logic.
- AppKit is the primary UI framework. SwiftUI currently exists only at the app entry point and `MenuBarExtra` boundary.
- Do not force a pure SwiftUI architecture onto AppKit-heavy code unless explicitly requested.
- Keep the current folder layout as the source layout for both SwiftPM and Xcode.
- Keep geometry, layout math, persistence, platform access, and UI orchestration separated by responsibility.
- Avoid pushing non-UI logic into view/controller classes when a helper type would make ownership clearer.
- When you add a new subsystem, include a short comment or structure that makes its boundary obvious.

## SwiftPM vs Xcode

Both build systems matter, but they do not have the same job.

**SwiftPM is the preferred source of truth for:**
- source layout
- module boundaries
- CI-friendly builds and tests
- lightweight local verification

**Xcode is the preferred source of truth for:**
- app target composition
- framework embedding
- entitlements
- signing
- sandbox configuration
- archive/export work

Rules:
- Do not let SwiftPM and Xcode drift silently.
- If you add, move, or rename sources/resources, update both `Package.swift` and `PanePilot.xcodeproj/project.pbxproj`.
- If a change is packaging-only or signing-only, keep that detail in Xcode rather than polluting SwiftPM.
- If a change is module-structure or source-layout related, make SwiftPM correct first and then mirror it in Xcode.
- Do not duplicate logic between the `Makefile` and Xcode without a good reason.
- Call out when one build path has been verified but the other has not.

## Hot Paths

Treat these as performance-sensitive unless proven otherwise:

- drag tracking
- snap target calculation
- overlay updates
- Accessibility queries and writes
- any repeated view redraw/update path

For those paths:
- Keep main-thread work tight.
- Avoid unnecessary allocations in loops or drag handlers.
- Avoid repeated AX lookups when the same data is already available.
- Avoid redraw churn.
- Prefer measured improvements over speculative micro-optimizations.

## Permissions

PanePilot interacts with other apps through Accessibility APIs. Changes touching any of the following require extra scrutiny:

- permissions
- sandboxing
- startup/login behavior
- cross-app control
- diagnostics/logging
- bundle metadata
- entitlements

Rules:
- Request only the access the app genuinely needs.
- Preserve a clear, honest explanation of why Accessibility access is needed.
- Degrade gracefully when permission is missing.
- Process data on-device.
- Be conservative with logging — window titles, bundle identifiers, display names, and interaction traces are user-sensitive.
- If data collection or third-party integrations change, call out the need to update App Store privacy metadata and privacy policy.

## Packaging

- Treat `Makefile` as part of the product, not a side detail.
- If a change affects bundle metadata, permissions, versioning, signing, resources, or launch behavior, verify the packaging step too.
- Keep `Info.plist` contents aligned with code behavior.
- If a new capability requires a usage description or entitlement, update packaging/signing paths accordingly.
- Keep Mac App Store assumptions separate from direct-download/Developer ID assumptions.
- Do not silently break one distribution path while improving the other.

## Verification

Minimum after any code change:

```bash
swift build
xcodebuild -project PanePilot.xcodeproj -scheme PanePilot -configuration Debug -destination 'platform=macOS' build
```

Also run `swift test` when:
- logic changes
- persistence changes
- layout math changes
- selection or preview behavior changes
- public behavior changes

Run packaging/smoke checks when relevant:

```bash
make app
make run
make package CONFIGURATION=release VERSION=<version> BUILD_NUMBER=<n>
xcodebuild -project PanePilot.xcodeproj -scheme PanePilot -configuration Debug -destination 'platform=macOS' test
```

If a UI or bundle-level change cannot be fully validated in the current environment, state that clearly.

## Git Conventions

- Keep commit messages short and specific.
- Never mention Claude Code, any LLM, tool, vendor, or model name in commit messages, PR descriptions, PR comments, or issue comments.
- Do not include a "Test plan" section in PR descriptions unless explicitly requested.

Branch naming:
- Release/version branches: plain version names — `1.1.0`, `1.0.x`
- Task branches: short descriptive names — `settings-window`, `layout-catalog-cleanup`
- Do not use names containing tool, vendor, or model branding.

## Non-Negotiable Standards

- Use only public Apple APIs.
- Do not introduce third-party dependencies without explicit approval.
- Do not add hidden background behavior, login items, helpers, or privilege escalation casually.
- Do not trade readability for cleverness.
- Do not assume a change is Mac App Store safe just because it works locally.
- Do not weaken privacy messaging, permission messaging, or bundle metadata accuracy.

## App Store Review Checklist

Before considering a product-facing change done:

- Does it rely only on public Apple APIs?
- Does it remain compatible with App Sandbox expectations?
- Does it add any new permission, entitlement, or sensitive data access?
- Does it require updated `Info.plist`, signing, or privacy metadata?
- Does it introduce startup, login, background, installer, or updater behavior that could create review problems?
- Does it need a clearer user-facing explanation or fallback path?

If any answer is "maybe", surface that explicitly.

## Readability Checklist

Before considering a file done:

- Can a human quickly tell what this type is responsible for?
- Are the most important methods near the top?
- Are `MARK` sections helping navigation?
- Are names descriptive?
- Are comments explaining intent rather than restating syntax?
- Would a less context-loaded developer know where to make the next change?

## In Doubt

- Prefer official Apple guidance over blogs.
- Prefer the simpler implementation that a human can debug.
- Prefer explicit tradeoff notes over silent assumptions.
- Raise App Store risk early.
- Official references: App Review Guidelines, App Sandbox, Configuring the macOS App Sandbox, App privacy details, Developer ID / notarization guidance.
