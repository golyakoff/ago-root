# Usage-cap entitlements: attachment storage, history retention, site count

- **Stage**: 13
- **Status**: blocked
- **Depends on**: `13-01-operator-invitations-and-seat-entitlement.md` (the `sites.tier` column this item's
  caps are keyed against, and the enforcement-pattern precedent — a DB-sourced, never-cached, atomic check
  at the one real write path a cap can bind to)

## Goal

`roadmap.md`'s Stage 13 deliverable line names this explicitly as conditional, not required: "seat count
at minimum; attachments/history/site-count caps **as those business decisions land**." They have not
landed. This item exists to hold that named-but-not-yet-buildable scope in one place, rather than leaving
it to be silently forgotten or, worse, silently built on an invented number. **Reading, stated plainly**:
Stage 13 does not need this item to be buildable for its own done-when to be true — `13-01`/`13-02`/`13-04`
already deliver "a real card can subscribe a self-registered account to a paid tier through ЮKassa, and
entitlements enforce that tier's limits" for the one limit (seat count) that has a real, decided number
behind it. Attachment storage, history retention, and site count do not have decided numbers or, in one
case, a decided *policy* at all — see Open questions.

## Context to read first

`docs/backlog/13-01-operator-invitations-and-seat-entitlement.md`'s own "multi-identity loophole" section
— read closely; it already covers most of what "site-count cap" would otherwise re-litigate, see the
Open questions note on that below. `docs/architecture/caching.md`'s "never cache what a write decision
depends on" — whichever cap eventually gets built, its enforcement point follows the same pattern `13-01`
already established (an atomic, DB-sourced check inside the write transaction it guards), not a new
mechanism. `docs/backlog/10-02-site-and-operator-registration.md`'s Out of scope — the explicit decision
*against* a separate `Account` aggregate above `Site`, with the reasoning that introducing one for a
concept with no second real caller today would be premature generalisation. Read this closely before
assuming "site-count cap" implies a new aggregate — it does not, see Open questions.

## Out of scope (until unblocked)

Everything — this item builds nothing until the questions below are answered. Naming likely shape here
only so a future session does not start from zero once unblocked, not as committed scope:

- An attachment-storage byte cap, keyed by `sites.tier`, enforced the same atomic-check pattern `13-01`
  established (most likely a running-total check against `attachments.size_bytes` at upload-confirm time,
  `5-03`/`5-04`'s existing write path) — mechanically straightforward once a real number exists for each
  tier; the mechanism is not the blocker, the number is.
- A history-retention window for the free tier (a scheduled deletion/archival job, similar in shape to
  `2-06`'s `PartitionMaintenanceJob` but dropping old data instead of creating new partitions) — **not**
  mechanically straightforward once decided, because the decision itself is binary and consequential
  (delete real customer conversation history, or don't) — see Open questions, this is the actual blocker
  for this whole item, named explicitly by the business context this stage was planned against as
  genuinely undecided, not merely unbuilt.
- Whatever "site-count cap" turns out to mean once the question below is answered.

## Done when

Not yet defined — cannot be, without the answers below.

## Open questions

- **Free-tier history retention: time-boxed (Slack-style, a rolling retention window past which older
  messages/conversations are deleted or archived) or unlimited history regardless of tier?** Stated
  explicitly, for this stage's own planning: **this is genuinely unresolved, not just unbuilt** — it is
  not decided anywhere in this repository, and it is not decided in the private business repository either
  (confirmed directly by the author while this stage was being planned, not inferred). This is the
  headline reason this item is blocked rather than merely deferred: a retention policy is not an
  implementation detail a session could reasonably default on the project's usual "reasonable default, tune
  later" terms — deleting a real customer's real conversation history on a wrong guess is not a reversible
  mistake the way a mistuned rate-limit bucket is.
- **What is the actual attachment-storage byte cap per tier (or per seat, or flat per site)?** Not stated
  anywhere. `CLAUDE.md`'s "do not invent numbers, benchmarks, or 'typical production' figures" applies
  directly — this item will not manufacture a plausible-sounding megabyte figure to fill this in.
- **What does "site-count cap" actually mean, given `10-02` already deliberately rejected a separate
  `Account` aggregate above `Site`?** Two readings are possible, and nothing decides between them:
  1. It is the same question `13-01` already named as an accepted, not-closed gap: one real person
     operating more than one free-tier site via multiple Keycloak identities, since enforcement is
     per-identity, not per-person. If this is what "site-count cap" means, it is **not a new cap to build**
     — it is the identity-correlation problem `13-01`/`12-02` already described, requiring either capturing
     operator email at registration or a live Keycloak Admin API call, both already named there as real,
     separate, deferred work with their own cost (a new class of secret this project has avoided holding).
  2. It could instead mean a genuinely new feature: a *paying* account being allowed more than one `Site`
     under one subscription/payment method — which would be new product scope no roadmap stage has
     described, and would be exactly the trigger `10-02`'s Out of scope named for revisiting the
     `Account`-aggregate decision "with real requirements in hand." Nothing in the business context given
     for this stage states this is wanted.
  Which of these `roadmap.md`'s wording intended is not resolved by anything available to this planning
  session, and picking one to build would risk building an entire aggregate the business does not actually
  want, or, conversely, silently dropping a real requirement. Named here explicitly so the author can say
  which (if either) is meant, rather than either being guessed.

This item does not start until the author answers at least the first question (history retention); the
attachment-byte-cap number and the site-count-cap meaning can, in principle, be answered independently and
would not by themselves fully unblock this item without the retention question also being settled, since
all three were named together in the same roadmap sentence and are being tracked together here rather than
fragmented into three separately-blocked files with no real difference in what unblocks each of them today.
