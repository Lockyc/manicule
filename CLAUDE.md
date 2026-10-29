---
type: architecture
links:
  - rel: see-also
    to: README.md
    note: human-facing counterpart
  - rel: see-also
    to: docs/FOLLOWUPS.md
    note: deferred work — what is next
---
# Manicule

A native macOS (14+) menu-bar app that is the system default browser: every http/https link
goes through it and it alone decides where the link opens. Targets are browser **profiles**
(Chrome and Chromium from `Local State`, Firefox from `profiles.ini`, Safari as one target),
not just browsers. One Swift package, no Xcode project, no third-party dependencies.

**What's next:** `docs/FOLLOWUPS.md` — deliberately deferred work.

## Layout

```
Package.swift
VERSION                  # the one version source
justfile                 # recipes: `just` lists them
Sources/ManiculeCore/    # all logic — unit-tested
Sources/manicule/        # the AppKit shell (executable): menu bar, picker panel, Settings
Resources/Info.plist     # bundle template; `just bundle` fills its version (from VERSION)
Tests/ManiculeCoreTests/ # unit tests for ManiculeCore
Tests/maniculeTests/     # the shell
```

Logic lives in `ManiculeCore` and is unit-tested (routing is pure); `Sources/manicule` is the
thin AppKit shell. Anything testable without a window belongs in `ManiculeCore`.

## Routing order

Evaluated in order; the first that resolves wins.

1. **Account in the URL** — a Google URL carrying an email (`authuser=<email>`, `/u/<email>/`)
   routes to the Chrome profile signed into that email (from `Local State`
   `profile.info_cache.<dir>.user_name`, read at runtime). A numeric `/u/1/` index is not an
   account and gets no built-in meaning.
2. **Rules** — URL matchers (host, path, query, contains, regex; all must hold) plus an optional
   source app → target. Ordered, first match wins, opens immediately. `⌥⏎` in the picker creates
   a host-suffix rule.
3. **Remembered document** — a Google file ID the user has picked a profile for before.
4. **Picker** — icon strip under the cursor, pre-selected on the last target chosen for the host.

A Google file opens in the profile's web app when installed there:
`open -na "Google Chrome" --args --profile-directory=<dir> --app-id=<id> --app-launch-url-for-shortcuts-menu-item=<url>`.

## Conventions

- The app opens without the picker only on an email in the URL, a user-made rule, or the user's
  own earlier pick for that exact document. A remembered host choice pre-selects; it never
  auto-opens.
- Opening a link leaves the URL untouched; only Copy strips tracking parameters.
- No personal data in tracked code: targets, names, rules, remembered documents and history live
  in runtime config under Application Support, discovered from the browsers' own profile files.
- Chrome's shared web-app shims are never touched; generated per-profile launchers live in
  `~/Applications`.
- Bundle id `com.lockyc.manicule` is fixed: default-browser registration is keyed to it.

## Branches and releases

`main` + `dev`. All work commits to `dev` and is pushed immediately; `main` advances only by a
fast-forward to `dev` at release. `VERSION` is the single version source; tags are
`v<VERSION>`, each with a GitHub release carrying notes. Cutting a release: bump `VERSION`,
curate `README.md`, tag, publish. `just bundle` signs `.build/manicule.app` with the identity
named by `APPLE_SIGNING_IDENTITY`, else ad-hoc.

## Build & test

`just test` (unit tests), `just gate` (pre-merge gate), `just bundle`, `just install`, `just run`.
