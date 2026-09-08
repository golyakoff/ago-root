# ADR-0161: a customer merge tombstones the losing row and is never undone

- **Status**: Accepted
- **Date**: 2026-09-09
- **Stage**: 23 (`23-60`)

## Context

`adr/0147` refused to merge a chat-sourced customer into a phone-matching booking-sourced one
automatically: a duplicate is visible, reversible and embarrassing, a wrong merge is invisible,
irreversible and a disclosure of one person's bookings to another, and a phone number is a hint, not
proof. That ADR's own consequence, named rather than implied: "duplicate customers are now normal…
`23-60` gives them a way to fix it."

`23-60` is that way - an operator, having looked at both lead cards' own booking histories, decides
the two are one person and merges them. Three questions `adr/0147` left open, and this item's own
brief asked to be decided and written down rather than defaulted:

- Can a merge be undone?
- What happens to the losing customer row - and everything in this schema that points at it
  (`events.customer_id`, `contact_phone_reveals.customer_id`)?
- Who decides which of the two rows survives - the operator, who can see both cards, or the system?

A fourth force, discovered while building the write path rather than anticipated from the item's own
text: this product's *only* channel by which a future booking attaches to an existing customer is
`BookingStore`'s own upsert, `INSERT … ON CONFLICT (tenant_id, phone) WHERE source = 'Booking'`. That
partial unique index can only ever be satisfied by a `Booking`-sourced row - a `Chat`-sourced one is
deliberately exempt from it (`adr/0147`'s own "does not merge" mechanism). Whichever row survives a
`23-60` merge is therefore not a cosmetic choice: if the surviving row is `Chat`-sourced while a
`Booking`-sourced row for the same phone is tombstoned, the very next booking that person makes
upserts onto a *third*, brand-new row rather than reaching the console's own chosen survivor - a wrong
merge `adr/0147` never anticipated, produced by the tool built to fix duplicates.

## Decision

**A merge is permanent.** Nothing in this codebase calls its inverse. `Customer.MarkMergedInto`
throws if called a second time on the same row - the domain's own statement that this is not a
retryable or idempotent write, unlike almost everything else this aggregate does.

**The losing row is tombstoned, not deleted.** Two new columns, `merged_into_customer_id` and
`merged_at`, self-referencing with `ON DELETE CASCADE`. `events.customer_id` carries a real foreign
key to `customers`, and `Event`'s own remarks are explicit that a cancelled or no-show visit's history
is kept forever - deleting the losing row outright would either orphan that history or force a second,
hidden reassignment this decision would rather make visible and atomic. `IContactsReadStore` excludes
a tombstoned row from the ordinary contacts screen; nothing else in the schema needs to change to stop
pointing at it, because it never stops existing.

**The system chooses the survivor; the operator only chooses whether to merge at all.** When exactly
one of the two candidates is `Booking`-sourced, that one always survives - the only asymmetric case
the partial unique index above can ever produce (two `Booking`-sourced rows can never share a phone in
the first place, so this is the sole asymmetry to resolve). Between two `Chat`-sourced rows, the one
first seen earlier survives, tie-broken by id for determinism. `MergeCustomers` therefore takes two
unordered candidate ids, never a caller-named "survivor" - the request has no field to hold a wrong
answer to a question the operator has no reliable way to judge correctly, and a wrong guess would
actively misroute future bookings, not merely look worse.

**The audit row (`customer_merges`) carries real foreign keys and cascades with the tenant**, unlike
`contact_phone_reveals`. A reveal is evidence an operator answers *AGO* for, and must survive the
tenant's own erasure so the tenant can still ask "who looked at this." A merge is the tenant's own
internal record of its own act on its own data - the same shape `role_change_records` and
`team_message_removals` already take, and for the identical reason: a merge record that outlived the
tenant it describes would be an unreachable fragment of an operator's personal data with nothing left
to attach it to.

**Detection is phone-only.** `23-60`'s own Scope line says "shares a phone or an e-mail"; this
product's `Customer` aggregate has no e-mail field at all, on any row, so the comparison this item
implements is phone-only. This is a scope boundary this ADR states rather than a gap the item silently
leaves - the day this product's `Customer` gains an e-mail field, the same grouping
`ContactsReadStore` already does for phone extends to it.

## Consequences

**Positive.** An operator who merges two records makes exactly one decision - "these are the same
person" - and the system, not the operator, protects the one invariant (`BookingStore`'s own upsert
target) an operator has no way to see and would have no reason to reason about. The audit trail
answers `adr/0147`'s own "a merge that cannot be explained afterwards is a merge nobody will trust"
with a queryable row, not a log line. Tombstoning means every foreign key already in this schema keeps
working with no further change.

