# the calendar console reveals a masked number on demand

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-12` (hard — the backend, the `Masked` flag and the three endpoints)
- **Decision**: `docs/adr/0123-*` (both sides of the ladder), and `decisions.md` §5 behind it

## Goal

An operator on a tenant whose account is set to `MaskedWithReveal` sees a masked number, can reveal one
when they need it, and can see that the reveal was recorded.

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
