# README rewrite for the reviewer audience

- **Stage**: 8
- **Status**: done
- **Depends on**: `7-06-stage-7-load-proof-report.md` (the real numbers this item quotes must exist
  first), `8-02-public-demo-page-and-console.md` (the live link and throwaway credential this item
  points to must actually work before this item can be marked done)

## Goal

`ago-root`'s `README.md` stops being the placeholder it has been since Stage 0 — "Status: design
phase... This README is rewritten for a reviewer audience at Stage 7" — and becomes the actual front
door a reviewer opens first: what the project is, the architecture in one diagram, Stage 7's real
numbers, the full ADR index, an honest "what I would do differently" section, and the live demo link
`8-02` produced. `roadmap.md`'s own Stage 8 done-when bar: "the README answers 'why' before they have
to ask."

## Context to read first

`README.md`'s own current content — read it before writing anything, specifically the two lines this
item must correct as part of the same change (`CLAUDE.md`'s "docs are part of the deliverable"): the
status banner says the rewrite happens "at Stage 7," and the Stack line says "RabbitMQ (Kafka in
Stage 8)" — both predate the roadmap's current stage numbering (the rewrite is Stage 8's own
deliverable per `roadmap.md`, and Kafka is `roadmap.md`'s Stage 9, "`Ago.Platform.Messaging.Kafka`
implementing the same port"). Leaving either uncorrected would ship a reviewer-facing document that
contradicts the roadmap it links to. `docs/vision.md` — the "why," already written; this item
summarizes it rather than re-deriving it. `docs/architecture/overview.md` — the source for the one
diagram this item embeds. `docs/adr/` in full — every accepted ADR gets one line in the index, not a
curated subset. `load/reports/<date>-stage-7-summary.md` (`7-06`'s own deliverable) — every number
this item quotes must trace to a specific line in that report, the same citation discipline `7-06`
itself was held to. `architecture/repositories.md`'s "Everything is public" section — the honesty-
notes precedent (hand-rolled mechanisms named as such, no performance number without a measurement)
this item extends rather than invents from scratch.

## Scope

- Rewrite `README.md` top-to-bottom for a reader who has never seen the project: what it is
  (`vision.md`'s own framing, shortened, not re-argued), the stack, and one embedded architecture
  diagram sourced from `architecture/overview.md` — reuse whatever diagramming convention that
  document already uses rather than introducing a second one for this file alone.
- A numbers section quoting Stage 7's real measured figures, each citing
  `load/reports/<date>-stage-7-summary.md` directly — no number restated without its source line, no
  number estimated or rounded beyond what the report itself states.
- An ADR index: every `docs/adr/*.md` file present at the time this item is done, one line each
  (number, title, one-sentence why) — generated from the actual files in `docs/adr/`, not a
  hand-picked highlight reel that quietly drops the less flattering ones.
- An honest "what I would do differently" section, built from trade-offs this project's own ADRs and
  backlog items already surfaced — the hand-rolled outbox and connection registry vs. an off-the-
  shelf broker/backplane (already named in the current README's own "Honesty notes"), the platform/
  product package-boundary's two-MR cost (`repositories.md`), the one-node local cluster's testing
  limits (`k8s-local.md`'s "Known limits" section) — restated for a reviewer here, not new material
  invented for this section alone.
- The live demo link (`8-02`'s public URL) and the throwaway console credential, stated plainly near
  the top of the document — this is the concrete artifact behind "a stranger with the link can hold a
  conversation," not a promise deferred to a later section.
- Correct the two stale lines named in Context to read first in this same change.

## Out of scope

- Any change to `docs/vision.md`, `docs/roadmap.md`, or any ADR's own content — this item summarizes
  and links to those sources, it does not re-author them. If reading them for this item surfaces a
  real inconsistency beyond the two README lines already named, that gets flagged to the author, not
  silently fixed here.
- Introducing a new diagramming tool or format if `architecture/overview.md` doesn't already have a
  diagram to reuse — producing one is still this item's job in that case, but the format choice
  should be whatever is cheapest to keep current (something this project already uses elsewhere), not
  a new dependency pulled in for one README section.

## Done when

- [x] `README.md` reads correctly for someone who has read nothing else in the repository — no
      unexplained jargon, no forward reference to a doc that isn't linked from the README itself.
- [x] Every number in the new README traces to a specific line in a `load/reports/*.md` file
      (`load/reports/2026-08-24-stage-7-summary.md`, cited directly).
- [x] The ADR index lists every accepted ADR present in `docs/adr/` at the time of this change (0001
      through 0027).
- [x] The live demo link and throwaway credential are present in the README and were verified working
      at the time this item was completed — both operator logins tested for real: `demo-operator`
      through the actual console UI (a real Keycloak redirect, a real login, the real hub connection
      showing real conversations from this session's own earlier tests), `demo-operator-2` through a
      real direct-grant token that resolves to its own, different `siteId` — not "should still work."
- [x] The two stale lines named in Context to read first are corrected in this same change (the
      "rewritten at Stage 7" banner and the "Kafka in Stage 8" stack line, both replaced with the
      current, live status and `roadmap.md`'s actual Stage 9 placement).

## Open questions

None.
