# PanePilot Agent Guide

This file defines how an LLM agent should work in this repository.

It is intentionally opinionated. PanePilot is a macOS utility app with distribution goals that are stricter than "it builds on my machine". Every change should be evaluated for:

1. product correctness
2. human readability and maintainability
3. runtime efficiency on hot paths
4. Mac App Store viability
5. release and packaging correctness

## Project Summary

- PanePilot is a macOS 13+ menu bar utility for snapping windows into layouts.
- The app relies on macOS Accessibility APIs to inspect and move windows.
- The repo uses Swift Package Manager, a `Makefile`, and an Xcode project.
- The committed Xcode project is `PanePilot.xcodeproj`.
- `Sources/PanePilotKit` contains the app logic, AppKit settings UI, layout logic, permissions, packaging helpers, and platform integration.
- `Sources/PanePilot` contains the executable entry point and `MenuBarExtra`.
- `Tests/PanePilotKitTests` contains logic tests.

## Core Priorities

When tradeoffs are unclear, prefer this order:

1. preserve correct snap behavior and permission handling
2. preserve App Store and signed-distribution viability
3. make the code easier for a human to read and debug
4. keep hot paths efficient
5. minimize architectural churn

## Non-Negotiable Standards

- Use only public Apple APIs.
- Do not introduce third-party dependencies without explicit approval.
- Do not add hidden background behavior, login items, helpers, or privilege escalation casually.
- Do not trade readability for cleverness.
- Do not assume a change is Mac App Store safe just because it works locally.
- Do not weaken privacy messaging, permission messaging, or bundle metadata accuracy.

## Platform Facts

- Minimum platform: `macOS 13`
- SwiftPM tools version: `6.1`
- Xcode Swift language mode: `Swift 6`
- Main executable target: `PanePilot`
- Main library target: `PanePilotKit`
- Xcode project: `PanePilot.xcodeproj`
- Packaging path: `Makefile`
- App bundle path after packaging: `.build/PanePilot.app`
- Release archive path: `dist/PanePilot-<version>-macOS.zip`

## Architecture Rules

- Treat `PanePilotKit` as the main home for application logic.
- Keep the executable target thin. It should primarily host app startup and the menu bar scene.
- Keep the current folder layout as the source layout for both SwiftPM and Xcode.
- AppKit is the primary UI framework in this repo. SwiftUI currently exists at the app entry/menu bar boundary.
- Do not force a pure SwiftUI architecture onto AppKit-heavy code unless the user explicitly asks for that refactor.
- Keep geometry, layout math, persistence, platform access, and UI orchestration separated by responsibility.
- Avoid pushing non-UI logic into view/controller classes when a helper type would make ownership clearer.

## SwiftPM vs Xcode

Both build systems matter in this repo, but they do not have the same job.

- SwiftPM is the preferred source of truth for:
  - source layout
  - module boundaries
  - CI-friendly builds and tests
  - lightweight local verification
- Xcode is the preferred source of truth for:
  - app target composition
  - framework embedding
  - entitlements
  - signing
  - sandbox configuration
  - archive/export work

When changing the project:

- Do not let SwiftPM and Xcode drift silently.
- Keep the distinction between SwiftPM tools version and Xcode Swift language mode explicit in docs and settings.
- If you add, move, or rename sources/resources, update both `Package.swift` and `PanePilot.xcodeproj` when needed.
- If a change is packaging-only or signing-only, prefer keeping that detail in Xcode rather than polluting SwiftPM.
- If a change is module-structure or source-layout related, prefer making SwiftPM correct first and then mirror it in Xcode.
- Do not duplicate logic between the `Makefile` and Xcode without a good reason.
- Call out when one build path has been verified but the other has not.

## Code Quality Rules

- Optimize for the next human reader.
- Prefer descriptive names over abbreviations.
- Prefer explicit control flow over dense one-liners when the explicit version is easier to debug.
- Use early returns to keep nesting shallow.
- Avoid force unwraps and `try!` unless failure is unrecoverable and clearly justified.
- Keep one primary type per file unless small helper types are tightly coupled and private.
- Use `// MARK:` sections in non-trivial files.
- Split large functions when they have multiple responsibilities, repeated logic, or hidden invariants.
- Remove dead code and duplicated branches introduced by refactors.

## Documentation Rules

- Inline comments should explain why, constraints, invariants, review risks, or non-obvious math.
- Do not add comments that merely paraphrase syntax.
- Add documentation comments for reusable types/functions or code with non-obvious contracts.
- Keep the repo readable without external tribal knowledge.
- When you add a new subsystem, include a short comment or structure that makes its boundary obvious.
- If user-visible behavior changes, update `README.md` when appropriate.

## Efficiency Rules

Treat these as hot paths unless proven otherwise:

- drag tracking
- snap target calculation
- overlay updates
- Accessibility queries and writes
- any repeated view redraw/update path

For those paths:

- keep main-thread work tight
- avoid unnecessary allocations in loops or drag handlers
- avoid repeated AX lookups when the same data is already available
- avoid redraw churn
- prefer measured improvements over speculative micro-optimizations

