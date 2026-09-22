# Hideout agent instructions

Keep these local project conventions aligned with the current source and Xcode
project settings when the repository changes.

## Project contract

- Project: Hideout, a sandboxed AppKit menu bar utility.
- Platform: macOS 27.0 or later.
- Language mode: Swift 6.0 with complete strict concurrency
  (`SWIFT_STRICT_CONCURRENCY = complete`).
- Xcode project and scheme: `Hideout.xcodeproj`, `Hideout`.
- No external Swift Package dependencies. Global shortcuts use the native
  Carbon Event Manager API.
- Runtime state and UI work belong to `@MainActor`-isolated AppKit code.
- The project has one XCTest target, `HideoutTests`.
- Verify menu bar behavior when a change affects interaction or layout.

## Work sequence

1. Inspect `git status`, the relevant source, and the nearest project files
   before editing. Treat existing staged and unstaged changes as user-owned.
2. Make the smallest focused change that matches the current AppKit
   architecture and localization setup.
3. Preserve the `hiddenbar_*_v27` status-item autosave names and declaration
   order. The `_v27` suffix intentionally isolates the macOS 27 layout from
   older versions, so an existing installation may need a one-time `⌘`-drag
   after upgrading. Do not rename or reorder these items without rechecking
   menu bar placement.
4. Verify the changed behavior and run the build/checks below. Record skipped
   checks and their reason in the handoff.

Git state changes such as staging, committing, branching, pushing, or merging
require an explicit user request.

## Verification

```sh
xcodebuild -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Debug \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Release \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild test -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

find Hideout -name '*.strings' -print0 | xargs -0 plutil -lint
```

Use `README.md` for product behavior and `CONTRIBUTING.md` for the project
workflow. Inspect the relevant source before changing the collapse mechanism,
status-item ordering, login item, or global event handling.

## Completion

The task is complete when the requested files are updated, the local
`AGENTS.md` reflects the current project contract, the applicable build and
validation checks pass, and the final handoff identifies any remaining manual
or hardware-only checks.
