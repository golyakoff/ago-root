# ADR-0166: A suspension is for enforcement, and its length is the owner's own to set

- **Status**: Accepted — 2026-09-13, in dialogue with the author (`22-08`)
- **Date**: 2026-09-13
- **Stage**: 22 (`22-08`)
- **Supersedes**: `adr/0149`'s own "The two parameters, answered" section only. Rules 1–3 of `adr/0149`
  — the lease-not-a-flag mechanism, proof-before-complete ordering, and chat's opacity to a module's
  data — are unchanged and this ADR does not touch them.

## Context

`adr/0149` answered two parameters on 2026-09-07: what a suspension is *for*, and how long the lease
**L** that bounds its worst-case propagation should be. Both answers were "suspension is a commercial
lever" and "L is 24 hours, renewed at 12" — reasoned from an asymmetry between a non-payer keeping one
extra day of a product they already had, and a payer losing a day of real business if AGO's own broker
were down.

`22-08`'s own text carried an open question next to that reading: whether the case this item actually
serves is the commercial one, or `decisions.md` §6's original motivating case — a suspected violation,
looked into. In dialogue on 2026-09-13, the author settled it, and settled it the other way from
`adr/0149`'s own answer:

- *«давай тогда зафиксируемся что приостановка у нас для нарушителей, я не вижу необходимости
  что-то приостанавливать в течение 24 часов для штатной ситуации»* — suspension is for violators, not
  a routine 24-hour commercial mechanism.
- Scope is **account-wide**, not add-on-only — `adr/0149`'s own inference from the commercial reading
  ("a commercial suspension is add-on-only... `22-08` is where it becomes real") does not survive the
  premise it was drawn from.
- The duration is **not a fixed system number at all**: *«я хочу иметь возможность при блокировке
  устанавливать время в минутах на которой я блокирую… я хочу иметь список заблокированных с
  возможностью продлить блокировку или разблокировать»* — an owner-chosen, per-suspension
  `suspended_until`, extendable or liftable from a console list.

`adr/0073` already answers non-payment with a downgrade, not a stop, and that stands regardless of this
ADR — the reversal here is only about what `adr/0149` itself inferred *from* the commercial reading, not
about non-payment's own handling.

The remaining piece `adr/0149` left as a number, L (the internal lease's own length, independent of what
triggers a suspension), was sized entirely around the commercial asymmetry that no longer applies. It
needs its own answer now, since "not a fixed number" describes the owner-facing duration
(`suspended_until`), never the internal robustness lease `22-08`'s own scope keeps: *"the lease merely
bounds how stale the calendar's own copy of 'is this account still suspended' can get before it fails
closed... an internal robustness detail underneath it, not a second thing anyone sets."*

## Decision

**What suspension is for**: a suspected violation, `decisions.md` §6's own original case — never
non-payment, which `adr/0073`'s downgrade already handles completely. There is no commercial-lever case
left for a lease length to be reasoned about in terms of.

**Scope**: account-wide. Chat stops serving new sessions and blocks operator sends; the calendar refuses
new bookings the same way, on the same lease mechanism `adr/0149` rule 1 already built.

**The owner-facing duration is not this ADR's number.** `suspended_until` is set in minutes by the
platform owner at the moment of suspending, extended or lifted from a console list, and a suspension
nobody touches lifts itself once it passes — all `22-08`'s own scope, unchanged by this ADR.

**The internal lease length is 5 minutes, renewed at 2.5** — replacing `adr/0149`'s 24-hours-renewed-
at-12, which was sized for a case that no longer exists. The reasoning is the same *shape* `adr/0149`
used, with the asymmetry now read the other way: an enforcement suspension exists because the owner
already decided there is a problem serious enough to freeze the account over, so the cost of the lease's
own ceiling is *continued violation* for up to L if the broker is down — the smaller L is, the better,
subject to the same "no invented figure" constraint `CLAUDE.md` states. Nothing about renewal cost argues
for a longer L here: `adr/0149`'s own "negligible at any tenant count this project will see" holds even
more strongly, because renewal traffic is proportional to *currently-suspended* tenants specifically, a
number smaller than the entitled-tenant count that reasoning was already applied to. Five minutes also
keeps the ceiling meaningfully tight against the shortest suspension an owner is likely to actually set
(the console list exists precisely because a short block-and-reconsider is a real usage pattern), which
24 hours would not.

**No number here was measured**, the same caveat `adr/0149` states about its own 24/12: this deployment
has no recorded broker-outage distribution, and the argument is from the asymmetry of costs, not from a
measurement.

## Consequences

- **`adr/0149`'s own "add-on-only" inference is retracted, not merely superseded by omission.** A reader
  who reaches `adr/0149` alone would build the wrong scope; this ADR exists so that reader is redirected
  rather than left to notice the contradiction between two accepted documents on their own.
- **The lease is now five orders of magnitude shorter than it was designed to be.** `adr/0149`'s renewal-
  traffic argument was sized against every entitled tenant; here it only ever runs against tenants
  actually under suspension, which this project expects to be rare — but "rare" is not "zero", and a
  future where suspensions become common would need this revisited with real numbers, not before.
- **The console list `22-08` scopes (extend/unblock, currently-suspended accounts) is now load-bearing
  for the lease's own health, not just an owner convenience**: an owner who suspends and forgets relies
  on the suspension expiring on its own, which it does, but a five-minute internal lease renewing only
  while the account is suspended means the mechanism's own liveness is exercised continuously for as
  long as any account is under it — worth monitoring the same way outbox lag already is (`nfr.md`),
  named here so `22-08`'s own implementation does not have to rediscover it.
- **`adr/0149`'s rules 1–3 are entirely unchanged** — this ADR only replaces its own stated parameters,
  not the mechanism they parametrise.

## Alternatives considered

- **Leave `adr/0149`'s 24/12 in place and read `22-08`'s duration as the console-facing knob layered on
  top of it.** Rejected: the two numbers would then disagree about what they bound — `adr/0149`'s 24
  hours was reasoned as the *worst case a payer should ever wait*, which stops being the right question
  once the trigger is enforcement rather than commerce. Keeping a stale number because retiring it is
  more paperwork was rejected on the same grounds `adr/0156` gives for not letting an accepted ADR carry
  its own quiet reversal.
- **Make the internal lease length itself an owner-configurable value, same as `suspended_until`.**
  Rejected: `22-08`'s own text is explicit that the internal cadence is "not a second thing anyone
  sets" — surfacing it as a setting would let an owner accidentally widen the calendar's own worst-case
  staleness while believing they were only choosing how long to suspend an account for.
- **Derive the internal lease from the owner's chosen `suspended_until` (e.g., half of it).** Rejected:
  it would make the calendar's own staleness bound depend on a value chosen per-incident for an
  unrelated reason, and a one-minute suspension would need a lease under thirty seconds — a number with
  no basis of its own, for a saving (fewer renewal messages during very short suspensions, which are
  already the rare case) that is not worth the coupling.
