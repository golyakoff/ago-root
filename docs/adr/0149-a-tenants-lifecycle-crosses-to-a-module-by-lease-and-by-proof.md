# ADR-0149: A tenant's lifecycle crosses to a module by a lease and by a proof, never by a fire-and-forget event

- **Status**: Accepted — 2026-09-07. The two parameters were the author's and they answered both the
  same day; see *The two parameters, answered*.
- **Date**: 2026-09-07
- **Stage**: 22 (`22-08`, `22-30`, `22-31`, `22-32`)
- **Qualifies**: ADR-0098's "a grant's expiry binds chat only; the module is never told" — see
  *Consequences*. That sentence stays true for the case it was written about and stops being the
  general rule.

## Context

`adr/0093` kept two products in two schemas and named the cost in its own Consequences: *"Tenant
lifecycle becomes cross-product work, and this is the honest cost."* Three operations were listed —
suspension, erasure, export — and none of the three has been built.

**The propagation pattern already exists, three times.** `RoleAssignmentsChanged` (`22-05`),
`ModuleQuantityGranted` (`22-07`) and `ContactVisibilityChanged` (`23-12`) each ride chat's outbox to
a consumer in `Ago.Calendar.Worker` that writes a calendar-local row, which the calendar then reads
inside its own transaction — rule 8's answer to "the calendar must not ask chat at write time". Each
is a snapshot rather than a delta, so a redelivery is a no-op and out-of-order delivery cannot land on
a wrong value permanently. The pattern is sound and this ADR does not change it.

**What the pattern does not carry is a bound.** Its guarantee is *eventual*, with no stated ceiling,
and for the three facts it carries today that is adequate: a permission that arrives late means an
operator is briefly refused something they should have; a quota that arrives late means one worker is
refused; a visibility rung that arrives late means a phone number is briefly masked. Every one of
those fails in the safe direction.

**Suspension fails in the other direction, and the more it fails the worse it gets.** A late message
means a suspended tenant keeps taking bookings, and every minute of lateness is more bookings. `22-08`
is filed with a Done-when that says the staleness bound is a number the item must *state*, not hope
for — and a plain event cannot produce one. It can produce a measurement of the healthy case, which is
a different thing.

**Erasure has the same shape at the other end.** `personal-data.md` and `16-03` require a tenant's
data to be removable; over at-least-once delivery, the system must be able to show that the second
half *completed*, not that a message about it was published. Chat's own `SiteErasureJob` already
embodies the right instinct here: it will not delete a site row until it has *observed* that the
conversations are gone, and it keeps a receipt (`erasure_records`, `24-13`) it marks `Failed` rather
than leaving to look pending.

**And the boundary is opaque by construction.** There is no `calendar` literal and no
`using Ago.Calendar` anywhere in `Ago.Chat.*`; an architecture test enforces it. Chat cannot read a
module's rows and must not learn a module's schema — which constrains what an export can look like
more than it first appears.

Two further constraints. `adr/0098` decided that an owner grant's `ExpiresAt` binds chat alone and
*"the module is never told"*. And `adr/0073` has already decided the non-payment case for chat: a
lapsed subscription downgrades to the free tier. Neither of those is the same act as a suspension, and
this ADR must not be read as changing either by implication.

## Decision

**Three rules. They are one shape: a fact that governs a module's writes is held by the module with
an expiry on it, and an operation on a module's data is finished when the module says so and chat has
read the answer.**

### 1. An entitlement a module enforces is a lease, not a flag

The projected row on the module's side carries a `valid_until`, compared against the module's own
clock **inside the transaction that performs the write it gates**. Chat renews it on a schedule, at
half the lease length, so a single missed renewal expires nothing. Suspending a tenant is chat
*declining to renew*, plus an immediate event that brings the effect forward.

That produces two numbers, and both are stated rather than one being implied:

