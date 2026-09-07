# The free tier gives one seat where the market gives two, and retention has no per-tier window

- **Stage**: 13
- **Status**: done (2026-09-03), `ago-root#378`
- **Decided**: 2026-09-03 — the free tier is **two operators with two months of history**, matching
  Jivo's published free plan. The numbers are settled; only the implementation is open.

## Where the numbers are today

**Seats.** `Site.SeatLimit` defaults to `1` and `Site.Tier` to `"free"`;
`SubscriptionTierBands.TryResolveTier` starts its paid bands at `MinSeats = 2`, and its own comment
says 1 seat *"has no band at all — that is the free tier every site starts on."*

One seat means the owner **cannot invite a single colleague without paying**, so the product cannot be
tried by two people — which is how it is actually evaluated.

**Retention.** Genuinely built. `13-06` (done 2026-08-29) repartitioned `messages` by retention class,
prunes per class and archives before dropping, with `MessageArchiveJob` and
`MessagePartitionPruneJob` running it and `RetentionClass.FromTier` deriving the class from the tier.

**But the number is not per tier.** `MessagePartitionPruneJobOptions.RetentionHorizonMonths` is a
single `3`, described in its own remarks as an operational default protecting a 2Gi disk. So there is
a per-class mechanism with one global horizon inside it.

## What the competitor actually offers, checked rather than remembered

| Jivo free | |
|---|---|
| operators | 2 |
| conversation retention | 2 months |
| channels | MAX, Telegram, Odnoklassniki, Viber, Email |
| behind the paid tiers | WhatsApp, Avito, CRM, departments, routing |

Review sites claim five operators; that is the **partner** licence, granted for referrals or an
article, not the standard free plan. Paid starts at 742 ₽ per operator per month on a two-year term.

## The two decisions inside this

1. **Where the free ceiling and the paid band floor meet.** Free becomes 2 and `MinSeats` is already
   2, so moving one end without the other makes them touch. What a 2-seat *paid* subscription means
   has to be decided, not inherited.
2. **How a per-tier window coexists with the disk floor.** `RetentionHorizonMonths` exists to protect
   a 2Gi disk (`15-05` carries that argument). **The operational horizon stays a floor**, not a
   default a generous tier can silently override. Paid windows have no number yet; a mechanism that
   can express one is the deliverable, and inventing a business number is not.

## Why this is not part of Stage 22

It touches the same two files the calendar add-on will (`Site`, `SubscriptionTierBands`) but makes a
different promise: *the free tier is worth trying*. It lands green on its own, at any time, and
Stage 22 does not wait on it.

## Done when

- [x] A freshly registered site can invite a second operator without paying, proven by doing it. —
      `OperatorInviteEndpointTests.Invite_OnAFreshFreeTierSite_ASecondOperatorIsAdmittedWithoutRaisingTheSeatLimitOrPaying`
      (`ago-chat@f2bf0b8`).
- [x] A third is refused, with the refusal readable rather than a 500. —
      `Invite_OnAFreshFreeTierSite_AThirdOperatorIsRefused_WithAReadableErrorNotA500`. The boundary
      moved at both ends so the two lists still meet: `Site.SeatLimit` 1 → 2 and
      `SubscriptionTierBands.MinSeats` 2 → 3, so the paid bands start at the first seat count that adds
      anything over free.
- [x] Free-tier messages older than two months are pruned and a paid tier's of the same age are not —
      proven with two tiers, since one proves nothing about a per-class mechanism. —
      `MessagePartitionPruneJobTests.PruneAsync_WithTwoRetentionClasses_PrunesTheExpiredFreeTierRow_AndLeavesThePaidTierRowOfTheSameAge`,
      which is exactly the two-tier shape the box demands.
- [x] The disk floor still holds: no tier's window can push the partition count past what
      `RetentionHorizonMonths` was protecting. — `EffectiveHorizonMonths` returns `Math.Min` of the
      class's window and that ceiling, so the floor cannot be configured past, and
      `PruneAsync_WhenAClassIsConfiguredPastTheCeiling_TheCeilingWinsAndTheRowIsStillPruned` proves it.
      Both the prune job and the archive job compute their cutoffs from that one method, so they cannot
      drift against each other.
- [~] The 17 existing sites are migrated, not left on the old default. — **the migration is proven; the
      live count of 17 was never re-read.** `Stage13RaiseFreeTierSeatLimit` backfills with
      `UPDATE sites SET seat_limit = 2 WHERE tier = 'free' AND seat_limit < 2` — scoped so no paid row
      can match, idempotent if it runs twice — and
      `Stage13RaiseFreeTierSeatLimitMigrationTests.Migrate_ExistingFreeTierRowsStillAtTheOldDefault_AreRaisedToTwo_AndPaidTierRowsAreUntouched`
      proves it against a real Postgres. It cannot have been skipped on the node either, since every
      `ago-chat` migration after it applies in order behind it. What is missing is only the act of
      counting the node's rows afterwards, which no record shows. Not given a number: the deliverable
      shipped, and the number 17 was a description of the day the item was written rather than a thing
      still owed. (`23-55`, 2026-09-07.)

## Context

Found 2026-09-03 while designing the calendar add-on: the author's own description of the flow said
"two operators free", and the code said one. `13-01` gated invitations on the seat limit, so its tests
are a regression surface for this rather than a neighbour.
