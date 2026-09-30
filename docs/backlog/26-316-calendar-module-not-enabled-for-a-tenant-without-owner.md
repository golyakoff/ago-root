# 26-316 · [onboarding] the calendar module is not enabled for a tenant without a platform-owner action

- **Stage**: 26
- **Status**: ready — not yet verified · **carries a product decision, filed as the question**
- **Found**: 2026-09-30, onboarding the first real client. The calendar did not turn on for «Салон
  Топаз» on its own — it was enabled by hand, acting **as the platform owner**. A normal tenant admin,
  signing up on their own, would have no calendar and no obvious way to get one.

## What is true today (confirmed against code)

Calendar availability to a tenant is a **module grant** (`23-01`/`23-45`): the console reads
`IEnabledModuleReadStore.GetForSiteAsync`, and a module is turned on for a site by a grant. The only
grant path a session used today is the platform-owner one (`SetUnconditionalModuleGrantAsOwner`,
`RequirePlatformOwner`). There is **no** auto-grant on sign-up and no self-serve enable — verified: the
auth/handshake reads enabled modules but nothing in the registration path grants the calendar module.

So "the calendar just works after signup" is not true today; it requires an owner to reach in.

## The decision (this is the question, not an answer)

When should a tenant have the calendar module?

- **(a) On by default for every tenant** — simplest onboarding; the calendar is part of the product.
  Cost: every tenant carries calendar UI/entitlement whether they want booking or not.
- **(b) On with a plan / entitlement** — calendar is a paid or plan-gated capability, granted
  automatically when the tenant is on the qualifying plan. Cost: ties into billing/entitlements
  ([[architecture/entitlements-and-subscriptions]]); needs the plan model to say so.
- **(c) Self-serve opt-in** — a tenant admin flips it on from settings (a one-click "enable booking").
  Cost: one more setup step, but discoverable and in the tenant's own hands.

Whichever is chosen, the outcome must be: **a tenant gets the calendar without a platform-owner having
to act.** The owner-grant path stays for exceptions, not as the normal route.

## Done when

- [ ] The author picks (a)/(b)/(c) (or another shape) — recorded here before build.
- [ ] A newly onboarded tenant reaches a usable calendar without any platform-owner action.
- [ ] The platform-owner grant remains available as an override, not the default path.
- [ ] Related onboarding items: [[26-315-…]] (slots), [[26-317-…]] (masters), [[26-318-…]] (wizard).
