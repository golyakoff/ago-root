# The personal-data map, and residency as a standing constraint

- **Stage**: 16 — but **pulled ahead of its stage** (`roadmap.md`'s "Order" section): two open vendor
  questions that are live right now, `10-05`'s email provider and `15-02`'s backup destination, cannot
  be answered correctly without the constraint this item records
- **Status**: ready
- **Depends on**: nothing

## Goal

The project knows what personal data it holds and where, and the residency constraint that binds
several already-open vendor decisions is written down before those decisions are made rather than
after. `docs/architecture/personal-data.md` is the artifact; this item is the work of keeping it
true and wiring its constraints into the items they bind.

## Context to read first

`docs/architecture/personal-data.md` — written alongside this item; it is the starting inventory, not
a finished one. `docs/architecture/data-model.md` — the tables it maps, and one sentence this item
corrects: `visitors` is described as "Anonymous, no PII by design", which is accurate about that row's
columns and misleading about the dataset, since `messages.body` next to it is whatever a visitor
typed. `docs/backlog/10-05-transactional-email-delivery.md` and `15-02-backup-and-verified-restore.md`
— the two open vendor questions this constraint binds. `adr/0026` — the deployment is already in
Russia, for cost and latency reasons; this item is what turns that into a recorded constraint instead
of a happy accident.

## Scope

- Keep `personal-data.md` accurate as the system changes, and make that a real obligation rather than
  an aspiration: add the check to the places a session actually looks — a line in `db-migration`'s
  guidance for any migration adding a column that holds a person's data, and the same for a new
  integration-event field.
- Correct `data-model.md`'s "Anonymous, no PII by design" so it says what is true of the row without
  implying it is true of the conversation.
- Write the residency constraint into the two items it binds (`10-05`, `15-02`), so the vendor answer
  is chosen against it rather than measured against it afterwards.
- State the two properties that currently make erasure tractable — body-free integration events
  (`MessageAccepted`), body-free webhook payloads (`6-05`) — as properties to be preserved, in the
  files where someone would be tempted to break them (`messaging.md`, `api-design.md`).
- No new mechanism, no schema change, no code. This item is documentation and cross-referencing, and
  it is deliberately small so it can land ahead of its stage without dragging Stage 16 with it.

## Out of scope

- Building deletion (`16-02`) or export (`16-03`).
- Answering the vendor questions themselves — `10-05` and `15-02` still own their own decisions; this
  item only ensures they are made with the constraint visible.
- The legal determination of AGO's role, the published policy text, or regulator notification — those
  live in `ago-business` and need a lawyer.
- Auditing logs and traces for personal data — `16-05`, which needs real running instrumentation to
  look at rather than a reading of the docs.

## Done when

- [ ] `personal-data.md` exists, lists every store, and is referenced from `data-model.md`.
- [ ] `data-model.md`'s "no PII by design" sentence is corrected.
- [ ] `10-05` and `15-02` each carry the residency constraint in their own Open questions, so neither
      can be answered without it.
- [ ] `messaging.md` and `api-design.md` state that integration events and webhook payloads stay
      body-free, and why that is now a privacy property and not only a size one.
- [ ] The migration guidance names the map as something a schema change updates.

## Open questions

None. Everything here is recording what is already true.
