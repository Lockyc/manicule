You are installing or updating **Manicule** — a macOS menu-bar default browser that routes each link to the right browser profile.

## 1. Check the Mac

```bash
sw_vers -productVersion
```

Manicule needs macOS 14 or later. On an older Mac, say so and stop.

## 2. Install

From a Manicule checkout (`[ -f install.sh ] && [ -f Package.swift ]`), ask with AskUserQuestion:
- **Latest release** (recommended): `bash install.sh`
- **This checkout's code**: `just install`

Outside a checkout, run `curl -fsSL https://raw.githubusercontent.com/lockyc/manicule/main/install.sh | bash`.

If the installer needs `sudo`, the user types their password in this session: suggest `! <the command>`.

## 3. Check it is running

```bash
pgrep -x manicule && /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /Applications/Manicule.app/Contents/Info.plist
```

Expect a process id and the installed version.

## 4. Done

Report the version, then the first-run steps from the README: click ☞ in the menu bar → Settings → **General → Make Manicule the Default Browser**, grant access to each browser listed, and pin the profiles wanted in the picker. Manicule updates itself (☞ → **Check for Updates…** checks now).
