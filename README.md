# Manicule

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-555)
![Swift](https://img.shields.io/badge/swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/github/license/lockyc/manicule)](LICENSE)

A macOS menu-bar app that becomes your default browser and decides where each link opens:
the right browser, and the right profile within it, or [flotilla](https://github.com/Lockyc/flotilla)
when it's installed. Links that are certain route themselves
(a Google Workspace link carrying an account email goes to that account's Chrome profile);
everything else gets a fast icon-strip picker under the cursor, and your picks turn into rules
instead of rules having to be written up front. The name is the printer's pointing hand, ☞.

## Status

Early (0.x): routing, the icon-strip picker, flotilla's windows and groups as targets, the ☞
menu-bar menu, Settings, the Velja import, the per-profile web-app launchers
(`~/Applications/Manicule Launchers/`) and in-app updates. What's next:
[docs/FOLLOWUPS.md](docs/FOLLOWUPS.md).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/lockyc/manicule/main/install.sh | bash
```

Needs macOS 14 or later. The installer downloads the latest release, checks that it is signed by
Manicule's developer and notarized by Apple, installs `/Applications/Manicule.app`, registers it
with Launch Services and launches it. After that Manicule updates itself: it checks daily, and
**Check for Updates…** in the ☞ menu checks now. From a clone of this repo, Claude Code's
`/manicule:install` runs the same install.

To build from source instead (needs Xcode's Swift 6 toolchain and
[`just`](https://github.com/casey/just)):

```bash
just install    # builds, installs /Applications/Manicule.app, registers it and launches it
```

## First run

Click ☞ in the menu bar and open Settings.

1. **General → Make Manicule the Default Browser** (macOS asks you to confirm).
2. **General → Browser access** — click Grant Access… for each browser listed (Chrome, Firefox)
   and then Open in the panel; macOS keeps their profile lists from Manicule until you do.
3. **Targets** — tick **Pinned** for the profiles you want in the picker strip; the rest wait
   under its ⋯ menu (or press `0`). Drag browsers and profiles into order. Profiles found later
   arrive unpinned. flotilla's windows are its profiles, each tile in its window's colour; its
   open groups are listed under ⋯ and in a rule's **Opens in**.
4. **General → Import rules from Velja**, if you are coming from Velja.
5. **General → Open at login**, to keep ☞ in the menu bar from login; otherwise macOS starts
   Manicule when the first link arrives.

## Build & test

```bash
just test      # unit tests
just gate      # pre-merge gate
just bundle    # assemble .build/Manicule.app
just install   # install to /Applications/Manicule.app and register with Launch Services
```

Architecture and conventions: [CLAUDE.md](CLAUDE.md).
