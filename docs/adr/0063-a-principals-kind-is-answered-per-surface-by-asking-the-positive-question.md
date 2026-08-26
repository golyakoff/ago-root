# ADR-0063: A principal's kind is answered per surface, by asking the positive question

- **Status**: Accepted, and **amended on 2026-08-26** — one *consequence* of this ADR was reversed by
  `12-05` on the same day it was written: `POST /api/v1/sites` no longer refuses a platform-owner
  identity. The decision itself is unchanged and the reversal is an application of it, not an
  exception to it. The amendment immediately following says why.
- **Date**: 2026-08-26 (amended 2026-08-26)
- **Stage**: 12

## Amendment (2026-08-26): the registration refusal is withdrawn — `12-05`

`12-04` shipped two changes. One was routing: the console stopped sending a platform-owner identity
to `10-02`'s registration form. The other was a refusal: `AuthorizationPolicies.NotThePlatformOwner`,
a second policy on `POST /api/v1/sites`, answering that identity `403`.

**`12-05` removed the refusal and kept everything else.** The route is back to
`RequireAuthorization("RequireKeycloakIdentity")` alone, the policy method is deleted, and one
identity may now hold Keycloak's `platform-owner` realm role *and* an `operators` row of its own.

**Why it was wrong to be there — and this ADR is the argument against it.** The section below
rejects a central classifier chiefly because "platform owner" and "operator" are **orthogonal axes,
not alternatives**, and one identity is legitimately both. The refusal made them exclusive at exactly
one endpoint. It is the same claim, contradicted by its own item.

**What the danger actually was.** Not that the owner could have a tenant — that the owner was *shown
a form they never asked for*, whose one button converted them silently. That is a routing defect, and
routing is where `12-04` fixed it. Filling in a site display name and an embed origin and pressing
"Finish setup" is not something anybody does by accident, which is the difference between a trap and
an action. `10-03`'s form is the same deliberate act for every caller; nothing about this identity
makes it less deliberate.

**Why the endpoint is safe without it**, stated plainly so a later reader does not have to reconstruct
it:

- Registering is a **deliberate, multi-field, authenticated act**, not a redirect target. No caller
  reaches the transaction without typing two values and pressing a button.
- The **routing fix is what stands between an owner and that form**, and it is unchanged. `12-04`'s
  fourth state still sends the owner to `/owner`; `/onboarding` is reached only on purpose, and says
  what registering will do to *this* account before it is done.
- The refusal **protected nothing else**. It guarded one endpoint against one identity for one
  outcome — an `operators` row — that this item positively wants to be reachable.
- **`adr/0032` is untouched.** The platform-owner *role* still carries no tenant: it is a realm role,
  granted in Keycloak, readable from no table this codebase writes. What changed is that the *person*
  holding it may separately hold an ordinary operator seat. The role remains tenant-less; the human
  is allowed to be two things.
- **Nothing was silently depending on the owner having no tenant.** The one place it could have
  mattered is `12-02`'s cross-tenant read: giving the owner a tenant makes
  `OperatorIdentityClaimsTransformation` start resolving, so every request that identity makes now
  carries a `site_id`, `GET /api/v1/owner/sites` included. That read consults no claim, and a narrowed
  read would have failed *silently* — a shorter list of tenants looks exactly like a platform with
  fewer tenants. `PlatformOwnerAsTenantTests.AnIdentityHoldingBoth_StillSeesEveryTenant_NotOnlyItsOwn`
  establishes it with an identity that genuinely holds both, and was checked to turn red against a
  deliberately narrowed read before being relied on.

**The one guarantee genuinely given up.** The refusal was a server-side backstop; there is now no
server-side "are you sure" between a platform owner and a permanent `operators` row, only the form
itself. That is accepted, and it is the same protection every other caller has always had. Whether
`10-03`'s form should warn *every* caller that registering cannot be undone is left open — it is a
question about the form, true of all callers, and belongs with `10-03` rather than with the identity
this item is about.

