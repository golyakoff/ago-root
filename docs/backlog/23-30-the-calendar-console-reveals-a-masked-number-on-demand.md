# the calendar console reveals a masked number on demand

- **Stage**: 23
- **Status**: ready — **repository corrected below; the promise is the same one`23-12` always implied**
- **Depends on**: `23-12` (hard — the backend, the `Masked` flag and the three endpoints)
- **Corrected 2026-09-09**: this item named `ago-calendar-console` throughout. That repository was
  retired by `22-06` on 2026-09-04 — two days before `23-12`'s own backend shipped — and every screen
  it named moved to `ago-console`, rewritten against `adr/0030`'s closed component set rather than
  carried over as-is. Found by a worker that stopped rather than build against a repository with no
  source left in it, checked independently before this correction: `ago-calendar-console`'s
  `origin/main` tip is `5a24862`, and its four pages exist in `ago-console` as
  `CalendarQueuePage.tsx`, `CalendarContactsPage.tsx`, `CalendarWorkerSlotsPage.tsx`,
  `CalendarWorkerRecutPage.tsx`. The promise below is unchanged; only the repository and the
  component system it is built against are.
- **Decision**: `docs/adr/0123-*` (both sides of the ladder), and `decisions.md` §5 behind it

## Goal

An operator on a tenant whose account is set to `MaskedWithReveal` sees a masked number, can reveal one
when they need it, and can see that the reveal was recorded.

## The precedent to copy, not invent

`23-11` (`ago-console`, merged 2026-09-06) already built this exact pattern for chat's own contacts:
a `masked` boolean on the row, a **Reveal** button beside it, a call that replaces the whole row with
the server's own unmasked response rather than computing anything client-side
(`src/workspace/ContactDetailsPanel.tsx`, and its own doc comment names the reasoning). Its test
proves a caller without the permission sees no panel at all, not an empty one — the same
forbidden-vs-empty distinction this item's own Done-when asks for on the audit view. Follow this
shape; do not design a new one.

## Why this is its own item

`23-12` built the whole backend and stopped, and the split is deliberate rather than a shortfall. The
console work is **four screens**, not one — the calendar queue, the contacts report, a worker's slots
and the recut preview — and by `CLAUDE.md` rule 15 each half makes its own promise that lands green:
`23-12`'s API refuses and records correctly whether or not a screen exists, and this item's screens have
something real to call from the day it starts.

## What `23-12` already gives you

- A `Masked` boolean on every response row that carries a phone, on all four read paths.
- `POST /api/v1/console/contacts/{customerId}/reveal-phone` — gated on `Permission.CustomerRead`,
  tenant-scoped, and it writes the reveal record itself.
- `POST /api/v1/console/contacts/{customerId}/confirm-phone` — the operator's own "I called and it is
  them", distinct from the SMS code's answer.
- `GET /api/v1/console/contacts/phone-reveals` — the audit view, gated on the **wider**
  `Permission.CalendarConfigure`, deliberately: revealing one number does not entitle somebody to the
  whole tenant's history of who revealed what.

## Scope

- The four screens render the masked value and a reveal control, replacing the row with the server's
  own response. **Nothing is unmasked client-side** — the browser never received the real value.
- The contacts report distinguishes the two verification facts: an SMS code came back, versus an
  operator confirmed by calling. They are different strengths and the screen should not merge them.
- A screen for the reveal audit trail, gated so a caller without `CalendarConfigure` does not see an
  empty page that looks like "no reveals" — "forbidden" and "none" must stay visibly different.

## Out of scope

- Any change to the rung, the masking, or the endpoints. That is `23-12`, and changing it here would
  mean two items owning one behaviour.
- A screen for *setting* the rung. That lives on the account side, in `ago-console`, and does not exist
  there either — a third item if it is wanted.

## Done when

- [ ] All four screens show a masked number as masked, and reveal one on demand.
- [ ] A test proves the real number is never in the rendered output before a reveal.
- [ ] The two verification facts are distinguishable on the contacts report.
- [ ] A caller without `CalendarConfigure` sees a refusal on the audit view, not an empty list.
