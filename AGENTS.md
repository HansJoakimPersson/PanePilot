# AGENTS.md - macOS Swift App v1.1

Guidance for agents working in macOS applications written in Swift. Apply the whole guide with judgment: some sections
only matter when the project has that surface, but the standards are part of the main document rather than separate
profiles.

## How To Use This Guide

- Read the whole file once when starting work in a macOS Swift project.
- Apply SwiftPM rules when the project has `Package.swift`.
- Apply Xcode rules when the project has an `.xcodeproj` or `.xcworkspace`.
- Apply SwiftUI/AppKit rules according to the UI technology already in use.
- Apply persistence, permissions, distribution, packaging, and dependency rules whenever the change touches those
  surfaces.
- Local project-specific instructions, `CLAUDE.md`, and local `AGENTS.md` files always take precedence when present.

## Core Rules

### Operating Principles

- Keep changes minimal and localized.
- Preserve established public APIs, user-visible workflows, bundle behavior, permissions, and distribution assumptions
  unless the task explicitly changes them.
- Treat product correctness, user safety, privacy, and distribution viability as first-class constraints.
- Prefer public Apple APIs and platform conventions.
- Do not introduce dependencies, background behavior, privileged helpers, login items, external services, telemetry, or
  alternate update mechanisms without explicit approval.
- Keep the build green. Do not proceed if tests fail.
- Call out App Store, privacy, permission, sandbox, signing, or packaging risk whenever a change touches those areas.

### Workflow

1. Read local project instructions before starting any task. If `CLAUDE.md` or `AGENTS.md` exists, read it.
2. In Clarity Framework projects, read project documentation in this order:
   - `docs/00-ai-context.md` — compressed overview of what the app is, its stack, and current status
   - `docs/09-grafisk-profil.md` — design tokens, colour palette, typography, and spacing; read before touching
     any visual value. If this file does not exist, do not hardcode visual values — raise the gap instead.
   - `docs/03-sad.md` — architecture, component responsibilities, and key design decisions
   - `docs/02-kravdokumentation.md` — requirements context when the task touches functional behavior or product scope
   - `docs/05-deployment-view.md` — distribution and packaging context when the task affects builds or releases
3. Read relevant source, build settings, package files, entitlements, and resources before proposing changes.
4. Identify the affected surface: domain logic, UI, persistence, permissions, sandboxing, signing, packaging,
   distribution, hot paths, or external integration.
5. Use TDD for non-trivial logic: write or update the failing test first, implement the smallest change, then refactor
   while keeping tests green.
6. Update all build-system references when files, resources, targets, bundles, or schemes change.
7. Run relevant SwiftPM and Xcode verification when feasible.
8. Report changed files, commands run, test results, behavior impact, distribution impact, and any residual risks.

### Swift Style

- Follow the project's formatter, Swift version, and Swift language mode first.
- Use descriptive names and explicit control flow.
- Prefer value types, immutable state, and constructor validation where they fit the model.
- Use access control deliberately; keep implementation details `private` or `fileprivate` where practical.
- Use early returns to keep nesting shallow.
- Avoid force unwraps, `try!`, and implicitly unwrapped optionals unless failure is truly unrecoverable and documented
  by context.
- Preserve thrown error context when wrapping or translating errors.
- Keep one primary type per file unless private helper types are tightly coupled.
- Use `// MARK:` in non-trivial files.
- Add documentation comments for public or reused types with non-obvious contracts.
- Document invariants, permissions, safety rules, and user-visible behavior changes.
- Do not add comments that merely restate syntax.

### Concurrency and Runtime Safety

- Keep UI updates on the main actor.
- Do not block the main thread with file I/O, rendering, hashing, network calls, database work, or long computations.
- Use cancellation-aware async work for long-running operations.
- Make progress reporting possible for user-visible long-running tasks.
- Avoid unstructured concurrency unless there is a clear ownership and cancellation story.
- Keep shared mutable state isolated through actors, the main actor, locks, or other explicit synchronization.
- Treat repeated UI updates, file scanning, rendering, hashing, database access, event tracking, interprocess calls, and
  platform API queries as potential hot paths.
- Avoid unnecessary allocations in tight loops.
- Avoid repeated expensive API calls when data can be cached safely.
- Prefer measured performance improvements over speculative micro-optimizations.

### Logging and Security

- Use the project's logging framework; prefer structured or privacy-aware logging where available.
- Never log secrets, credentials, tokens, personal data, full paths, filenames, window titles, bundle identifiers,
  pasteboard content, or user activity unless the project explicitly treats that data as safe.
- Redact or summarize sensitive values before logging.
- Keep user-facing messages clean and actionable.
- Do not expose stack traces or internal implementation details to end users.

### Configuration

