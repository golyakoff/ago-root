# The platform owner may also be a tenant, and the console shows both

- **Stage**: 12
- **Status**: done
- **Depends on**: `12-04` — merged and deployed. This relaxes one thing that item did, and keeps the
  rest.

## Goal

One person can be the platform owner **and** run a tenant of their own, sign in once, and see both —
the operator queue and the owner view — as two entries in the same navigation.

## Why this exists a day after `12-04`

`12-04` found the platform owner being routed to `10-03`'s registration form, whose button would have
bootstrapped that identity into a tenant it could never leave. It fixed the routing **and** added
`AuthorizationPolicies.NotThePlatformOwner` to `POST /api/v1/sites`, refusing the bootstrap outright.

**The refusal is one notch stricter than the problem required, and the author said so** (2026-08-26).
The trap was never *that the owner can have a tenant* — it was that the owner was **shown a form they
never asked for**, with a button that converted them silently. Routing fixed that. Filling in a site
name and an embed origin is not something anybody does by accident.

`adr/0063`, written by `12-04` itself, is the argument for this item: platform owner and operator are
**orthogonal axes, not alternatives**, and one identity is legitimately both. The refusal contradicts
its own ADR — it makes the axes exclusive at exactly one endpoint.

**And "be your own customer" is worth having.** It is the cheapest possible dogfooding: the person who
decides what the product should do uses it the way a customer does, on the same deployment.

## The one thing that must be checked before relaxing anything

Today the platform owner's token carries **no** `OperatorId` and **no** `site_id`, because
`OperatorIdentityClaimsTransformation` resolves nothing for an identity with no `operators` row.

Give that identity a tenant and the transformation starts resolving — so **every** request it makes,
including `GET /api/v1/owner/sites`, arrives carrying a `site_id`.

`12-02`'s endpoint is gated on the realm role and does not consult `site_id`, so it should be
unaffected. **Should be is not good enough here**, because the failure mode is silent: an owner whose
cross-tenant read got narrowed to their own tenant sees a shorter list, not an error, and a shorter
list of tenants looks exactly like a platform with fewer tenants.

**Establish it by test, not by reading**: the owner view, requested by an identity that holds both,
returns every tenant — including ones it has no `operators` row in.

## Scope

- **Remove `NotThePlatformOwner` from `POST /api/v1/sites`**, and record the reversal in `adr/0063`
  rather than quietly deleting the policy — the reasoning that put it there is worth keeping as the
  history of why the endpoint is safe *now*.
- **Keep everything else `12-04` shipped.** The fourth routing state, `/onboarding`'s explanation, the
  banner's audience: all of it stays. This item changes one refusal, not the analysis.
- **The navigation shows both entries when both apply**, which `12-03`'s existing probe already
  supports — verify rather than assume, since nobody has held both.
- **A test that an identity holding both sees every tenant in the owner view**, per the section above.
- **Decide what `/onboarding` says to an owner now.** `12-04` made it explain that the form does not
  apply. It does apply now — but it should still not be where an owner *lands*. Probably: land on
  `/owner`, and if they navigate to the form deliberately, let them use it.
  **Decided, as suggested.** `CallbackPage` is untouched, so `/owner` is still where an owner lands.
  `/onboarding` now renders the same form everybody else gets, with `12-04`'s owner block kept above
  it and rewritten: it names the account, says that registering additionally makes it an operator of
  a new site of its own, that this cannot be undone, and links to `/owner` for a reader who arrived
  by a stale bookmark. An explanation beside a usable form, rather than a refusal in place of one.

## Out of scope

- Giving the platform owner an `operators` row **automatically**. Nothing should create one for them;
  this item only stops refusing when they ask.
- `adr/0032`'s decision that the platform-owner role carries no tenant of its own. That stays true —
  the role does not; the *person* may separately hold one.
- Any change to `12-02`'s API beyond proving it is unaffected.

## Done when

- [x] The platform owner can register a site through the ordinary flow, and afterwards holds both an
      `operators` row and the `platform-owner` role.
      *`PlatformOwnerAsTenantTests.ThePlatformOwner_MayRegisterASite_ThroughTheOrdinaryEndpoint` — a
      real Keycloak user granted the realm role over the admin API, `201` from the real
      `POST /api/v1/sites` mapping, the `operators` row read back out of Postgres, and
      `RequirePlatformOwner` still accepting the same identity afterwards.*
- [x] Signing in as that identity lands on the operator queue, with the owner view one click away —
      both entries visible.
      *`permissionGating.test.tsx`, "offers the tenant's own sections and the platform-owner one
      together, to an identity holding both": the whole navigation list asserted, not a containment
      check, so one entry suppressing the other fails. The routing half (operator first) is
      `CallbackPage`'s unchanged precedence, already covered by `CallbackPage.test.tsx`.*
      **Not verified in a browser** — doing so needs a signed-in owner on a running deployment and a
      real site registration on it, which this item was told not to perform.
- [x] The owner view returns **every** tenant for an identity that holds both, proven by a test that
      fails if the read is narrowed by the token's `site_id`.
      *`PlatformOwnerAsTenantTests.AnIdentityHoldingBoth_StillSeesEveryTenant_NotOnlyItsOwn`. The
      identity's own `site_id` is read back through a probe route first, so the test cannot pass for
      the uninteresting reason that nothing resolved; the assertion is that a tenant it has **no**
      `operators` row in is on some page of the result. Confirmed to turn red against a deliberately
      narrowed read before being relied on.*
- [x] `adr/0063` records the reversal and why the endpoint is safe without the refusal.
      *Amendment at the top of the file, plus the one reversed *Consequences* bullet struck through
      in place rather than deleted.*
- [x] `12-04`'s other four outcomes still hold — the three original routing states, and the banner.
      *No change to `CallbackPage`'s logic, `resolveOperatorState`, `useOwnerEligibility` or
      `demoNoticeAudience`; `CallbackPage.test.tsx` and `demoNotice.test.tsx` unchanged and green.*

## Open questions

**Whether anything should warn on the way in.** ~~The refusal was blunt but it was also a stop
sign.~~ **Answered: it belongs to `10-03`, and was deliberately not done here.**

The sentence the question describes — "this will make you an operator of a new tenant, which cannot
be undone" — is, in the question's own words, *true for every caller, not just this one*. That makes
it a property of `10-03`'s registration form and of the fact that this product has no un-register
path, not a property of the platform owner. Adding it under this item would file a general
irreversibility warning in the changelog of the one identity it is least needed for: the platform
owner is the one caller who already gets a paragraph naming the consequence (`OnboardingPage`'s
owner block, kept from `12-04` and rewritten by this item), and the one caller who could undo it by
hand if they had to, since they operate the deployment.

What this item did instead: the owner-specific explanation stays and now says what registering will
do rather than that the server will refuse it. The general warning — and the larger question behind
it, whether "delete my site" should exist at all — is left to `10-03`.
