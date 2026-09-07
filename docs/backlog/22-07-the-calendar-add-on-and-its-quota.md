# The calendar add-on, and the quota it grants

- **Stage**: 22
- **Status**: done (2026-09-06)
- **Depends on**: `22-04`, `22-05`

## The shape the author asked for

A feature list on the tenant's own settings screen, checkboxes down one side:

```
[ ] MAX bot        [x] Telegram bot      [ ] WhatsApp   … 
[ ] Master calendar for [ N ] masters
```

Tick it, enter the number of masters, pay (YooKassa, already built for seats), and the calendar
becomes available — its settings, its screens, its widget entry.

**The calendar is an add-on product, not a tier.** `SubscriptionTierBands` derives the tier from the
seat count (`starter` 2–9, `growth` 10+), which is a size, not a bundle. Masters are their own
dimension and do not belong in that ladder.

## The crossing, which is the hard part

The add-on is **sold in chat** and **enforced in the calendar**, which owns `workers`.

Rule 8: a write decision never reads a cache. So the granted N lives in the **calendar's own
database**, on the tenancy row `22-03` keeps, and the calendar refuses the (N+1)-th worker inside its
own transaction. Chat grants; the calendar holds and applies. Propagation rides the outbox.

The alternative — the calendar asking chat at write time — is worse twice over: a cross-product
network call on a write path, and still a cache by the time the transaction commits.

## What must be got right rather than discovered

- **Lowering N below the workers already created: the excess is deactivated.** Decided by the author,
  2026-09-05, choosing among the three this item named — refuse the change, deactivate the excess, or
  let it sit over quota.
  What that commits to, stated so the implementation does not have to re-derive it: the change is
  **accepted**, not refused, so a tenant reducing their plan is never blocked by data they already
  created; the excess workers stop being usable rather than being deleted, so nothing a shop typed is
  destroyed by a billing action; and the over-quota state does not exist, so no screen has to explain
  it and no scheduler has to decide whether a deactivated worker may still take a booking.
  **Which workers are the excess is not decided here** and must not be guessed: an implementation that
  picks by row order is choosing for the tenant. Ask, or use a rule the tenant can predict and see.
- **Payment succeeded, provisioning did not.** Money taken and no calendar is the worst outcome here.
  Idempotent retry the outbox gives; what it does not give is anyone noticing — see `22-08`.
- The unified list mixes channels (internal to `Ago.Chat.*`) with a separate product. That is right
  for the person reading it and must not become right for the code: chat offers a **module**, and
  does not learn the word "calendar".

## Done when

- [x] Enabling the add-on for N masters results in a calendar the tenant can configure, with no
      manual step anywhere.
- [x] The (N+1)-th worker is refused by the calendar, inside its own transaction, proven by trying.
- [x] Changing N takes effect, and the lowering rule is stated in writing and tested.
- [x] The channel toggles beside it keep working — this screen is shared, so it is a regression
      surface, not a new page.

## Outcome (2026-09-06)

`adr/0125` carries the reasoning. Recorded here: what the item left open, and three things that are
true afterwards and would otherwise be assumed away.

**The item's own open question — which workers are the excess — was answered by a stated rule, not by
asking.** The most recently created active workers are deactivated first, tie-broken by `WorkerId`
(a UUIDv7, itself time-ordered) descending, until the active count matches the new quota. The property
that makes it defensible is predictability rather than fairness: a tenant sorting their own worker list
by "added on" sees exactly which ones a downgrade would cut. It is a pure function in
`Ago.Calendar.Domain` (`WorkerQuotaPolicy`), unit-tested with no database at all.

**Nothing is deleted and the downgrade is never refused.** A lowered quota deactivates; the rows stay,
so an upgrade restores them. That is the kindness in the design — and it is exactly what makes `22-23`
possible, below.

**A real gap, found by this item's own worker and deliberately not fixed here.** `UpdateWorkerHandler`
— `PUT /workers/{id}` with `IsActive: true` — reactivates without any quota check, so a tenant can walk
straight around a downgrade one worker at a time through the ordinary edit screen. Verified by reading
the handler rather than accepted on report. It is filed as **`22-23`**: closing it needs a new
repository method, a restructured handler and its own concurrency tests, which is a second promise
(rule 15) rather than a corner of this one.

**The chat-side migration was regenerated at landing, and the reason is worth recording.** It was
generated against a base that predated `23-11`, so after the rebuild its `Designer.cs` described a
model without `contact_reveals` or `sites.contact_visibility` while the migration itself now applies
*after* them — the "snapshot that is a lie" `CLAUDE.md` rule 13 names. Regenerating was safe here
because the migration is pure EF output with no hand-written SQL, and the regenerated `Up()` is
**byte-identical** to the original, which is the check that makes regeneration safe rather than hopeful.

**What is not proven, stated rather than implied — was, and is closed by `23-66`.** No test in either
repository exercised a real RabbitMQ round trip between chat's outbox publish and the calendar's
consumer — the same honestly stated gap `22-05` left for `RoleAssignmentsChangedConsumer`. Each side
was proven in isolation: chat staged the envelope in the right transaction, the calendar applied a
grant correctly when called directly. The wire between them was not — and, separately, there was no
route to call at all: `GrantModuleQuantityHandler` existed and was registered in DI, but nothing in
`Ago.Chat.Api` ever mapped it to an endpoint, so `WorkerQuota` was zero for every tenant that would
ever exist and no calendar tenant could create their first worker. Neither half was found until
`23-66` (filed 2026-09-07, while designing `22-08`), which added the platform owner's own route, the
console screen, and a real-broker integration test proving the wire this item's own report named as
unproven. **This item's own first Done-when — "results in a calendar the tenant can configure, with no
manual step anywhere" — was ticked here and was not true until `23-66` shipped**; it is true now.
