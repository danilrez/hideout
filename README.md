# Hideout

Hideout keeps your macOS menu bar tidy by moving selected menu bar items into
the system overflow area until you need them.

## Preview

<p align="center">
  <img src="docs/previews/Preview.gif?v=0.2.0" alt="Hideout usage preview" width="900">
</p>

## Features

- Hide and reveal menu bar items with the arrow in the menu bar.
- Reorder items with `⌘`-drag.
- Configure a global shortcut, automatic hiding, and login launch.

## Requirements

- macOS 27.0 or later.

## Installation

Download the latest DMG from the [GitHub Releases](https://github.com/danilrez/Hideout/releases)
page, open it, and drag `Hideout.app` to `/Applications`.

Release DMGs use an ad-hoc signature to seal the application bundle and its
resources. They are not signed with an Apple Developer ID certificate or
notarized, so macOS may require a manual confirmation the first time a
downloaded build is opened.

## Usage

1. Launch Hideout. Its arrow appears in the menu bar. By default, the
   preferences window opens at launch.
2. Hold `⌘` and drag menu bar icons past the `>>` control to choose which items
   Hideout manages.
3. Click the arrow to collapse or expand the managed items.
4. Right-click the arrow to open Settings, toggle automatic collapse, or quit
   Hideout.
5. In Settings, configure the global shortcut, automatic hiding delay, login
   launch, and whether the preferences window opens at launch.

<p align="center">
  <img src="docs/previews/Settings.png?v=0.2.0" alt="Hideout Settings" width="720">
</p>

## License

MIT &copy; [Danil Reznichenko](https://github.com/danilrez)
