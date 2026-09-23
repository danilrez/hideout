# Contributing to Hideout

Hideout is a sandboxed AppKit menu bar utility. The current development target
is macOS 27.0 or later, built with Xcode 27 and Swift 6 in complete strict
concurrency mode. The project does not support older macOS deployment targets.

## Before you start

For a small fix, open a pull request with a clear description of the problem.
For a larger behavior or architecture change, open an issue first so the
direction can be discussed before implementation. Please include screenshots
or a short reproduction when the change affects the menu bar or preferences
window.

The project follows the [Contributor Covenant][code-of-conduct]. Report
unacceptable behavior to the maintainers through the repository or at
`code.cli.agent@gmail.com`.

## Development setup

Open `Hideout.xcodeproj` in Xcode 27. The app has no external Swift Package
dependencies; global shortcuts use the native Carbon Event Manager API.

The command-line build used for local verification is:

```sh
xcodebuild -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Debug \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Also validate the Release configuration before submitting a change:

```sh
xcodebuild -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Release \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Do not override `MACOSX_DEPLOYMENT_TARGET` or `SWIFT_VERSION` when verifying a
change. They are part of the project contract: macOS 27.0 and Swift 6.0.

The project has one XCTest target, `HideoutTests`. Run the full suite with:

```sh
xcodebuild test -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

A successful test run is required, and behavioral changes must also be checked
against the real menu bar. For UI or interaction changes, manually verify
collapse/expand, auto-hide, the global shortcut, login item registration, and a
multi-display setup on macOS 27. If the change touches hover-to-expand or
status-item ordering, verify those paths as well. Check localized resources
with:

```sh
find Hideout -name '*.strings' -print0 | xargs -0 plutil -lint
```

## Release DMG

Releases are created from version tags. Keep `MARKETING_VERSION` in the Xcode
project aligned with the numeric part of the tag. The current project version
is `0.1.2` (build `3`), so create the stable release tag with:

```sh
git tag v0.1.2
git push origin v0.1.2
```

The `Release DMG` workflow builds a macOS 27 Release archive, seals
`Hideout.app` with an ad-hoc signature, verifies it, and publishes the DMG with
an `Applications` shortcut and SHA-256 checksum. Ad-hoc signing is not
Developer ID signing or notarization, so macOS may require confirmation on
first launch.

## Repository layout

- `Hideout/` — application source, storyboard, resources, and localizations.
- `Hideout.xcodeproj/` — target settings, build configurations, and the test
  scheme.

Derived data, build products, Xcode user data, and other generated files do not
belong in a pull request.

## Coding guidelines

- Keep AppKit state and UI work on `@MainActor`; resolve Swift 6 isolation
  errors instead of masking them with `@unchecked Sendable`.
- Use the macOS 27 APIs and behavior already established in the source. Keep
  the deployment target and Swift language mode aligned with the Xcode project.
- Preserve the existing `hiddenbar_*_v27` status-item autosave names and their
  declaration order. The `_v27` suffix intentionally isolates the macOS 27
  layout from older versions, so an existing installation may need a one-time
  `⌘`-drag after upgrading. Do not rename or reorder these items without
  rechecking menu bar placement.
- Keep the app sandboxed and avoid adding entitlements, network access,
  subprocesses, or dependencies without an explicit design decision.
- Put user-visible strings in the localization resources and update the
  storyboard companion strings when changing storyboard text.
- Prefer focused changes that match the existing AppKit architecture. Do not
  reformat unrelated files or edit generated artifacts.

## Branches and pull requests

Branches are created from `main` and should use a short descriptive prefix,
for example `feature/hover-to-expand`, `fix/login-item-state`, or
`maintenance/contributing-guide`.

A pull request should state:

1. What user-visible or maintenance problem it solves.
2. Which behavior or files changed.
3. What was verified, including the exact build command and any manual menu bar
   checks.
4. Any known limitation or migration step for existing installations.

Keep commits focused, do not include secrets or local configuration, and do not
commit DerivedData or Xcode user state.

## Code of Conduct

This project follows the [Contributor Covenant, version 3.0][code-of-conduct].
Participation is expected to be respectful, constructive, and free from
harassment. Maintainers may remove or reject contributions that violate these
standards.

[code-of-conduct]: https://www.contributor-covenant.org/version/3/0/code_of_conduct/