**Negative, and named rather than implied.**

- **No undo, ever - stated as a real cost, not a footnote.** A merge performed on a mistaken belief
  ("these are the same person" when they are not) cannot be reversed by this product. The console's
  confirmation step exists to make this felt at the moment of the click - both customers' own full
  booking lists, shown before the operator commits, and copy that states the merge cannot be undone -
  but that mitigates the cost, it does not remove it. `adr/0147`'s own asymmetry argument is what
  decides this is the right trade anyway: an automatic wrong merge is worse than an operator's wrong
  merge, but an operator's wrong merge is still irreversible, and pretending otherwise (a "soft" undo
  that silently reassigns the same bookings back) would just move the invisible-failure risk from the
  first merge to the second.
- **An operator cannot pick which lead card's own name or notes survive.** `Customer.AbsorbHistoryFrom`
  deliberately never touches `DisplayName`/`Notes` - splicing free text an operator wrote about one
  identity onto another risks attributing it to the wrong context with nobody deciding that should
  happen. The consequence: if the losing card had the better name or notes, they are gone with it.
  This item's own Done-when asks only that the bookings end up on one record; a future item may widen
  this deliberately, but this decision does not do so implicitly.
- **A tombstoned row is not reachable from the ordinary contacts screen, ever again, by design** - an
  operator who wants to see it again needs the audit trail (`customer_merges`), not the contacts list.
  This is the intended effect of the merge, but it means "undo" is not only unbuilt, it is also not a
  simple matter of un-hiding a row that never stopped existing.

## Alternatives considered

**Let the operator name the survivor.** Rejected: the sharpest alternative, and the one a reviewer
would expect - "the human decided to merge, let the human decide which record to keep." Rejected once
the `BookingStore` upsert-target asymmetry was found: an operator has no way to know which row is the
one future bookings will attach to, and choosing wrong would silently misroute that person's next
booking onto a third row - reproducing, from inside the tool built to fix `adr/0147`'s own duplicates,
the exact "invisible, irreversible" failure that ADR warns a wrong merge already is.

**Delete the losing row outright.** Rejected: `events.customer_id`'s own foreign key and this
product's "a customer's history is kept forever" rule (`Event`'s own remarks) would force either an
orphaned booking or a second, un-audited reassignment. Tombstoning keeps every existing foreign key
correct with no further schema change.

**Allow undo within a short window** (the way `20-04`'s confirmation sweep has a window). Rejected:
`adr/0147`'s own asymmetry argument is precisely that a wrong merge is a privacy disclosure the moment
it happens, not a state that stays wrong only until somebody notices - a booking's own confirmed
customer may already have been looked at by an operator in the interim. A time-boxed undo would imply
a safety this product cannot actually provide.

**No foreign key on `customer_merges`, matching `contact_phone_reveals`.** Considered for consistency
with the nearest existing audit table. Rejected: that table's own no-FK choice exists so evidence of
AGO's own operator activity survives a tenant's erasure - a different question than this one. A merge
record answers a question about the tenant's own act on its own data, the identical shape
`role_change_records`/`team_message_removals` already take, and those cascade.

## Current-state documents this changes

`docs/architecture/personal-data.md` - a `customers` row can now be a tombstone
(`merged_into_customer_id`/`merged_at`), and a new table, `customer_merges`, exists. Updated in the
same change as this ADR.
