# ADR-0163: A tenant can relax the verified-phone guarantee, until a gateway exists

- **Status**: Accepted
- **Date**: 2026-09-09
- **Stage**: 25

## Context

`adr/0082`/`20-09` established that a chat-driven booking requires a verified phone before a slot is
held — a booking is a real-world commitment against a worker's calendar, and a self-reported string is
not proof of anything. That guarantee assumed `14-15`'s verification mechanism would have a live
SMS/voice gateway account behind it. It does not: `14-15` shipped against
`UnconfiguredPhoneVerificationSender`, and the vendor decision is recorded as "undecided, needs a cost
quote" with no date attached.

The consequence surfaced live, testing the calendar end to end on 2026-09-09: every chat-driven booking
attempt reached the verified-phone step and stopped there, because no code can ever be delivered to a
real phone in this environment. `RequiresVerifiedPhone: true` was not protecting anything at that
point — it was making the entire booking flow uncompletable, for every tenant, unconditionally.

## Decision

A tenant can turn on a per-site, off-by-default setting (`WidgetConfig.AcceptUnverifiedPhone`) that
lets a chat-driven booking complete with a self-reported, unverified phone number. With it on and a
phone already known from earlier in the conversation, the flow skips the phone step entirely and books
directly. With it on and no phone known yet, the phone step still renders, but without demanding proof
of control over the number. With it off — the default for every tenant — nothing changes.

The booking record's own `PhoneVerifiedAt` is left `null` on this path, never fabricated as if it were
verified. `RequiresVerifiedPhone` on `BookEvent` becomes `!acceptUnverifiedPhone` rather than a
hardcoded `true`, computed fresh on every reply from the tenant's current setting — not persisted or
cached anywhere a race could stale it.

## Consequences

**Positive**: a real tenant can take real bookings today, without waiting on an unresourced vendor
decision. The relaxation is legible — a console label states plainly that it exists because phone
verification has no live provider yet, and that it is temporary, not a feature to keep. Every consumer
of `phone_verified_at` (the operator console, any future no-show logic) can still tell a verified
booking from an unverified one, because the field is never lied about.

**Negative**: this is a real, deliberate weakening of `20-09`'s own guarantee, opt-in per tenant. A
tenant who turns it on accepts a no-show/fraud risk `20-09` existed to close, in exchange for a
functioning booking flow. It also creates two live code paths through `HandlePhoneProvidedAsync`
(genuine reply vs. direct-call skip) that must be kept in sync by hand rather than by a single call
site. `20-10`'s public booking widget is deliberately **not** covered by this setting — it has its own,
already-working phone-verification mechanism and never had `14-15`'s missing-vendor problem — so the
two booking surfaces now differ in what "verified" requires, which a future reader must not assume is
symmetric.

## Alternatives considered

**Do nothing, wait for `14-15`'s vendor decision.** Rejected as the default: no date is attached to
that decision, and it blocks every real booking, on every tenant, indefinitely in the meantime.

**Silently mark an unverified phone as verified to satisfy the existing check.** Rejected outright —
this would corrupt the one signal `14-15`/`20-09` exist to produce, for every future consumer of
`phone_verified_at`, permanently, not just for the tenants who asked for the relaxation.

**A global flag rather than a per-tenant setting.** Rejected: a tenant who already has a way to reach
their own customers by other means, or who is comfortable with the risk, should not have that decision
made for them by every other tenant's absence of a gateway. Per-tenant, off by default, keeps the
guarantee the norm and the relaxation a deliberate, visible exception.
