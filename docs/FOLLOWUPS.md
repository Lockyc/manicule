---
type: roadmap
links:
  - rel: see-also
    to: CLAUDE.md
    note: architecture and conventions
---
# Follow-ups

Deliberately deferred work. Remove an entry when it ships.

- **Account check for Google links.** Ask Google which signed-in account can open a shared file,
  so a new shared doc routes without the picker. Deferred: Manicule does not sign in to Google
  for now. Unlock: revisit it; candidate routes are borrowing existing `gcloud` sign-ins or a
  dedicated OAuth client. It slots in as a routing step between "Remembered document" and
  "Picker".
- **Source-app-only rules.** "Every link from this app → this target" can't be written: a rule
  needs a condition with a value, and Velja rules with only a source app are skipped on import.
  Deferred: a rule without a URL condition opens every link from that app unseen, so it should be
  an explicit choice. Unlock: an "Any URL" matcher kind, shown as such in Settings and mapped from
  Velja.
- **Chrome profile colour in tiles.** A Chrome tile without an avatar picture is a circle in a
  hue derived from the target id, not the profile's own colour. Deferred: the colour fields in
  `Local State` (highlight vs theme, signed ARGB) need confirming on current Chrome. Unlock:
  confirm the field and use it for the circle.
- **Firefox profiles at absolute paths.** A profile with `IsRelative=0` is launched as
  `<Firefox folder>/<Path>`, which is wrong for it. Deferred: only profiles created with a custom
  location have it. Unlock: read `IsRelative` in discovery and launch with the absolute path.
- **Login item.** Manicule doesn't start at login; macOS launches it when the first link
  arrives. Deferred: launch-on-demand already routes every link; starting at login only puts the
  ☞ menu up earlier. Unlock: an "Open at login" toggle in General backed by
  `SMAppService.mainApp`.
- **Uninstalled browsers.** A target counts as available when its profile is discovered, and
  an uninstalled browser often leaves its profile folder behind, so routing can still pick it and
  the launch fails (logged). Deferred: rare on a maintained Mac. Unlock: count a browser's
  profiles only when `NSWorkspace.urlForApplication(withBundleIdentifier:)` finds the app.
- **Firefox with a different profile running.** When Firefox is running, links go to its binary,
  which hands off to that profile's instance — or, if a different profile is the running one,
  starts a second instance as Manicule's child. Deferred: one-profile use is the norm. Unlock:
  check whether the target profile is the running one and use `NSWorkspace.openApplication`
  when it isn't.
- **Save-refusal notice on every tab.** When the config file can't be safely written, only
  General says so; edits on other tabs look saved until Settings reloads. Unlock: show the
  notice in the window title or on every tab.
- **Wide picker strips.** The strip is one row of fixed-width tiles; past about 25 pinned
  targets it is wider than the screen and tiles fall off the edge. Deferred: the strip is meant
  for a curated handful (nine have number keys), with the rest under ⋯. Unlock: someone showing that many — cap the
  width and scroll, or wrap to a second row.
