# Manicule

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-555)
![Swift](https://img.shields.io/badge/swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/github/license/lockyc/manicule)](LICENSE)

A macOS menu-bar app that becomes your default browser and decides where each link opens:
the right browser, and the right profile within it. Links that are certain route themselves
(a Google Workspace link carrying an account email goes to that account's Chrome profile);
everything else gets a fast icon-strip picker under the cursor, and your picks turn into rules
instead of rules having to be written up front. The name is the printer's pointing hand, ☞.

## Status

In development: links route, the icon-strip picker, the ☞ menu-bar menu and Settings work; the
per-profile web-app launchers are not built yet.

## Build & test

```bash
just test      # unit tests
just gate      # pre-merge gate
just bundle    # assemble .build/Manicule.app
just install   # install to /Applications/Manicule.app and register with Launch Services
```

Needs macOS 14+ and the Swift 6 toolchain. Architecture and conventions: [CLAUDE.md](CLAUDE.md).
