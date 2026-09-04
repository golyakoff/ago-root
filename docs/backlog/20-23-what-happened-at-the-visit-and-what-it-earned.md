# What happened at the visit, and what it earned

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-20`. Related to `20-28` (the same card is where this is entered).
- **Decided by the author, 2026-09-02**: the revenue figure is **accounting**, not a private note.
  That answer is what shapes this item; it was asked three times before it was answered, and the
  design was held rather than guessed.

## What the tenant asked for, in her terms

Four facts about every appointment:

1. **Was the client there.**
2. **How much it earned**, if they were.
3. **Cancelled in advance** — polite, not punished.
4. **Did not come and did not say** — recorded, and eventually a reason to require prepayment.

## What exists, and the three gaps

`EventStatus` is `Available, PendingConfirmation, Booked, Cancelled, NoShow, Blocked`.

- **(3) exists** — `Cancelled`, via `CancelBooking`.
- **(4) exists as a state** — `NoShow`, with a real invariant (it cannot be recorded before the slot
  ends, because a no-show is a statement about something that did not happen).
- **(4) does not exist as history.** `NoShowCount` is already on the contacts report and **nothing in
  production ever writes it up** — the code says so in as many words, and `20-12` recorded that fixing
  the missing writer is a separate item. **This is that item.** Until it lands, the data behind
  "eventually require prepayment" is not accumulating; every day without it is history not kept.
- **(1) does not exist.** There is no `Attended`. Today "came" is inferred from "in the past and not
  marked otherwise" — the absence of an action, which is not a fact.
- **(2) does not exist at all.** There is no money anywhere in AGO Calendar.

## The correction the author accepted, and what follows from it

The tenant's own split was *cancelled = polite, silent = malicious*. The significant axis is not
whether they warned but **how long before**: cancelling ten minutes ahead loses the slot exactly as
thoroughly as silence, because there is no time to refill it. A day's notice is a different act.

Two consequences, and the first is urgent independently of the second:

- **The facts must be recorded now.** `Cancel`, `Reject` and `MarkNoShow` all take `now` and put it —
  with the reason — into a **domain event**, not onto the booking row. The row keeps only
  `Status = Cancelled`. So "cancelled a day ahead" and "cancelled ten minutes ahead" are today stored
  identically, and **the difference cannot be recovered afterwards**. Recording is cheap; not recording
  is irreversible.
- **The policy is not urgent** and is not built here. What counts as an abuse — and whether a later
  attendance redeems an earlier no-show — is the tenant's judgement, and it should be *derived from the
  recorded facts*, never stored as a flag somebody has to maintain. `adr/0090` already fixes where
  reputation lives: on the `Customer`, never on the phone number, because a carrier can reissue a
  number to a stranger.

## Money, given that it is accounting

- **An amount is never a bare number.** It carries a currency, stored with it rather than assumed —
  one column now against a rewrite later, and the tenant has already named prepayment as coming.
- **Corrections are visible, not silent.** She will mistype an amount. Overwriting loses the fact that
  it changed, and *that* is the line between a note and an account: who, when, from what to what.
- **Grouping is already solved and costs nothing** — `adr/0049` materialises `events.local_date`, the
  business-local day computed in the calendar's own IANA zone, and forbids re-zoning a live calendar.
  So "most profitable weekday" and "most profitable month" group on a column that already exists, with
  **no timezone arithmetic in the report at all**. This is the trap that silently corrupts such reports
  elsewhere — a 23:30 UTC visit landing on the wrong local day — and it was closed before this item
  existed.

## Scope

- An explicit **attended** outcome, and the amount recorded against the appointment — which already
  carries the customer and `local_date`, so all three reports the author named are one read model.
- **Entering the amount is what marks attendance.** One action rather than two, and it is the action
  she opens the card for anyway. *(Proposed and not objected to; see Open questions.)*
- **A writer for `NoShowCount`**, so the report stops being permanently zero.
- **`CancelledAt` and the initiator on the booking row**, not only in a domain event.
- A `CancelledByCustomer` reason — today the enum has only operator-initiated values, so "the client
  rang and politely cancelled" is indistinguishable from "she cancelled because she was ill", which is
  precisely the distinction the tenant wants to act on.

## Out of scope

- **Reports.** *"Потом придумаем отчёты, пока сохраняем"* — the author's own sequencing, and it is
  affordable exactly because `local_date` is already materialised.
- **Prepayment**, and any policy that blocks a booking. Named as coming; not built here.
- Letting a client cancel their own booking. That would need `CancelledByCustomer` to be produced by a
  client-facing path, which does not exist.

## Done when

- [ ] Attendance and amount are recorded against an appointment, and the amount carries a currency.
- [ ] An amount can be corrected, and the correction is **visible** — proven by a test asserting the
      previous value is still recoverable.
- [ ] `NoShowCount` increases for a real no-show, proven end to end. The report has shown zero for
      every customer since it shipped.
- [ ] A cancellation records **when** and **at whose initiative**, on the row, recoverable without
      replaying domain events.
- [ ] Revenue can be summed per customer, per local weekday and per local month, grouped on
      `local_date` — with a test crossing a UTC day boundary, because that is the case that silently
      gets it wrong.
- [ ] Nothing here stores a "bad customer" flag. Reputation is derived from recorded facts.

## Open questions

- **Is "the amount is the attendance mark" right?** It is one action instead of two, but it forces a
  number for a visit that earned nothing — a consultation, a warranty fix, a no-charge redo. Perhaps
  zero is a legitimate amount and that resolves it; perhaps attendance needs its own control after all.
- **Whose money is it** — gross taken from the client, or her earnings after materials? For a
  one-person business they may be the same, and if they ever diverge the answer must be decided before
  a year of history is recorded under the wrong meaning.
- **Does a moved appointment (`20-29`) carry its outcome across the chain**, or does the outcome belong
  to the appointment that actually happened? The latter is almost certainly right and should be stated
  rather than assumed.