**What survives verbatim**: the decision, the rule ("a surface may act on 'this principal is an X'
only when something authoritative said X"), the rejection of a central classifier, and every
alternative below. The one bullet this amendment rewrites is marked in *Consequences*.

## Context

Three surfaces have now had to answer "what kind of caller is holding this token", and each answered
differently. The token in question is always the same shape: a signature/audience/lifetime-valid
Keycloak token on `JwtSchemes.Operator` whose `sub` matches no `operators` row.

- **`17-06`** found `5-03`'s shared attachment routes branching on
  `ClaimsPrincipalExtensions.IsOperator()` and reading `false` as **"therefore a visitor"**. Since
  `10-01` opened the realm to public self-registration, such a token existed and was parsed as a
  `VisitorId` from Keycloak's own `sub` GUID. Nothing was reachable through it — every handler
  compares that id against the conversation's real visitor — so it was a mis-classification, not an
  access-control failure. Closed at the policy layer: the route now requires `kind` to hold one of
  two known values.
- **`10-03`/`12-03`** had `ago-console`'s OIDC callback read the same state as **"therefore a new
  registrant"** and route it to `10-02`'s self-registration form.
- **`12-01`/`adr/0032`** deliberately *creates* such a token: the platform owner is a Keycloak realm
  role and has no `operators` row on purpose.

`12-04` is where those collided. The platform owner signing into the live console landed on "Finish
setting up your site", and pressing the button would have committed a `Site`, its roles and an
`Operator` row for the owner's `sub` in one transaction — a state change with no un-register path,
undoable on the live deployment only by hand-editing production rows.

The obvious response is a central answer: one server-side "what kind of principal is this token",
computed once, consumed by every surface, making the next surface impossible to get wrong. It is a
genuinely platform-shaped question rather than a product one, which makes it more tempting still.
It is also, exactly, the abstraction `clean-architecture.md` warns about — built from three examples
rather than from a need.

This ADR exists because that choice deserved to be made rather than defaulted into, in either
direction.

## Decision

**No central principal classifier. Each surface keeps deciding for itself — but only by asking a
*positive* question, never by reading the absence of one kind as the presence of another.**

Two things make that a rule rather than a restatement of the status quo:

1. **The defect class is named, and it is not "no central classifier".** All three surfaces failed
   the same way: they inferred a positive identity from a negative answer. `IsOperator() == false`
   was read as "is a visitor"; `GET /api/v1/operators/me` answering `403` was read as "is a new
   registrant". Every one of those inferences would still have been written with a classifier
   available, because the code that made them never asked anything at all. The correction that
   generalises is: **a surface may act on "this principal is an X" only when something authoritative
   said X.** A missing claim is evidence of nothing.

2. **Server-side recognition of a *given* kind has exactly one implementation, shared.** `12-04`
   extracted `PlatformOwnerRealmRole.IsHeldBy` out of `PlatformOwnerAuthorizationHandler` precisely
   so the registration refusal reuses the same reading of `realm_access.roles` rather than a second
   copy of it. Likewise the console asks `12-02`'s endpoint (`probeOwnerEligibility`) rather than
   inspecting the token, so `12-01`'s `RequirePlatformOwner` remains the only thing that decides who
   the platform owner is. What is rejected here is a new *aggregating* abstraction, not the sharing
   of the rules that already exist.

**The decisive argument against the central classifier is that the question it answers is not
well-posed.** A classifier must return one kind. "Platform owner" and "operator" are not alternatives
— they are orthogonal axes, and one identity can be both: holding Keycloak's `platform-owner` realm
role says nothing about whether an `operators` row exists for the same `sub`. On this deployment the
author's own account holds both, which is exactly why `12-03` shipped without anyone noticing the
bug: the only person who had ever signed in as the owner was already an operator, so the owner path
was never taken. A single-valued classifier would have had to pick a winner for that account, and
whichever it picked would be wrong for one of the two surfaces asking. `12-04`'s console routing
instead states an explicit **precedence** — operator first, owner second, registrant last — which is
a routing decision belonging to that screen, not a fact about the token.

Two further reasons, weaker but real:

- **The surfaces cannot share a mechanism even if they shared an answer.** Two of the three are
  ASP.NET Core authorization policies inside `Ago.Chat.Api`; the third is a browser SPA in a separate
  repository that can only reach the server over HTTP. A classifier usable by all three would have to
  be both an in-process predicate and a published endpoint — two artifacts to keep in step, which is
  the drift the central answer was supposed to prevent.
- **A classifier does not remove the per-surface mapping, it adds a hop.** Each surface would still
  map its answer onto its own behaviour, and each mapping would still have a default branch. The
  wrong default is what caused all three bugs.

**Where this leaves `Ago.Platform.*`: nowhere.** Nothing here is generalised into the platform layer.
`clean-architecture.md`'s qualifying rules are not met — one product, three call sites, no second
consumer — and `adr/0032` already placed platform-owner recognition inside `Ago.Chat.Api`.

## Consequences

- **A fourth surface can still get this wrong**, and this ADR does not prevent it structurally. It
  states the rule and names the three prior instances so a reviewer has something to point at. That
  is a weaker guarantee than a type that cannot be misused, and it is accepted knowingly: the
  alternative's own guarantee was shown above to be unavailable at the shape the question actually
  has.
- **`authorization.md`'s actor table is the register of what a principal can be**, and stays the
  thing to read before writing a fourth branch. It now says so explicitly.
- ~~**The rule has teeth where it matters most.** `12-04` puts the platform-owner refusal on
  `POST /api/v1/sites` at the policy layer (`AuthorizationPolicies.NotThePlatformOwner`), the same
  layer `17-06` used, with a test that turns red if the check is removed. Client-side gates in
  `ago-console` are courtesy; neither is load-bearing.~~
  **Withdrawn by `12-05`** (the amendment at the top of this file). The refusal is gone; the
  endpoint's only gate is `RequireKeycloakIdentity` again. The half of that bullet which still holds
  is the last sentence: client-side gates in `ago-console` remain courtesy, never the rule. What
  replaced the refusal is not a weaker check but the absence of one — the act of registering is
  itself deliberate, and the routing fix is what keeps an owner from being led to it.
- **One duplication remains and is deliberate**: the console asks two endpoints in sequence
  (`/api/v1/operators/me`, then `/api/v1/owner/sites?limit=1`) to route one sign-in. That is one
  extra request per sign-in for the identity that has no operator row, and zero extra for everyone
  else, since the operator answer short-circuits. A "what am I" endpoint would collapse it into one
  request; it would also be the classifier this ADR declines to build, for a saving of one request on
  a once-per-session path.
- **If a fourth surface ever appears with a genuinely new need** — not a fourth guess at the same
  question — this decision should be revisited with that need as the argument, which is the
  qualifying condition `clean-architecture.md` asks for and which three examples do not supply.

## Alternatives considered

- **A `GET /api/v1/principal` endpoint returning `{"kind": ...}`.** Rejected on the orthogonality
  argument above: it has to return one value for an identity that is legitimately two things, and
  every consumer would need the precedence rule anyway. It would also be a new public contract on the
  API's own versioned surface (`api-design.md`) added for an internal tidiness gain.
- **A `PrincipalKind` value object in `Ago.Chat.Application`, resolved by a port.** Rejected. It puts
  a decision `adr/0032` deliberately keeps out of `Application` back into it: recognising the platform
  owner reads a Keycloak-signed claim and nothing from this system's data, so it is a token property
  decided before any use case runs. `Application` would have to be *handed* the answer by the
  transport edge and trust it, which is weaker than the policy layer deciding it and strictly harder
  to test.
- **A `kind` claim extended to a third value (`"platform-owner"`), set by
  `OperatorIdentityClaimsTransformation`.** Rejected, and it is the closest call. `kind` already
  exists (`17-06`) and a third value looks like a one-line change. But the transformation would have
  to read `realm_access.roles` to set it, making a *second* implementation of the owner check whose
  output is a claim other code then trusts — the exact drift risk this ADR's second clause forbids —
  and `adr/0032`'s "no grant this codebase can write can satisfy the owner check" property would be
  weakened by inserting a codebase-written claim into the path.
- **Refusing registration inside `RegisterSiteHandler`, via a `CallerIsPlatformOwner` flag on the
  command.** Rejected; see the `PrincipalKind` entry for the layering half. Operationally it would
  also spend a rate-limit token, six generated ids and a database round trip before refusing, where
  the policy refuses before the handler is constructed.
- **Leaving it per-surface without recording anything**, which is what would have happened by
  default. Rejected because `12-04`'s own Open questions asked for the opposite, and because "three
  surfaces guessed" is only a defensible outcome if the fourth reader can see it was a decision.
