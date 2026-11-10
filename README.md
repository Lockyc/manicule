# Manicule

[![Release](https://img.shields.io/github/v/release/lockyc/manicule?sort=semver&label=release)](https://github.com/lockyc/manicule/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-555)
![Swift](https://img.shields.io/badge/swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/github/license/lockyc/manicule)](LICENSE)

Every link you click opens in the right browser and the right profile. Manicule becomes your
default browser and routes each link: a Google Workspace link carrying an account email goes
straight to that account's Chrome profile, and a link it isn't sure of gets a fast icon-strip
picker under the cursor. Pick with ⌥⏎ and that choice becomes a rule, so rules grow from use
instead of being written up front. The name is the printer's pointing hand, ☞.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/lockyc/manicule/main/install.sh | bash
```

Needs macOS 14 or later. The installer downloads the latest release, checks that it is signed by
Manicule's developer and notarized by Apple, installs `/Applications/Manicule.app`, registers it
with Launch Services and launches it. Manicule then updates itself: it checks daily, and
**Check for Updates…** in the ☞ menu checks now.

## First run

Click ☞ in the menu bar and open Settings.

1. **General → Make Manicule the Default Browser** (macOS asks you to confirm).
2. **General → Browser access** — click **Grant Access…** for each browser listed, then **Open**
   in the panel; macOS keeps a browser's profile list from Manicule until you do.
3. **Targets** — tick **Pinned** for the profiles you want in the picker strip; the rest wait
   under its ⋯. Drag browsers and profiles into order. Profiles found later arrive unpinned.
4. **General → Import rules from Velja**, if you are coming from Velja.
5. **General → Open at login**, to keep ☞ in the menu bar from login; otherwise macOS starts
   Manicule when the first link arrives.

## Features

- **Targets** — Chrome, Chromium, Firefox and Safari, each profile its own target, and
  [flotilla](https://github.com/lockyc/flotilla) when it's installed: its windows are its
  profiles, each tile in its window's colour, and its open groups are listed under ⋯ and in a
  rule's **Opens in**.
- **The picker** opens under the cursor with your pinned targets, the one you last picked for the
  link's host selected.

  | Key | Action |
  |---|---|
  | 1–9 | Open in that target |
  | ← / → | Move the selection |
  | ⏎ | Open in the selected target |
  | ⌥⏎ | Open there, and always open this host there (adds a rule) |
  | 0 | Show the targets under ⋯ |
  | c | Copy the link, with click-tracking parameters removed |
  | Esc | Cancel |

- **Rules** (Settings → Rules) are checked top to bottom, and the first that matches opens the link
  without the picker. A condition is the host (is, or ends with), the path, the query, the whole
  URL, or a regex, optionally limited to links from one app.
- **Web-app launchers** — a small app per Chrome web app and profile, in
  `~/Applications/Manicule Launchers/`, so Spotlight and the Dock open the web app in the right
  profile.
- **Recent** (☞ menu) — the last 20 links and where each went.

## Status

In use, `0.x`. What's next: [docs/FOLLOWUPS.md](docs/FOLLOWUPS.md).

## Related

[flotilla](https://github.com/lockyc/flotilla), a workspace for documents, is a Manicule target.

## Development

Needs Xcode's Swift 6 toolchain and [`just`](https://github.com/casey/just).

```bash
git clone https://github.com/lockyc/manicule && cd manicule
just test      # unit tests
just gate      # build, tests and checks
just install   # install to /Applications/Manicule.app and register with Launch Services
```

Architecture, conventions and the release process: [CLAUDE.md](CLAUDE.md).

## License

MIT — see [LICENSE](LICENSE).
