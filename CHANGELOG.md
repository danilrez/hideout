# Changelog

All notable changes to Hideout are documented here.

## [0.1.2]

### Fixed

- Fixed DMG packaging by sealing the archived app with a valid ad-hoc
  signature before creating the disk image.

## [0.1.1]

### Fixed

- Fixed layout, spacing, and control alignment issues in the Preferences view.
- Fixed global shortcut registration when changing or clearing a shortcut.
- Updated the About window link to point to the Hideout repository.

### Changed

- Removed the third-party `HotKey` Swift package dependency.
- Replaced shortcut handling with the native Carbon Event Manager API.
- Kept the app on native Swift 6 and AppKit APIs with no external Swift
  package dependencies.

## [0.1.0]

### Added

- Initial Hideout release for macOS 27.
- Menu bar item hiding and reveal controls.
- `⌘`-drag reordering for menu bar items.
- Global shortcut, automatic hiding, login launch, and multi-display support.
- Preferences, localization resources, and XCTest coverage for core behavior.
- An unsigned DMG release workflow with a SHA-256 checksum for GitHub
  Releases.
