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