- Do not hardcode environment-specific paths, URLs, bundle identifiers, team IDs, signing identities, feature flags, or
  secrets in source code.
- Use the project's configuration mechanism: build settings, `.xcconfig`, plist files, command-line arguments,
  environment values, or ignored local config.
- Keep local defaults safe and convenient without accidentally becoming release defaults.
- Validate critical configuration at startup or build time and fail fast with clear messages.
- Keep secrets out of committed config files.

### Testing

- Prefer TDD for pure logic, policies, state transitions, parsing, persistence rules, file action safety, permissions
  decisions, and bug fixes.
- A practical TDD loop is: failing test, smallest implementation, green test, refactor.
- Use Apple's XCTest framework for Swift unit tests and integration-style tests unless the project has an established
  alternative.
- Use XCUITest for UI tests that verify real user flows, windows, menus, dialogs, permissions messaging, onboarding, and
  regression-prone interactions.
- Unit test pure logic and policy code with XCTest.
- Add integration tests for filesystem, persistence, rendering, platform adapters, or resource loading when practical.
- Smoke test user-critical flows after UI, permission, or bundle changes.
- Keep UI tests focused on user-visible behavior rather than implementation details.
- Prefer testability through dependency injection and protocol boundaries over reflection or fragile UI timing.
- Do not remove tests unless explicitly requested.
- Do not skip failing tests without explicit approval.
- If UI automation, permission prompts, signing, packaging, or App Store paths cannot be validated locally, say so
  explicitly.

### Documentation and Hygiene

- Update README, usage docs, release notes, privacy notes, or design notes when user-visible behavior, permissions, or
  distribution behavior changes.
- In Clarity Framework projects, update the relevant docs when their content changes:
  - `docs/03-sad.md` — when architecture or key design decisions change
  - `docs/05-deployment-view.md` — when distribution, packaging, signing, or App Store behavior changes
  - `docs/06-testdokumentation.md` — when testing strategy or coverage targets change
  - `docs/08-andringshantering.md` — for change tracking and ADRs
  - `docs/00-ai-context.md` — when stack, status, or key context shifts significantly
- Keep generated files out of source control unless the project intentionally tracks them.
- Do not reformat unrelated files.
- Do not make drive-by refactors.
- Do not leave commented-out code behind.

### Definition of Done

- Behavior is implemented and scoped to the request.
- The app or package builds through the relevant build path.
- Relevant tests pass with no known regressions.
- SwiftPM, Xcode, packaging, signing, permissions, and distribution checks have run when the change touches those
  surfaces.
- Public behavior, documentation, privacy messaging, and configuration are aligned.
- Relevant Clarity Framework docs are updated when their content is affected.
- No unrelated dependency churn, formatting churn, or refactoring is included.
- Completion notes always include modified files.
- Completion notes always include commands executed.
- Completion notes always include test results.
- Completion notes call out permission, privacy, entitlement, App Store, signing, packaging, and residual runtime risks
  when relevant.
- If tests or checks could not run locally, explain why and name the CI pipeline, scheme, destination, or command that
  should run instead.

### Explicitly Forbidden

- Private Apple APIs.
- Hidden background behavior, login items, helpers, privilege escalation, telemetry, or external network behavior
  without explicit approval.
- Automatic destructive file operations without explicit user intent.
- Hardcoded secrets, signing credentials, team-specific private values, personal data, or production-only configuration.
- Weakening privacy messaging, permission explanations, sandboxing, entitlements, or bundle metadata accuracy.
- Skipping or suppressing failing tests without explicit approval.

## SwiftPM

Use these rules when the project has `Package.swift`.

### SwiftPM Commands

```bash
swift build
swift test
swift package resolve
```

Run only commands that apply to the project.

### Package Rules

- Keep `Package.swift` as the source of truth for package targets, module boundaries, dependencies, and resources.
- Update `Package.swift` when adding, moving, renaming, or removing source files/resources if the package layout
  requires it.
- Keep libraries as plain Swift package products when practical.
- Do not add dependencies unless the task requires them.
- Prefer Apple frameworks, Foundation, and existing project utilities before adding packages.
- Explain why each new package dependency is needed.

## Xcode App

Use these rules when the project has an `.xcodeproj` or `.xcworkspace`.

### Xcode Commands

Use project-specific schemes and destinations:

```bash
xcodebuild -scheme AppName -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme AppName -configuration Debug -destination 'platform=macOS' test
```

### Xcode Rules

- Keep Xcode project settings aligned with SwiftPM when both are present.
- Use Xcode settings for app targets, bundle identifiers, resources, entitlements, signing, sandboxing, capabilities,
  archives, and exports.
- If files/resources are added, moved, renamed, or deleted, update the Xcode project references.
- Do not rely on Xcode-only generated behavior unless CI and command-line builds also work.
- Keep schemes, build settings, and signing changes minimal and intentional.
- State clearly when only SwiftPM or only Xcode has been verified.

