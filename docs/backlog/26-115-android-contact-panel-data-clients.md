# 26-115 · [android] Contact-detail panel data layer (contact details + phone/email reveal, tags, notes)

- **Stage**: 26 — implementation of `26-111` (design: `docs/design/26-111-thread-contact-detail-panel.md`).
- **Status**: ready — over chat endpoints that already exist (26-111 design mapped them).
- **Depends on**: nothing — these back existing `ago-chat` endpoints; no backend change needed.

## What and why

The in-dialog contact-detail bottom sheet (26-111) needs its Android **data layer** before the UI shell.
The 26-111 design confirmed the backing chat endpoints already exist for: the visitor's contact details
(name/phone/email, masked) + phone/email **reveal**, the conversation's **tags** (site vocabulary + apply/
remove), and the conversation's **team notes** (list + add). Build the domain ports + Ktor clients for
these, reusing `26-53`'s existing reveal-result shape. This is one coherent data-layer slice (kept as one
worker deliberately, because all three register in the same `di/AppModule.kt` — splitting them across lanes
would collide on that file, CLAUDE.md rule 13).

## Scope

- **Confirm each endpoint against the real code first** (paths/DTOs) — see the 26-111 design doc's
  element-by-element map; do not assume.
- Domain ports in `:core:domain` + Ktor implementations in `:core:network` for:
  - contact details for a conversation's visitor (name/phone/email + masked flags),
  - phone reveal **and** email reveal (reuse the existing reveal path `26-53` established; distinguish
    surface as `AndroidThread`),
  - conversation tags: read the site's tag vocabulary + the conversation's applied tags; apply + remove,
  - conversation team-notes: list + add.
- Register all in `di/AppModule.kt` (one edit).
- **Name is plain text, always trusted** (26-111 decision #1) — no invalid/assessment handling anywhere.
- No UI in this ticket (the bottom-sheet shell + sections are separate tickets); expose flows/suspend
  functions the ViewModels will consume.

## Out of scope

- The bottom-sheet UI, the per-section composables, the write actions close/block (separate tickets).
- `visitor-summary` / past-dialogs clients (depend on `26-114`; separate tickets).

## Done when

- [ ] Domain ports + Ktor clients for contact details, phone/email reveal, tags (read/apply/remove), notes
      (list/add), all wired in `AppModule`, each confirmed against the real chat endpoint.
- [ ] `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green; unit tests for each
      client (success + not-configured/failure classification), counts reported.
