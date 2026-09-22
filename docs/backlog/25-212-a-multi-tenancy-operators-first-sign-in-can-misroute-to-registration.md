# 25-212 · A multi-tenancy operator's first sign-in can misroute to registration

- **Stage**: 25
- **Status**: done — merged as `ago-console#274`. Design decision for >1 tenancy: reuse
  `resolveActiveSite`'s existing stored-or-first-alphabetically resolution for the one probe call,
  not a blocking site-picker screen (unlike `26-12`'s Android router) — the console already answers
  "which tenancy" silently one layout level up and deleted its own dedicated `TenancySwitcher` screen.
- **Found**: 2026-09-22, while implementing `26-12` (`ago-android`)'s own post-authentication
  routing. That item found the identical defect shape server-side (`ResolveOperatorIdentityHandler`)
  and fixed it for the Android client; reading `ago-console`'s own `CallbackPage`/`PermissionsProvider`
  to confirm the fix generalised found the same bug still live in the console itself. Not reproduced
  against a real multi-tenancy identity (none exists in this deployment) - this is a reading of the
  source, confirmed against the real handler code, not a live reproduction.

## What is actually true today, confirmed against real code

`Ago.Chat.Application.UseCases.ResolveOperatorIdentity.ResolveOperatorIdentityHandler` (`13-07`/
`adr/0068`): when a Keycloak identity has **more than one eligible tenancy and no requested-site
signal**, it resolves to `null` - deliberately, since guessing which tenancy to use would be exactly
the cross-tenant misdirection that ADR forbids. No resolution means no `operator_id` claim, which
means `GET /api/v1/operators/me`'s `RequireOperatorIdentity` policy answers `403` for that identity -
**even though it is a real, working operator**, just one this call gave no way to disambiguate.

`ago-console/src/pages/CallbackPage.tsx` calls `resolveOperatorState(user.access_token)`
(`operatorsApi.ts`, itself calling `operators/me` via `withActiveSiteHeader`) as its own, independent
first check after a Keycloak redirect - **without ever setting the active-site signal first**.
`src/api/activeSite.ts`'s `setActiveSiteId` has exactly one caller in this codebase:
`PermissionsProvider.tsx`, which is mounted at the authenticated-app layout level (`App.tsx`) - **only
reached after `CallbackPage` has already routed somewhere**. `PermissionsProvider`'s own doc comment
states it does the correct tenancies-then-active-site-then-`operators/me` sequencing, and is right
that it does - but that sequencing runs *after* `CallbackPage`'s own routing decision, not before it,
so it protects nothing on this path.

**The consequence**: a multi-tenancy operator's first sign-in on a fresh session sends `operators/me`
with `activeSiteId` still `null` (module-level singleton, unset), draws the same `403` a platform
owner or an unregistered identity would, and falls into `CallbackPage`'s own `(b)`/`(d)`/`(c)`
disambiguation with no signal telling it this is actually case `(a)` in disguise - landing, per that
file's own documented decision tree, on `/onboarding` (site registration) unless the identity also
happens to hold the `platform-owner` realm role. This is `12-04`'s own defect - the platform owner
being sent to `/onboarding` - reproduced for a different identity by the same missing signal, and it
survived `13-07`'s own fix for the identical reason `12-04` itself survived `12-03`: the one identity
whose bug this is has never been the one testing it (the author's own account has always held either
zero or exactly one tenancy).

## Scope

- `CallbackPage.tsx`'s own routing decision needs the tenancy count **before** it calls
  `resolveOperatorState` - the identical reordering `26-12` (`ago-android`) already applied: call
  `GET /api/v1/me/tenancies` first (already gated by the weaker `RequireKeycloakIdentity`, so it
  answers for zero-or-several with no `operators` row needed), and:
  - **Zero tenancies**: proceed exactly as today - `operators/me`'s own `403` still correctly
    distinguishes `(b)`/`(d)` from nothing, since there is no ambiguity to resolve.
  - **Exactly one**: set the active-site signal from it before calling `operators/me` - the identical
    value `PermissionsProvider` would resolve to moments later, just available in time for this call
    too.
  - **More than one**: **this item's own real design decision, not assumed** - either (a) show the
    site picker before `operators/me` is ever called (deferring the operator/owner/registration
    question until a site is chosen), or (b) set a "just check any known-eligible site" signal for
    this one probe call only, since the question being asked is "does *some* operator row exist for
    this identity", not "which one is active" - state which was chosen and why. `26-12`'s own Android
    router picked the site-picker-first shape; check whether the console's own screen inventory and
    `navigation.md`'s Android-side precedent make the identical choice right here, or whether the
    console's different session model (a single long-lived SPA session vs. a mobile app's own
    lifecycle) argues for the other.
- Confirm the fix generalises: a platform owner who *also* holds two or more operator tenancies (the
  author's own account, per `PermissionsProvider`'s own remarks: "the author's own account has both")
  must still land in their queue, unaffected by whichever multi-tenancy resolution is chosen above.
- A regression test reproducing this exact defect shape: a fake multi-tenancy identity, asserted to
  reach the operator arm (or the site picker, per whichever design is chosen) rather than
  `/onboarding`.

## Out of scope

- Any change to `Ago.Chat.Api`'s own resolution algorithm (`ResolveOperatorIdentityHandler`) - that
  side is correct and unchanged; this item is entirely about the console's own client-side sequencing
  around it.
- `ago-android`'s own equivalent - already fixed, `26-12`.
- Any other console routing arm not touched by this ordering.

## Done when

- [x] A fake multi-tenancy identity reaches the operator path rather than `/onboarding`, proven by a
      new `CallbackPage.test.tsx` case asserting call order.
- [x] A platform owner who also holds two or more operator tenancies still reaches their queue,
      proven by a real test.
- [x] The single-tenancy and zero-tenancy paths are provably unchanged (existing cases stay green).
- [x] `npm run typecheck`/`lint`/`test` — 1685/1685 passing; `ux-gate` — 67 passed, 9 skipped, 0 failed.