## SwiftUI

Use these rules when the app UI is primarily SwiftUI.

- Keep `body` computations cheap.
- Move expensive formatting, filtering, file I/O, networking, database work, and rendering out of `body`.
- Keep view state narrow and explicit.
- Use view models or observable state only where they clarify ownership.
- Keep domain logic out of views.
- Add previews where practical for reusable pure SwiftUI views, but do not invent previews for platform-heavy views just
  to satisfy a rule.
- Preserve accessibility labels, keyboard navigation, focus behavior, dynamic type where relevant, and contrast.

## AppKit

Use these rules when the app uses AppKit, mixed SwiftUI/AppKit, menu bar UI, tables, outline views, panels, or
platform-specific controls.

- Keep AppKit controllers and delegates thin relative to domain/application logic.
- Use AppKit-backed views for heavy tables, outlines, text systems, menu bar behavior, inspectors, or platform-specific
  controls when SwiftUI is a poor fit.
- Keep main-thread work small during event tracking, drawing, layout, drag/drop, and accessibility interactions.
- Preserve responder chain, menu command, focus, undo, keyboard shortcut, and accessibility behavior.
- Do not force a pure SwiftUI rewrite onto AppKit-heavy code unless explicitly requested.

## Persistence

Use these rules when the app stores data using files, SQLite, Core Data, SwiftData, UserDefaults, keychain, caches, or
bookmarks.

- Follow the storage technology already chosen by the project.
- Prefer simple file storage or SQLite for local-first apps when that fits the data model.
- Use Core Data or SwiftData only when object graph management, migrations, predicates, or platform integration justify
  it.
- Use UserDefaults only for small preferences, not user documents or large state.
- Use keychain for secrets and credentials.
- Keep caches disposable and rebuildable.
- Use security-scoped bookmarks for sandboxed file access when needed.
- Test migrations, file format changes, and persistence compatibility.
- Never silently delete or rewrite user data without explicit user intent and a recovery story.

## Permissions and Privacy

Use these rules when the app touches protected resources, user data, or platform capabilities.

- Request only the permissions the feature genuinely needs.
- Preserve clear, honest user-facing explanations for permissions.
- Degrade gracefully when permission is missing, denied, revoked, or partially available.
- Process data on-device whenever practical.
- Keep `Info.plist` usage descriptions aligned with actual behavior.
- Update privacy documentation or metadata when data collection, protected capabilities, diagnostics, or third-party
  integrations change.
- Treat file paths, filenames, window titles, bundle identifiers, pasteboard content, screenshots, and interaction
  traces as potentially sensitive.
- Do not add Accessibility, automation, file access, notifications, login item, camera, microphone, contacts, or
  calendar behavior casually.

## App Store and Distribution

Use these rules when App Store viability, signing, sandboxing, entitlements, or distribution can be affected.

- Use the minimum entitlements necessary.
- Keep App Sandbox compatibility intact for App Store-facing builds.
- Keep `Info.plist`, entitlements, signing settings, privacy metadata, and code behavior aligned.
- Do not add downloaded executable code, custom installers, alternate update mechanisms, root privileges, setuid
  behavior, or privileged helpers without explicit approval.
- Keep direct-download and App Store assumptions separate when both distribution paths exist.
- Avoid deprecated or optionally installed technologies unless the project already depends on them.
- Call out App Review risk explicitly instead of assuming a locally working feature is acceptable.

## Packaging and Runtime

Use these rules when producing an `.app`, installer, zip, DMG, CLI helper, launch item, or release artifact.

- Prefer a clean `.app` bundle for GUI apps and plain binaries/helpers only when they are truly needed.
- Keep dev-only tools, test fixtures, generated debug files, and local config out of runtime artifacts.
- Verify resources are packaged correctly when adding files to app bundles or package resources.
- Keep startup behavior deterministic and fail fast on invalid configuration.
- If bundle metadata, entitlements, permissions, signing, resources, launch behavior, or versioning changes, verify
  packaging.
- Do not silently break one distribution path while improving another.
- Document how to build and run the artifact when packaging behavior changes.

## Dependency Policy

Use these rules when adding, removing, or upgrading dependencies.

- Prefer Apple frameworks, Foundation, Swift standard library, and existing project utilities before adding
  dependencies.
- Avoid small one-off dependencies for trivial utilities.
- Prefer actively maintained, widely used packages with compatible licenses.
- Be cautious with packages that introduce network behavior, native binaries, code generation, background services, or
  broad permissions.
- Pin versions through the project's existing package-management mechanism.
- Remove unused dependencies when discovered as part of the task.
- Explain why each new dependency is needed.
