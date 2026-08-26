# ADR-0059: The booking claim is a compare-and-set, and a lost race is not an error

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 20 (`backlog/20-03-booking-and-lead-card.md`)
- **Builds on**: `adr/0049` (one row is both the slot and the booking), `adr/0053` (the rows exist
  before anybody books them)

## Context

AGO Calendar exists to answer one question correctly under load: *is this slot still free?* `20-01`
and `20-02` built everything that question needs — a row per slot, a status on it, an exclusion
constraint stopping two rows covering one worker, and a job that materialises the rows in advance.
`20-03` is the item that finally asks it.

Three forces shape the answer, and only the first is about concurrency.

**One.** The endpoint is **unauthenticated**. A customer books with a phone number and no account;
`Customer` has no password by design. So the usual thing that stands between the public internet and
a write — a token — is not available, and everything else has to do more work.

**Two.** The product's central design decision is a **two-step mechanic**: the customer is told
instantly that they are booked, while the row only reaches `PendingConfirmation` with a deadline and
an operator may still veto it (`20-04`). A booking product whose customer waits for a human loses to
the phone call it replaces; a shop that cannot refuse a booking will not use the product at all. The
design puts the uncertainty on the side that can absorb it.

**Three.** Everything a booking writes is **personal data**. A phone number is this product's most
directly identifying field (`personal-data.md`), and a lead card is *meant* to name a person.

## Decision

### The claim is one `UPDATE`, and its rows-affected count is the verdict

```sql
UPDATE events
SET status = 'PendingConfirmation', customer_id = @customerId,
    service_id = @serviceId, confirmation_deadline = @deadline
WHERE id = @eventId AND calendar_id = @calendarId
  AND status = 'Available' AND starts_at > @now
RETURNING worker_id, starts_at, ends_at, local_date;
```

**Why, restated rather than cited** — this is the second time this codebase makes the call, and a
precedent nobody can re-derive is a precedent that erodes. A booking must know the slot is free *at
the instant it takes it*. An EF aggregate write cannot express that as one operation: it reads the
row, decides in memory, and writes back, and between the read and the write another customer's claim
can land. EF's own answer to that gap is optimistic concurrency, which converts the second customer's
attempt into a `DbUpdateConcurrencyException` the caller must catch, interpret and retry — on the
hottest, most contended path in the product, for an outcome that is not exceptional. A single
`UPDATE` has no gap: Postgres evaluates the predicate and applies the change under the same row lock,
so of two simultaneous callers one gets 1 row and the other gets 0, and neither has to know the other
existed. The predicate names the same row's own column, so there is no earlier read to go stale.
CLAUDE.md rule 8 is this written down; `6-09` is the worked example of the read-then-write version
losing a slot on every close.

**Every condition lives in the `WHERE` clause.** `calendar_id` is there because the route's calendar
id is the only thing binding an unauthenticated request to a tenant, and a condition that merely
validates is a condition a future caller can forget; `starts_at > @now` is `Event.Claim`'s own
precondition, restated where it cannot be checked against a reading from milliseconds ago.
`RETURNING` supplies the confirmation from the write itself rather than from a follow-up `SELECT`
that would observe a row a later transition could already have moved on.

### A row count of 0 is an ordinary outcome

Never logged at `Error`, never a 500, never an exception, never distinguished from success by a
`try`/`catch`. It is what happens to the second of two people reaching for the last table. The port
returns `null`; the handler turns it into `409 booking.slot_unavailable`; the customer is told to
pick another time. `4-01` set this precedent explicitly and `concurrency.md` repeats it, and it is
restated here because it is the rule most easily lost the moment somebody adds a log line.

### The lead card is a real upsert, in the same transaction as the claim

`INSERT ... ON CONFLICT (tenant_id, phone) DO UPDATE ... RETURNING id`. `DO UPDATE` rather than
`DO NOTHING` so the statement returns a row on both paths and the caller learns the customer id
whether it inserted or collided — with `DO NOTHING` a collision returns nothing and the caller must
go and read the row it just failed to insert, which is a second round trip down a branch that only
executes under contention.

**The two statements share one transaction, and the reason is data minimisation, not consistency.** A
lead card without a booking harms nothing operationally. But writing a phone number for a claim that
then loses the race would mean an unauthenticated public endpoint accumulating identifying rows for
actions that never happened. One transaction makes a failed booking leave no trace. It also fixes a
single lock order — the customer row first, always — so two bookings from one number cannot deadlock
against each other.

The merge rules are decisions, not defaults: `GREATEST(last_seen_at, EXCLUDED.last_seen_at)` so a
request that was slow in flight cannot rewind the watermark (the rule `Customer.Touch` enforces in
memory, restated because this statement never goes through that method), and
`COALESCE(customers.display_name, EXCLUDED.display_name)` so a name an operator curated is never
overwritten by whatever a public form was typed into next time.

### The visitor-facing response cannot express the pending state

`BookingConfirmedResponse` has no `status` field, no `confirmationDeadline`, and no `state`. The
shape is the guard: there is nothing for an endpoint to set to `"pending"` by accident, and adding
one is not a small change but a reversal of the product's central decision.
`BookingConfirmationDisclosureTests` serialises a real response and fails if the JSON mentions a
pending state or a deadline at all, so the reversal cannot arrive as an unreviewed one-line addition
to a record.

### Two rate-limit buckets, and the phone is hashed in the key

Per phone (tenant-scoped) and per calendar, `IRateLimiter` reused unchanged from
`Ago.Platform.Abstractions`. The phone bucket is checked first: a caller who was never going to pass
their own bucket must not also spend a share of the coarser shared one finding that out. Both are
treated as correctness properties with tests against a real Redis, not as settings.

