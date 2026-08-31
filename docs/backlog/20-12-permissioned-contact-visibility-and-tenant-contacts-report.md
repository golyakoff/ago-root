# Permissioned contact visibility in the pending queue, and a tenant contacts report

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-04-confirmation-sweep-and-operator-queue.md` (done) — the pending-bookings queue
  this item adds a field and a permission gate to. `20-09-booking-confirmation-requires-a-verified-phone.md`
  (built, chat-only) — a cheaper, faster stopgap for exactly the risk `20-09`/`20-10` solve by full
  verification; see "Why this, and why now" below for how the two relate.

## Why this, and why now

Raised in the same launch-readiness conversation as `20-09`/`20-10`/`20-11`, as a deliberately smaller,
faster first step rather than a competing design. The author's own framing: a phone number that reaches
the system *unconfirmed* is still most of the value — a genuine visitor is motivated to type it
correctly, and an operator who can actually *see* it in the first few minutes after a booking lands can
catch an obviously fake one (`12345`, a repeated digit, the wrong length) by eye and cancel it before it
auto-confirms, without any SMS/voice mechanism existing yet. Full verification (`20-09`/`20-10`) closes
the gap this cannot — a visitor who is willing to type a *real-looking* but not-theirs number, or a
script attacking the endpoint automatically — but costs a real gateway account and, for the widget, a
real design decision not yet made. This item can ship today, with what already exists, and `20-09`'s own
verification gets built *into* this same review moment later, not as a replacement for it: named as the
explicit intended relationship, not two unrelated features.

## What already exists, checked before scoping the rest

`20-04`'s own two-step booking mechanic (claim → `PendingConfirmation` with a `ConfirmationDeadline` →
operator veto or an automatic sweep to `Booked`) is fully built and tested, including a real reject
endpoint (`RejectBookingHandler`, `POST /bookings/{bookingId}/reject`, gated on
`Permission.BookingReject`) and a console screen (`ago-calendar-console`'s `QueuePage.tsx`) rendering the
shared, unassigned queue every operator sees. None of that needs rebuilding.

What is missing, confirmed by reading the real code rather than assumed:

- **`PendingBookingRow`/`PendingBookingResponse` carry no phone number at all** — not gated, simply
  absent. The read model's own doc comment states the omission was deliberate ("a list does not need
  [a phone], and a read model that joined them would put personal data into every row of a screen an
  operator leaves open all day") — a real, considered decision `20-04` made for a different reason
  (screen-level PII minimization) that this item now has to weigh against a new want (operator judgment)
  rather than simply reverse.
- **`Reject` does not reopen the slot.** `Event.Reject` transitions `PendingConfirmation → Cancelled`,
  permanent — the slot never becomes `Available` again for a different visitor. Worth naming, not
  necessarily worth fixing in this item (see Out of scope).
- **`Permission.CustomerRead` already exists** (`Ago.Calendar.Domain/Permission.cs`) but is not yet
  wired to anything in the queue, and **exactly one role exists today** (`Role.cs` seeds a single
  `"Operator"` role holding all seven permissions, including `CustomerRead`) — so granting `CustomerRead`
  to one operator and withholding it from another is not possible in the current system at all. This
  item's own permission gate is meaningless until Calendar's role system can express more than one role,
  which makes that a real, in-scope dependency, not a detail.
- **No owner-bypass mechanism exists in Calendar.** Chat's own closest-sounding precedent (`14-12`'s
  "site owner's unconditional unlink") resolves, on inspection, to AGO's own *platform* owner
  (`adr/0032`'s cross-tenant staff role) — not a tenant's own account owner, and not reusable here.
  "The tenant can always see everything" needs its own mechanism, decided below.
- **No existing report screen lists customer PII.** `18-08` (Chat's own operator-analytics report) is
  the closest shape precedent (a Dapper read store, a plain console table, gated by an existing
  permission, tenant isolation proven by a dedicated test) but aggregates counts, never lists raw
  personal data — this item's own contacts report is a new kind of screen for both products, not a
  copy of an existing one.

## Decided: two permission tiers, not a bypass

**Extend Calendar's role system to support more than the single seeded `"Operator"` role** — the
concrete, structural gap named above. The shape: a tenant can grant `Permission.CustomerRead`
per-operator (through whatever role-assignment mechanism this item builds — a second seeded role, or a
per-operator permission override; decide and record which when implemented, the same "state the real
mechanism, don't guess" discipline this backlog already holds itself to elsewhere). The tenant's own
account-owner identity — itself a real, open question named below — always holds `CustomerRead` by
construction, not through a bypass path parallel to the permission system (`adr/0032`'s own platform-
owner shape is deliberately not reused here, since that concept is cross-tenant AGO staff, not a
tenant's own admin).

## Scope

- **The role-granularity gap**: Calendar's role system gains the ability to express at least two
  distinct operator roles (or an equivalent per-operator override), so `CustomerRead` can genuinely be
  granted to one operator and withheld from another — proven by a test that an operator without it
  cannot read a customer's phone even though one with it, on the same tenant, can.
- **The pending queue's own read model gains the phone field**, returned only when the requesting
  operator holds `Permission.CustomerRead` — checked per-request (the queue is shared/unassigned, so
  this cannot be a static per-row property) — proven by a test that the same queue request returns the
  field for one caller and omits it for another, on the identical underlying data.
- **The console's `QueuePage.tsx`** renders the phone when the API returns it, and an honest
  placeholder ("hidden — you don't have contact-visibility permission" or equivalent, decided at
  implementation) when it does not — never a blank cell indistinguishable from "no phone recorded at
  all."
- **A tenant contacts report**: a new screen/endpoint listing every customer (phone, display name, notes,
  first/last-seen, no-show count) for the tenant's own operators who hold `CustomerRead` — reusing
  `18-08`'s own shape precedent (Dapper read store, plain table, permission-gated, tenant-isolation
  test) as the closest structural model, adapted for a full PII listing rather than aggregate counts.
- **Who counts as "the tenant" for the always-granted case**: decide explicitly — the simplest, most
  honest answer given no owner concept exists in Calendar today is that this item **also** has to
  establish what "tenant owner" means operationally (the first operator ever created for a tenant, a new
  explicit flag, reuse of whatever Chat's own owner concept resolves to for a shared account — `13-07`'s
  "one login, several tenancies" may be relevant context) — record the actual choice here, don't leave it
  implicit.

## Out of scope

- Making `Reject` reopen the slot to `Available` — a real, named gap, but a different, separable change
  from contact visibility; a future item if the author wants it.
- `20-09`/`20-10`'s own full verification mechanisms — this item is explicitly the cheaper interim step,
  not a replacement; both remain their own items, to be built later and layered on top of this one's own
  review moment, per "Why this, and why now" above.
- `NoShowCount`'s own "has no writer, always zero in v1" gap (`20-04`'s own retro note) — surfaced in the
  contacts report as a real field, but fixing why it never increments is a separate item if it matters.

## Done when

- [ ] An operator holding `Permission.CustomerRead` sees a pending booking's phone number in the queue;
      one without it does not, on the identical underlying booking — proven by a test.
- [ ] The role-granularity gap is closed: a tenant can actually grant `CustomerRead` to one operator and
      withhold it from another, proven by a test using two real operators with different roles.
- [ ] The tenant's own account-owner concept (whatever this item decides it means, per Scope above)
      always sees contact data regardless of role, proven by a test.
- [ ] A tenant contacts report exists, listing every customer's contact/personal data for an operator
      holding `CustomerRead`, tenant-isolated, proven by a test.
- [ ] The console renders both the gated queue field and the new report screen, with an honest
      "hidden, not absent" treatment when the field is withheld.

## Open questions

- Exact mechanism for "who is the tenant owner" — named as a real, in-scope decision above, not
  resolved here; the answer likely has to reconcile with however account/tenant identity already works
  elsewhere in this deployment (`13-07`), rather than inventing a Calendar-only concept that could
  disagree with it.
- Whether the second role this item introduces should be named something specific (`Admin`, `Manager`)
  or left as a bare permission grant with no named role at all — a naming/UX question, not a structural
  one, left for implementation.
