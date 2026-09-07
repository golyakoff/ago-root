# ADR-0147: a contact collected in chat reaches the calendar without either product reading the other

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-58`, `23-59`, `23-60`)

## Context

`23-09` gave a visitor a widget-native form for a name and a phone, stored through
`RecordVisitorContactDetail` as a contact on the tenant's own register (`23-08`). It is shown **once**,
appended to the out-of-hours system message, so a visitor who arrives while somebody is online is
never offered it at all.

The author asked, 2026-09-07, for two things: a modest link under the visitor's own first message that
opens that form whether or not anybody is online, and for the collected contact to **also be a customer
in AGO Calendar** — including for contacts collected before the tenant had the calendar at all, which
must arrive when the module is switched on.

The second half crosses a boundary this project drew deliberately. `adr/0093` keeps two schemas:
`ago_chat` and `ago_calendar`, in separate databases, one product per repository, and the platform may
never reference a product. A contact lives in the first; a customer lives in the second.

## Decision

**Chat publishes; the calendar consumes; neither reads the other's tables.**

- A contact recorded through `RecordVisitorContactDetail` emits an integration event through the
  outbox, in the same transaction as the write (CLAUDE.md rule 4). Chat does not know whether anybody
  is listening.
- AGO Calendar consumes it **when the module is granted to that tenant** and creates a customer.
  Consumers are idempotent (rule 5), so the same contact arriving twice is one customer.
- **When the module is granted, every contact ever collected for that tenant is carried over**, not
  only those collected afterwards. The author's answer: *все, что когда-либо собраны.* The backfill is
  a separate, replayable pass rather than a side effect of the grant, so a grant that succeeds and a
  carry-over that fails are two facts and not one.
- **A phone that matches an existing customer does not merge.** The chat-sourced customer is created
  as its own row, visibly marked as arriving from chat, and merging is a deliberate act somebody takes
  in the console (`23-60`).

## Why not the alternatives

**The calendar reads chat's contacts directly.** Rejected: it is a cross-product read across two
databases, it makes the calendar unable to start when chat is down, and it puts one product's schema in
the other's queries — the thing `adr/0093` exists to prevent. It would also have to be re-derived for
every future product.

**Chat calls the calendar's API when a contact is recorded.** Rejected: it makes a visitor's form
submission depend on another product being up, and it is a synchronous cross-product write from inside
a request handler — rule 4 forbids publishing from there for the same reason.

**Merge on a matching phone.** Rejected, and this is the sharpest of the three. A phone number is a
strong hint and not proof: numbers change hands, and a household shares one. A wrong merge is not an
inconvenience — it shows one person another person's bookings, which is a disclosure. Duplicates are
visible, reversible and embarrassing; a wrong merge is invisible, irreversible and reportable. The
asymmetry decides it.

**Carrying over only from the moment of enabling.** Rejected by the author. It is the cleaner answer on
purpose-limitation grounds and it produces a tenant who switches the calendar on, knows they have
hundreds of contacts, and sees an empty customer list — which reads as a broken product.

## Consequences

**Positive.** The two products stay independent: chat neither knows nor cares whether the calendar
exists, and the calendar can be granted years later without chat changing. The backfill being
replayable means a failed carry-over is re-runnable rather than a support ticket.

**Negative, and named rather than implied.**

- **The consent text has to cover it.** A visitor gave a phone number to a chat widget. Carrying every
  such contact into a booking system, retroactively, is a use the `24-05` consent wording must actually
  permit — if it does not, the wording changes, not this decision. That is a question for the lawyer
  reviewing `23-52`'s documents, and this ADR does not answer it.
- **Duplicate customers are now normal.** A tenant will see the same person twice. `23-60` gives them a
  way to fix it; until it lands, they cannot.
- **The carry-over volume is unbounded.** A tenant with a busy chat and years of history grants the
  calendar and the backfill is large. It is a background pass and not a request, so nothing user-facing
  waits on it, but it is not free.
- **Deleting a contact in chat does not delete the customer in the calendar.** Two products, two
  records, and erasure has to reach both — `24-09`'s subject and, once this lands, a wider one.
