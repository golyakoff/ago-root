# The calendar add-on, and the quota it grants

- **Stage**: 22
- **Status**: ready
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

- [ ] Enabling the add-on for N masters results in a calendar the tenant can configure, with no
      manual step anywhere.
- [ ] The (N+1)-th worker is refused by the calendar, inside its own transaction, proven by trying.
- [ ] Changing N takes effect, and the lowering rule is stated in writing and tested.
- [ ] The channel toggles beside it keep working — this screen is shared, so it is a regression
      surface, not a new page.