- **The ordinary effect** is one outbox hop. `LISTEN`/`NOTIFY` wakes the dispatcher on a fresh row and
  `OutboxDispatcher.PollInterval` (5 s) is only the fallback for a coalesced notification; the
  deployment already alerts on 60 s of outbox lag (`15-03`, `nfr.md`). This number is a measurement,
  and it is the one that holds when everything works.
- **The ceiling** is the lease length **L**, and it holds when nothing works — broker stopped,
  consumer crashed, chat itself down. Past `valid_until`, the module refuses the writes the lease
  gates. **Fail-closed.**

The lease is not a new mechanism. It is `EnabledModule.ExpiresAt` — an expiry checked live, inside the
read that decides, never swept by a job — moved to the other side of the boundary. What is new is who
holds it.

### 2. A lifecycle operation completes when the module proves it, never when chat has sent it

Erasure and export both end with chat **asking** the module over the credentialed per-site channel
(`22-02`) and reading the answer, on a job tick that already polls. A receipt is never marked complete
on the strength of a published event, and a module that does not answer never auto-completes: after a
stated window the receipt is `Failed`, naming the module, and a `Failed` receipt is retryable and
visible.

Ordering follows from this and is load-bearing rather than cosmetic: **the module's half first, chat's
own row last.** The per-site entry point and credential live on the `EnabledModule` row, which cascades
with `sites` — so the instant chat deletes its own row it loses the address of every module holding
that tenant's data, and can neither finish the operation nor describe what is left. This is the same
class of reasoning `SiteErasureJob`'s own remarks already give for reading archive keys and Keycloak
subject ids before the delete.

### 3. Chat never parses a module's data

A module's half of a tenant export enters the archive as **one opaque member the module produced**,
with its own internal format and its own format version, listed in `manifest.json` and never read.
Chat proves it arrived; it does not know what is in it.

An export writer emitting `workers.jsonl` would be the moment `Ago.Chat.*` learned what a module *is*
— the boundary crossing arriving through a data format rather than a project reference, which is
precisely the failure `ModuleKey`'s own remarks describe for the enum it refuses to be.

## Consequences

- **`adr/0098`'s "the module is never told" is qualified, in the open.** It stays true for what it
  decided — a *trial grant lapsing* in chat does not reach the module, and a tenant does not lose a
  calendar because a discount ended. It stops being the general rule: a suspension does reach the
  module, because the whole point of a suspension is that it binds where the work happens. Two
  entitlement facts, two behaviours, and the difference is stated rather than discovered.
- **A new failure mode the product does not have today: AGO's own broker outage can stop a paying
  tenant's bookings, after L.** This is the real cost of a bound that is a bound, and it is not
  mitigated away. What softens it is that renewals run at L/2 (one missed renewal expires nothing) and
  that the outbox-lag alert fires at 60 s, so reaching L means a person has been ignoring a page for
  most of L. It remains possible.
- **Renewal traffic proportional to entitled tenants.** Two messages per tenant per lease period.
  Negligible at any tenant count this project will see; stated so that a future L measured in minutes
  is chosen with the multiplication in view.
- **Two clocks.** The module compares `valid_until` against its own `IClock`; chat sets it from its
  own. Both are UTC `DateTimeOffset` (rule 11) and today both run on one node, so skew is bounded by
  NTP and swamped by any L worth choosing. A short L narrows that margin, which is one more reason the
  parameter is not free.
- **Erasure gets slower and more honest.** It now spans at least one extra job tick per module and can
  end `Failed` for a reason that is somebody else's deployment. That is the correct trade: an erasure
  that reports success without proof is the failure this whole ADR exists to prevent.
- **The export archive grows a member chat cannot validate.** Chat can check that it arrived and how
  big it is, and nothing else. A module that produces a corrupt archive produces a corrupt member, and
  chat will say it was included. Named rather than solved; the alternative is chat learning the
  format, which rule 3 forbids for a stronger reason.
- **The reconciliation check (`22-32`) becomes necessary rather than nice**, because rules 1 and 2
  both assume chat knows which modules hold a tenant's data. When that assumption is wrong — a revoke
  that orphaned a tenancy row, a half-failed provisioning — nothing else in the system can see it.

