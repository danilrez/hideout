# Contributing to Hideout

Hideout is an AppKit menu bar utility for macOS 27 and later. It uses Xcode 27 and Swift 6 with complete strict concurrency. Older macOS versions aren’t supported.

## Propose a change

For a small fix, open a pull request with a clear description. For a larger behavior or architecture change, open an issue first. Include a screenshot or reproduction when changing the menu bar or Preferences window.

## Develop and verify

Open `Hideout.xcodeproj` in Xcode 27. The project has no external Swift Package dependencies; global shortcuts use the native Carbon Event Manager API.

Build Debug and Release with:

```sh
xcodebuild -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Debug \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```sh
xcodebuild -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Release \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Keep `MACOSX_DEPLOYMENT_TARGET` at 27.0 and `SWIFT_VERSION` at 6.0 when verifying changes. All `HideoutTests` must pass before submitting:

```sh
xcodebuild test -project Hideout.xcodeproj \
  -scheme Hideout \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Behavior changes also need a check in the real menu bar. For UI changes, verify collapse and expand, auto-hide, the global shortcut, login-item registration, and multiple displays on macOS 27. If a change affects hover-to-expand or status-item order, check those paths too. Lint localized strings with:

```sh
find Hideout -name '*.strings' -print0 | xargs -0 plutil -lint
```

## Release DMG

Use semantic version tags in the form `vMAJOR.MINOR.PATCH`. Match `MARKETING_VERSION` to the tag and increment `CURRENT_PROJECT_VERSION` for each build. Create and push the matching tag when preparing a release.

The `Release DMG` workflow builds a macOS 27 archive, seals and verifies `Hideout.app` with an ad-hoc signature, then publishes the DMG with an `Applications` shortcut. Ad-hoc signing isn’t Developer ID signing or notarization; macOS may ask users to confirm the first launch.

## Code guidelines

- Keep AppKit state and UI work on `@MainActor`. Fix Swift 6 isolation errors; don’t mask them with `@unchecked Sendable`.
- Use the macOS 27 APIs and behavior already established in the project.
- Preserve the `hiddenbar_*_v27` status-item autosave names and declaration order. They keep macOS 27 menu bar placement separate from older layouts. An existing installation may need a one-time `⌘`-drag after upgrading. Recheck placement before renaming or reordering these items.
- The Release DMG workflow signs with `Hideout/Hideout.entitlements`; local verification builds disable signing. Discuss changes to entitlements, network access, subprocesses, or dependencies before making them.
- Put user-facing strings in localization resources. Update storyboard companion strings when changing storyboard text.
- Keep changes focused; don’t reformat unrelated files or edit generated artifacts.

## Branches and pull requests

Create branches from `main` with a short descriptive prefix, such as `feature/hover-to-expand`, `fix/login-item-state`, or `maintenance/contributing-guide`.

Describe the problem and the change in each pull request. Include build commands and manual checks, plus any known limitation or migration step. Keep commits focused. Don’t commit secrets, local configuration, DerivedData, or Xcode user state.

## Code of Conduct

Hideout follows the [Contributor Covenant, version 3.0][code-of-conduct]. Keep participation respectful and constructive. Report unacceptable behavior through the repository or to `code.cli.agent@gmail.com`.

[code-of-conduct]: https://www.contributor-covenant.org/version/3/0/code_of_conduct/
