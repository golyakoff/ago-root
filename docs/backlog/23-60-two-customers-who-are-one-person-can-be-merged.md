# two customers who are one person can be merged

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-59` — it is what creates the duplicates this fixes.
- **Decision**: `adr/0147` chose not to merge automatically; this is the other half of that choice.

## Why this exists

`adr/0147` refuses to merge a chat-sourced customer into an existing one on a matching phone. The
reasoning is an asymmetry: **a duplicate is visible, reversible and embarrassing; a wrong merge is
invisible, irreversible and a disclosure** — it shows one person another person's bookings. Numbers
change hands and households share one, so a match is a strong hint and never proof.

That decision is only honest if somebody can act on the hint. Without this item a tenant sees the same
person twice and can do nothing, which is the failure the decision was supposed to avoid, arriving by a
different road.

## Scope

- The calendar console shows, on a customer, that another customer shares a contact detail with them.
- An operator can merge the two, deliberately, seeing both sets of bookings before deciding.
- **The merge is recorded** — who, when, and which record absorbed which. A merge that cannot be
  explained afterwards is a merge nobody will trust.
- **Undo is in scope or explicitly refused, in writing.** `adr/0147` calls a wrong merge irreversible;
  if it stays irreversible then the confirmation has to carry that weight, and if it does not, say how.

## Out of scope

- Automatic merging on any signal. That is the decision `adr/0147` took and this item does not reopen.
- Merging across tenants. Never.

## Done when

- [ ] A tenant can see that two customer records share a phone or an e-mail.
- [ ] They can merge them, and the bookings of both end up on one record.
- [ ] The merge is recorded with who and when, and is visible afterwards.
- [ ] Whether it can be undone is decided in the change and written down either way.