## Alternatives considered

- **Event only, no lease** — publish `TenantSuspended` and let the projection be eventually
  consistent, as the three existing facts are. Simplest, and it is what the pattern already does.
  Rejected because it cannot produce the number `22-08` requires: the honest statement would be "the
  bound is however long the broker is down", which is not a bound. It also fails *open* — the
  direction where the failure is a suspended tenant continuing to trade — whereas every other
  eventual fact in this system fails closed by accident.
- **The module asks chat at write time.** Rejected twice over, and `22-07` already rejected it for the
  quota: rule 8 forbids a write decision resting on a read of something outside its transaction, so
  the answer is a cache by the time the transaction commits — and it puts a cross-product network call
  on a booking path.
- **A lease that fails open** — past `valid_until`, keep accepting and log loudly. Attractive because
  it removes the new failure mode above. Rejected because it is the event-only option with extra
  machinery: an entitlement that keeps working when it cannot be verified is not an entitlement, and
  the ceiling it states is fictional.
- **Express suspension as a quantity grant of zero.** Tempting — the mechanism exists and is already
  wired end to end. Rejected: `ModuleQuantityGranted` gates *creating a worker*, so a zero grant stops
  a tenant hiring and leaves every existing worker taking bookings. It suspends the wrong thing, and
  overloading it would make one event mean two facts that need to be true independently.
- **Express suspension as a revoke.** Also rejected, and more sharply: a revoke deletes the
  entitlement row, so lifting a suspension would be a re-provisioning with a new credential rather
  than a write on the account — and `adr/0118` has already spent a document establishing that a revoke
  is an act with its own weight and its own recorded reason. A suspension that is a revoke underneath
  cannot be undone cheaply, and a suspension that cannot be undone cheaply will not be used.
- **Chat drives the module's erasure by deleting its rows directly** — one connection string, two
  databases, one transaction-ish. Rejected on `adr/0093`'s own terms: it is Variant A arriving through
  a job, it would put a `calendar` schema literal inside `Ago.Chat.*`, and Postgres would still not
  give one transaction across two databases, so it buys none of the atomicity it appears to.
- **Two-phase commit across the two databases.** Named because a reviewer will ask. Rejected: it needs
  a transaction manager and a prepared-transaction lifetime this project has nowhere to put, and it
  converts "one side failed, retry next tick" — a recoverable state that is already how every job here
  works — into "a prepared transaction is holding locks and nobody knows why". The honest answer to
  "both, atomically" is that it is not available, and rule 2 is what replaces it.

## The two parameters, answered

Both were the author's, and both were answered on 2026-09-07. They are recorded here as answers rather
than left in the section that asked them, because an ADR whose open questions are closed should read as
a decision and not as a form.

**Suspension is a commercial lever.** Not `decisions.md` §6's stop-the-abuser case, which was the other
reading. That was the load-bearing choice: the ADR argued that choosing L without choosing this is
choosing it by accident, and this is the half that sets it.

**L is 24 hours, renewed at 12** — the ADR's own recommendation, which follows from the answer above.
The argument stands as written and is worth keeping visible because no part of it was measured: a
non-payer taking one more day of bookings costs one day of a product they already had, while a payer
whose bookings stop because AGO's broker was down costs a client. The asymmetry is the ground; there is
no recorded broker-outage distribution in this deployment and inventing one would be the invented figure
`CLAUDE.md` forbids.

**What follows, and is flagged rather than assumed.** A commercial lever sits beside `adr/0073`, which
already answers non-payment with a **downgrade rather than a stop**. So the natural reading is that a
commercial suspension is **add-on-only** — it takes away what was bought, not the account. That is an
inference from two decisions rather than a third answer, and it is written here so it can be contradicted
in one sentence rather than discovered in an implementation. `22-08` is where it becomes real.

**No number here was measured.** This deployment has no recorded broker-outage distribution and inventing
one would be exactly the invented figure `CLAUDE.md` forbids; the argument above is from the asymmetry of
costs, which is the only ground available.
