# 26-317 · [onboarding/calendar] masters (workers) have no designed way to come to exist

- **Stage**: 26
- **Status**: done — ADR-0192 (amends 0125). Merged (`df7f1369`) and deployed. A master is a
  resource-only name (no login); every tenant gets 2 by default (`max(WorkerQuota,2)`), more only via
  the existing platform-owner grant. No migration. Master self-onboarding: answered NO (no login).
- **Found**: 2026-09-30, onboarding the first real client. Masters for «Салон Топаз» were added **by the
  platform owner**; there is no thought-through path for how a master appears for a normal tenant.

## What is true today (confirmed)

A worker is created by `POST /console/workers` (`CreateWorker`), gated by `calendar:configure`. A tenant
admin (Алёна holds `calendar:configure`) **can** create workers from the Masters screen
(`CalendarWorkersPage`) — so there is no hard technical block; the gap is conceptual and one of
discoverability. The owner did it by habit/confusion, not because the admin couldn't.

The unanswered product question is **what a "master" is** in relation to the rest of the model, and how
one is meant to come into being during real onboarding:

- Is a master a **standalone calendar entity** (a name + schedule), created purely by the admin — the
  current shape?
- Or is a master **an operator** (a person who logs in), so adding a master = inviting a colleague
  ([[operator invites]]), and the two concepts should converge rather than sit side by side?
- Or **both** — some masters log in (operators), some are just bookable resources (no login)?
- Can a master **self-onboard** (accept an invite, fill their own profile/hours), so the admin isn't the
  sole data-entry point?

Today "operator" (a console/app user with permissions) and "worker/master" (a bookable calendar entity)
are separate, and nothing links them or guides a tenant from "I have staff" to "they are bookable".

## The decision (filed as the question)

Pick the relationship between **operator** and **master**, and the onboarding path that follows:
- keep them separate (masters are admin-managed resources), or
- converge (a master can be an invited operator who fills their own schedule), or
- support both, with a clear default.

Then design the flow so a tenant admin — not the platform owner — brings masters into the calendar,
ideally with the master able to do some of it themselves.

## Done when

- [ ] The operator↔master relationship is decided and recorded here (an ADR if it changes the model).
- [ ] A tenant admin has a clear, discoverable path to add masters without platform-owner involvement.
- [ ] The design says whether/how a master self-onboards.
- [ ] Feeds the wizard [[26-318-…]] and depends on the module being on [[26-316-…]].
