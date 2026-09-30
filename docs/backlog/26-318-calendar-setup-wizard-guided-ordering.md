# 26-318 · [onboarding/calendar] a guided setup wizard — the prep ordering is opaque

- **Stage**: 26
- **Status**: needs design (opus)
- **Found**: 2026-09-30, onboarding the first real client. The order of calendar preparation is
  murky: you must create some combination of **calendar, master, service, working hours, worker
  schedule** and then **publish**, in the right order, and it is not discoverable which comes first.
  The author — who designed this — said he "barely worked it out"; a real user would be lost.

## What is true today

The pieces exist as separate screens under Записи/Календарь (`CalendarSetupPage`, Masters, Services,
Working hours, the readiness panel «Может ли клиент записаться прямо сейчас?»). The readiness panel
*names* the missing preconditions, which is good, but it is a checklist to interpret, not a path that
leads the user step by step. There is no first-run flow that says "do this, then this".

The implicit dependency order (from the readiness chain and the handlers):
1. a **calendar** exists and (eventually) is **published**;
2. an **active master** on it;
3. the master **offers a service**;
4. the master has **working hours** (or a cyclic schedule);
5. the master has a **saved worker schedule** (slot length, horizon…);
6. **slots are materialised** (see [[26-315-…]] — today this needs a kick);
7. **publish** so clients can book.

Nothing surfaces that order as a guided sequence.

## Proposal

A **wizard-style first-run flow** for a tenant setting up booking: one screen at a time, in dependency
order, each step gating the next, reusing the existing readiness preconditions as the wizard's own
steps (so the wizard and the readiness panel never disagree). It should:
- start the moment the calendar module is on ([[26-316-…]]) and no calendar is bookable yet;
- walk create-calendar → add-master ([[26-317-…]]) → add-service → set hours → confirm schedule →
  (materialise happens automatically per [[26-315-…]]) → publish;
- let the user leave and resume (the readiness panel remains the always-available map);
- end at a clearly bookable calendar with a shareable booking link.

This is the umbrella onboarding item; 26-315/26-316/26-317 are its prerequisites and can land first.

## Done when

- [ ] A design (opus) proposing the wizard's steps, states, and how it reuses the readiness chain —
      author-reviewed before build.
- [ ] A first-time tenant can reach a bookable calendar by following the flow, without prior knowledge
      of the required order.
- [ ] The wizard and the readiness panel share one source of truth for "what's missing".
