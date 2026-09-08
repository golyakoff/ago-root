# a lapsed subscription never touches the add-on it paid for

- **Stage**: 22
- **Status**: done
- **Sharpened 2026-09-08 by `adr/0159`**: an option is now its own subscription with its own period, so
  an option's *own* non-payment lapses it and that half is `23-86`'s ordinary work. What is left here is
  the harder question and it is entirely commercial: **when the base lapses, what happens to an option
  that is still being paid for?** The author has said a channel is meaningless without chat — which is
  an argument, not yet a decision, and the two readings below still stand. AGO Calendar is the same
  question with a different likely answer, because `ago-business/0008` made it a separate product with
  its own subscription rather than an add-on to this one.
- **Depends on**: nothing to find it. `22-08` (suspension) is where the mechanism would live.
- **Found**: 2026-09-07, while designing `22-08`.

## What is actually true

`SubscriptionRenewalApplier` and `MarkLapsed` write neither `EnabledModule` nor `ModuleQuantityGrant`.
A tenant whose subscription lapses is downgraded to the free chat tier — `adr/0073` chose a downgrade
over a stop deliberately — and **keeps the calendar add-on, and its full worker quota, indefinitely.**

Nothing expires it, nothing revokes it, nothing tells the calendar. The add-on outlives the payment
that bought it, for as long as the account exists.

## Why this is not simply a bug to fix

`adr/0073` decided that non-payment produces a **downgrade rather than a stop**, and that reasoning is
sound for the chat tier: a shop that misses a payment should not have its customers meet a dead widget.
Whether it extends to a paid add-on is a different question with a different answer, and nobody has
taken it.

Two shapes, and the choice is the author's:

- **The add-on lapses with the subscription.** What was paid for stops when payment does, which is what
  a customer would expect of an add-on. Needs `22-08`'s suspension mechanism, and needs an answer to
  what happens to bookings already made — `22-07` already says nothing a shop typed is destroyed by a
  billing action, and a stranger's appointment is not leverage.
- **The add-on survives, deliberately**, as part of the same generosity `adr/0073` chose. Then it is not
  a defect at all — but it must be written down, priced, and said out loud, because right now it is
  neither a decision nor a mistake, just something nobody wrote.

## Why it matters now rather than later

The first paying customers are weeks away. This is the difference between an add-on that is sold and an
add-on that is given away to anyone who stops paying, and it is cheaper to decide before there is a
customer on the wrong side of it.

## Done when

- [x] Chosen by the author on 2026-09-08 and recorded as [`adr/0160`](../adr/0160-a-paid-option-outlives-the-tier-that-lapsed-under-it.md):
      **a paid option is not cancelled by the lapse of the tier beneath it.** It runs on its own
      subscription and its own money - the base falls to the free tier and the option keeps working for
      as long as it is paid for. "Maximum a year" is the horizon of one paid period, not a stop.
- [x] Implemented by **declining to add a mechanism**, which is the unusual part and the reason it is
      worth stating: `adr/0159` gives an option its own subscription with no relationship a charge can
      traverse, so "the base lapsing does not touch the option" is already true by construction. An
      implementation that checks the base's status to decide an option's fate has misread it.
      The half this item originally described - *nothing revokes an add-on at all* - is `23-86`, where
      an option's own lapse revokes its own entitlement.
- [x] Answered in `adr/0160` rather than by editing `adr/0073`, which is immutable (`adr/0156`). It
      covers them, and in the same generous direction: nothing a tenant paid for is taken away because
      something else was not paid for.
- [x] **A contradiction found while checking this, and carried out to `23-116`.** The commercial grid
      exempts an account from auto-deletion for inactivity under the *paid tier's heading*, so an
      account that is on the free tier and paying for a channel would be deleted for not signing in -
      taking its conversations and contacts with it while its card is charged. The exemption belongs to
      the fact of payment, not to the name of a tier. Cheap to fix because `23-73` is not built.
