# AGO Inbox × AGO Calendar: unified operator queue

- **Stage**: 21
- **Status**: blocked — a real, unresolved integration-mechanism question (below); no implementation
  starts until the author picks a direction
- **Depends on**: `14-01`..`14-05` (AGO Inbox surfacing every AGO Chat conversation, regardless of
  channel, in one place already — true by construction once Stage 14 ships, since every channel maps
  into the same `Conversation`/queue) and `20-04-confirmation-sweep-and-operator-queue.md` (AGO
  Calendar's own pending-bookings queue, the second thing this item would merge in)

**See `20-08` first (added 2026-08-26).** It asks what a chat operator may *do* to a booking, which
comes before where they see it: a unified queue showing a booking nobody in that screen may act on is
a worse outcome than two queues.

## Goal

A conversation from the widget, a conversation from any of AGO Inbox's own channels, and a booking
confirmation request from AGO Calendar's own pending-bookings queue (`20-04`) all surface in the *same*
operator-facing queue/console — the actual point of calling the whole channel-expansion effort "a
single window," per the product spec's own framing. `adr/0027` already resolved the domain-model half
of this question (AGO Calendar's `Operator` is never the same row as AGO Chat's), which means this item
is real, deferred, cross-product integration work, not a natural consequence of anything already built
— exactly as that ADR's own Consequences section named it.

## Context to read first

`docs/adr/0027-operator-identity-across-products.md` in full, especially its Consequences section's own
"a genuinely unified operator queue... is real, deferred, cross-product integration work" line — this
item is that work, and should not re-litigate the Operator-identity decision that ADR already made.
`docs/architecture/repositories.md`'s cross-repository-change ordering ("platform branch... product
branch... deploy branch... docs") — whichever mechanism this item picks will very likely need changes
in both `ago-chat` and `ago-calendar` (and possibly a new shared console surface), so read this section
before scoping the actual change sequence, once a direction is chosen. `docs/architecture/messaging.md`'s
"Delivery guarantees and idempotency" — directly relevant if the chosen mechanism turns out to be
"AGO Calendar publishes an event AGO Chat's own console (or a new aggregating service) consumes,"
rather than a synchronous API-merge.

## Scope — deliberately not written as an implementation plan

Two real, structurally different candidate mechanisms, named for the author to choose between, not
decided here:

- **Console-side dual-API merge.** Whichever console a working operator actually uses calls both
  `Ago.Chat.Api`'s own conversation-queue read and `Ago.Calendar.Api`'s own pending-bookings read, and
  merges the two client-side into one list. Simple, no new backend integration, but couples whichever
  console does this to both products' own APIs directly, and only works if that operator is
  authenticated against both (an unsolved provisioning-friction point `adr/0027`'s own Consequences
  already names: "provisioning an operator for both products is two actions, not one").
- **A lighter cross-product notification path.** AGO Calendar publishes an integration event on a
  pending booking (reusing `20-04`'s own `BookingConfirmed`-shaped event, or a new one for "booking
  needs attention" specifically) that some AGO Chat-side consumer turns into a real, first-class item
  in AGO Chat's own existing queue — closer to how AGO Chat's own webhook deliveries already surface in
  a tenant-visible history today, but a genuinely new cross-product wire contract neither product's own
  `Contracts` project has needed before (state explicitly, once a direction is chosen, whether this
  becomes a new shared contracts package, or each product keeps its own and a small translation layer
  sits between them — the platform-vs-product boundary rules in `clean-architecture.md` apply to this
  decision the same way they apply to any other, and a naive shared `Ago.Platform.Contracts` package
  would very likely fail the same "contains no domain concept" test `adr/0027` already applied once).

## Out of scope

- Building either mechanism — genuinely blocked, per the same reasoning `21-01` states for its own
  open question.
- Any change to `adr/0027`'s own Operator-identity decision — this item works within that decision, it
  does not reopen it.

## Done when

Not yet meaningful — this item has no `Done when` until the open question below is answered and the
item is re-scoped as a real implementation plan for whichever mechanism is chosen.

## Open questions

**Which integration mechanism to build** — genuinely unsolved, named plainly per the author's own
explicit instruction not to invent an answer here. Whichever direction is chosen deserves its own ADR
before implementation starts (`docs/adr/README.md`'s own "a reviewer would ask why on earth" test
applies directly to a genuine cross-product architectural boundary decision like this one), not a
choice folded silently into this item's own eventual Scope rewrite.