For SwiftUI code:

- keep `body` computations cheap
- keep data dependencies narrow
- move expensive formatting/computation out of `body`
- use previews where practical for pure SwiftUI views, but do not invent previews for AppKit-heavy code just to satisfy a style rule

## macOS App Store Rules

Mac App Store requirements are a first-class design constraint in this repo.

- Any app-store-facing build must remain compatible with App Sandbox.
- Use the minimum entitlements and permissions necessary for the feature.
- Any new protected capability must be justified in code review/output summary.
- Keep the app self-contained. Do not add custom installers, downloaded code, alternate update mechanisms, or external resources that materially change app functionality for the App Store build.
- Do not add auto-launch or start-at-login behavior without explicit user consent.
- Do not add root privileges, setuid behavior, or privileged helpers.
- Avoid deprecated or optionally installed technologies.
- Keep the app functional on the current shipping macOS.
- If a feature may create App Review risk, call it out explicitly rather than assuming it is acceptable.

Because PanePilot interacts with other apps through Accessibility APIs, changes touching any of the following require extra scrutiny:

- permissions
- sandboxing
- startup/login behavior
- cross-app control
- diagnostics/logging
- bundle metadata
- entitlements

## Privacy and Permission Rules

- Request only the access the app genuinely needs.
- Preserve a clear, honest explanation of why Accessibility access is needed.
- Degrade gracefully when permission is missing.
- Process data on-device whenever possible.
- Be conservative with logging. Window titles, bundle identifiers, display names, and interaction traces may be user-sensitive.
- If app data collection or third-party integrations change, call out the need to update App Store privacy metadata and privacy policy.

## Packaging and Distribution Rules

- Treat `Makefile` as part of the product, not a side detail.
- If a change affects bundle metadata, permissions, versioning, signing, resources, or launch behavior, verify the packaging step too.
- Keep `Info.plist` contents aligned with code behavior.
- If a new capability requires a usage description or entitlement, update packaging/signing paths accordingly.
- Keep Mac App Store assumptions separate from direct-download/Developer ID assumptions.
- Do not silently break one distribution path while improving the other.

## Testing and Verification

Minimum expectation after code changes:

- run `swift build`

Also run `swift test` when:

- logic changes
- persistence changes
- layout math changes
- selection or preview behavior changes
- public behavior changes

Run packaging/smoke checks when relevant:

- `make app`
- `make package CONFIGURATION=release VERSION=<version> BUILD_NUMBER=<n>`
- `make run`
- `xcodebuild -project PanePilot.xcodeproj -scheme PanePilot -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -project PanePilot.xcodeproj -scheme PanePilot -configuration Debug -destination 'platform=macOS' test`

If a UI or bundle-level change cannot be fully validated in the current environment, state that clearly.

## Preferred Change Workflow

Before editing:

1. understand the local architecture and affected files
2. identify any hot-path, permission, sandbox, or packaging impact
3. choose the smallest coherent change that solves the problem

While editing:

1. keep files structured
2. extract helpers when they improve readability
3. add concise comments only where they reduce cognitive load

After editing:

1. re-read the changed files for clarity
2. remove duplication introduced by refactor
3. run the relevant verification commands
4. summarize behavior impact, App Store/distribution impact, and verification results

## File and Module Conventions

- `Sources/PanePilot/`
  - app entry point only
- `Sources/PanePilotKit/`
  - application logic, UI controllers, system integration, utilities
- `Tests/PanePilotKitTests/`
  - unit tests for logic and behavior that can be exercised without UI automation
- `PanePilot.xcodeproj/`
  - Xcode app/framework/test target wiring
  - signing, entitlements, embedding, archive/export behavior
- `Config/`
  - entitlements and export/signing related configuration files

Keep feature-specific helpers near their owner until reuse clearly justifies extraction.

## Readability Checklist

Before considering a file "done", check:

- Can a human quickly tell what this type is responsible for?
- Are the most important methods near the top?
- Are `MARK` sections helping navigation?
- Are names descriptive?
- Are comments explaining intent rather than restating syntax?
- Would a less context-loaded developer know where to make the next change?

If not, the file is not done.

## App Store Review Checklist

Before considering a product-facing change "done", check:

- Does it rely only on public Apple APIs?
- Does it remain compatible with App Sandbox expectations?
- Does it add any new permission, entitlement, or sensitive data access?
- Does it require updated `Info.plist`, signing, or privacy metadata?
- Does it introduce startup, login, background, installer, or updater behavior that could create review problems?
- Does it need a clearer user-facing explanation or fallback path?

If any answer is "maybe", surface that explicitly.

## References for Platform Decisions

When platform behavior or review requirements are in doubt, prefer official Apple documentation first:

- App Review Guidelines
- App Sandbox
- Configuring the macOS App Sandbox
- App privacy details / App Store Connect privacy metadata
- Developer ID / notarization guidance for direct distribution

## In Doubt

- Prefer official Apple guidance over blogs.
- Prefer the simpler implementation that a human can debug.
- Prefer explicit tradeoff notes over silent assumptions.
- Raise App Store risk early.
