# Hideout

Hideout keeps your macOS menu bar tidy by moving selected menu bar items into the system overflow area until you need them.

## Preview

<p align="center">
  <img src="docs/previews/Preview.gif?v=0.2.0" alt="Hideout usage preview" width="900">
</p>

## Features

- Hide and reveal menu bar items with the arrow in the menu bar.
- Reorder items with `⌘`-drag.
- Configure a global shortcut, automatic hiding delay, login launch, and whether the full menu bar returns when expanding.

## Requirements

- macOS 27.0 or later.

## Installation

Download the latest DMG from the [GitHub Releases](https://github.com/danilrez/Hideout/releases) page, open it, and drag `Hideout.app` to `/Applications`.

Release DMGs use an ad-hoc signature to seal the application bundle and its resources. They are not signed with an Apple Developer ID certificate or notarized, so macOS may require a manual confirmation the first time a downloaded build is opened.

## Usage

1. Launch Hideout. Its arrow appears in the menu bar. By default, the preferences window opens at launch.
2. Hold `⌘` and drag menu bar icons past the `>>` control to choose which items Hideout manages.
3. Click the arrow to collapse or expand the managed items.
4. Right-click the arrow to open Settings, toggle automatic collapse, or quit Hideout.
5. In Settings, configure the global shortcut, automatic hiding delay, login launch, whether the preferences window opens at launch, and whether the full menu bar returns when expanding.

## Menu bar changes during a call

macOS can add or rearrange native microphone, camera, or screen-sharing indicators during a call. If a layout change moves the Hideout arrow out of its expected position while items are collapsed, Hideout expands the managed menu bar and pauses automatic hiding. After the indicators settle, click the arrow to collapse the menu bar again.

<p align="center">
  <img src="docs/previews/Settings.png?v=0.2.0" alt="Hideout Settings" width="720">
</p>

## License

MIT License &copy; 2026 [Danil Reznichenko](https://github.com/danilrez). See [LICENSE](LICENSE).