The bucket key holds `SHA-256(tenant_id:phone)`, never the number. A rate-limit bucket is a store and
its key space is readable by anyone who can run `KEYS`; hashing does not make it anonymous — the
input space is enumerable, and pseudonymised data is still personal data — which is why
`personal-data.md` lists the bucket and says so rather than claiming the problem away. What hashing
buys is real: the number is not readable by eye, and two tenants' buckets for one person are
unlinkable to a reader of the key space.

## Consequences

- **`IBookingStore` is this product's first multi-aggregate port**, arriving three items earlier than
  `ITenantRepository` predicted (it named `20-06`'s provisioning transaction). Same shape AGO Chat's
  `ISiteRegistrationRepository` settled on, for the same reason: a transaction spanning two writes
  has to belong to something a reader can see, and splitting it across two ports puts the boundary in
  a handler that cannot express it.
- **`BookEventHandler` returns its own outcome type, not `Result<T>`.** `Ago.Platform.Kernel.Error`
  is `(Code, Message)` with nowhere to carry structured failure metadata, and `api-design.md` promises
  a rate-limited caller a real `Retry-After` header. AGO Chat squeezed the retry-after into the
  message text and `Ago.Chat.Api.Http.ErrorExtensions` carries a comment apologising for the missing
  header. One non-standard return type is the cheaper of the two costs, and widening `Error` is a
  platform change this item deliberately did not make.
- **The booking endpoint returns `200`, not `201` with a `Location`.** It creates nothing — a slot and
  the booking that takes it are one row (`adr/0049`) — so there is no new URL, and a `Location`
  pointing at a `GET` this product does not serve would be a promise broken by the first client that
  followed it. A deliberate deviation from `api-design.md`'s POST rule, recorded rather than silently
  taken.
- **Redis becomes a dependency of AGO Calendar**, for the rate limiter alone. Never a source of truth:
  the claim reads nothing from it, per CLAUDE.md rule 8.
- **`AddRedisCaching` could not be used, and that is a finding about the platform.** The package's one
  extension method registers the cache, the rate limiter, the distributed lock *and*
  `CacheInvalidationPublisher`, which takes an `IEventPublisher`. AGO Calendar has no broker until
  `20-05`, so calling it makes the host fail service-provider validation in Development with
  *"Unable to resolve service for type 'Ago.Platform.Abstractions.IEventPublisher'"* — verified by
  doing it, not inferred. The package's units of composition are coarser than its units of use.
  Worked around in `Ago.Calendar.Infrastructure.Redis` with about fifteen lines duplicating the
  multiplexer factory and the pipeline construction the method keeps private. **No platform commit was
  made**; the finding is worth more than the fix, and the fix belongs to whoever owns the platform's
  next version.
- **The second consumer of `IRateLimiter` exists**, which is the thing `vision.md`'s platform claim is
  supposed to produce. The port, the `RedisRateLimiter` adapter, its Lua token bucket, the
  `ResiliencePolicyBuilder` and the `Resilience:Redis:*` options shape were all reused unchanged —
  only the convenience wiring was not reusable.
- **`ConfirmationWindow` is configuration with an unmeasured default** (fifteen minutes). Stated
  plainly, the same treatment `20-02`'s rolling horizon got. What it trades between is written down
  even though the trade has not been measured: too short and a shop that steps away auto-confirms a
  booking it would have rejected; too long and a customer told "confirmed" waits that long before
  anything is settled.

## Alternatives considered

- **Load the `Event`, call `Event.Claim`, save, and let `xmin` reject the loser.** The idiomatic
  option, and the one the codebase uses everywhere else. Rejected on the booking path for three
  reasons: a second round trip on every booking; a lost race arriving as an exception rather than as
  a number; and a domain method whose in-memory status check *looks* like the guarantee when it is
  not — `Event.Claim`'s own remarks already say so. It stays right for `20-04`'s operator-driven
  transitions, which are uncontended single-actor writes.
- **A pre-read of the slot's status, then the claim.** Rejected: a check-then-act, and every reason
  `6-09` exists applies to it verbatim. The handler reads the slot for the worker's identity and
  deliberately does not consult its status; the status lives only in the `WHERE` clause.
- **A `SELECT ... FOR UPDATE` on the event row, then an update.** Rejected: it holds a lock across two
  statements and a round trip for a decision one statement already makes atomically, and it turns a
  contended slot into a queue of waiters instead of a single winner and instant losers.
- **Read the customer, branch, then insert or update.** Rejected for the same race reason as
  everything else here: two first-time bookings from one number both find nothing and both insert.
  The unique index would catch it, but only as a violation somebody has to handle — an upsert has no
  check to hide.
- **Two ports, one for the claim and one for the customer, each in its own transaction.** Rejected:
  the ordering it produces (upsert, then claim) leaves a lead card behind on every lost race, which
  is personal data written for an action that did not happen.
- **Rate limiting in the endpoint rather than the handler.** Tempting, because the endpoint has the
  `RateLimitDecision` in hand and could write the header directly without a custom return type.
  Rejected: a limit enforced in the endpoint is a limit the next caller of the handler does not get,
  and `3-05`'s own precedent puts it in the handler with the tests to match.
- **A per-process in-memory limiter, to avoid taking a Redis dependency.** Rejected outright: two API
  replicas would each grant the full budget, so the limit would be a multiple of itself and would
  change silently whenever the deployment scaled.
- **Store the phone in the bucket key in clear**, as AGO Chat stores visitor ids in its own keys.
  Rejected: a visitor id is a synthetic identifier this system minted, and a phone number is the
  person. The keys are equally visible; the data is not equally sensitive.
