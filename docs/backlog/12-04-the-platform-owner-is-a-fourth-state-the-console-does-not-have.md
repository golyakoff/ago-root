# The platform owner is a fourth state the console does not have, and it offers to make them an operator

- **Stage**: 12
- **Status**: **built and tested (2026-08-26); one Done-when deliberately unticked.** The server-side
  refusal, the fourth destination and the banner all landed with tests, and the test that matters most
  was checked against the pre-fix code and does fail there. The live browser pass as the owner is not
  done and cannot be until this is deployed — it is listed unmet below rather than quietly ticked.
  "How it was closed" has the shape of the change.
- **Depends on**: nothing. `12-01`/`adr/0032` and `12-03` are what it corrects.

## What happens

The platform owner signs into `console.reserve-me.ru` and lands on **"Finish setting up your site"** —
`10-03`'s self-registration onboarding form, asking for a site display name and a widget embed origin.
Not `/owner`, which is the only thing that identity is for.

Found 2026-08-26, the first time anybody but the session that built it signed in as the platform
owner.

## Why, and why it is the same defect for the third time

`CallbackPage` tells three states apart, by the answer to `GET /api/v1/operators/me`:

- an existing operator → the queue;
- **a Keycloak identity with no `operators` row** → `403` → `/onboarding`;
- no token or an invalid one → the sign-in error.

**`adr/0032` gives the platform owner no `operators` row, deliberately** — no `OperatorId`, no
`site_id`, and `OperatorIdentityClaimsTransformation` resolves nothing for it. So the owner *is* the
second state by that test, and the console sends them where that state was built to go.

There is no fourth state, and nobody wrote one, because when `12-03` shipped the only person who had
ever signed in as the owner was the session that built it — already an operator on the same
deployment, so it never took this path.

**This is the third time "a Keycloak identity with no `operators` row" has been resolved by whatever
the surface happened to be built for.** `17-06` found the shared attachment route silently
classifying it **as a visitor**; the same audit found registration made such identities creatable by
anyone since `10-01`. Now the console classifies it **as a new registrant**. Three surfaces, three
different guesses, one ambiguity nobody owns.

That is the finding worth acting on, rather than the routing bug on its own.

## The trap

**Pressing "Finish setup" would make the platform owner an operator.** `10-02`'s bootstrap commits a
`Site`, its roles and an `Operator` row for that `sub`, in one transaction. The owner identity would
then hold a tenant, `operators/me` would start answering `200`, and the console would route them to a
queue forever after.

On the live deployment that is a state change nothing in the product can undo — there is no
"un-register" — so it would need hand-editing rows in production. **The form that does this is the
first thing the platform owner sees, with a button, and nothing on the page warns them.**

## Context to read first

`docs/adr/0032-*` and `docs/backlog/12-01-*` — why the owner has no `operators` row, which is not
being reversed here. `ago-console/src/pages/CallbackPage.tsx` — the three-state comment, which is
accurate and simply does not know about a fourth. `ago-console/src/auth/useOwnerEligibility.ts` — the
console already knows how to ask the server whether an identity is the owner; it just asks *after*
routing rather than as part of it. `docs/backlog/17-06-*` — the attachment-route instance of the same
ambiguity, and how it was closed there.

## Scope

- **A fourth state**, decided the way the third already is — by asking the server, never by
  inspecting the token client-side. `useOwnerEligibility`'s probe is the existing mechanism and the
  routing decision should use it rather than duplicate it.
- **The owner lands on `/owner`.** Reachable by URL today, which is the workaround, not the fix.
- **The onboarding form must refuse an identity that is the platform owner**, server-side. Hiding the
  form is not enough: `10-02`'s bootstrap endpoint is what actually commits the row, and a client-side
  gate is a suggestion. This is the half that turns a trap into a mistake somebody can survive.
- **Decide what the owner sees if they reach `/onboarding` anyway** — a bookmark, a back button, a
  second tab. Saying plainly why the form does not apply to them beats a blank page.
- **The console's demo banner should follow the identity, not the surface.** It currently tells the
  platform owner *"Its login is published on the demo pages, so anyone can sign in here"*, which is
  false of that login. `8-11` did exactly this for the widget's notice and its reasoning transfers.

## Out of scope

- **Giving the platform owner an `operators` row.** `adr/0032` argued that out and the argument
  stands; this item makes the console understand the decision, not reverse it.
- Anything about `12-02`'s API, which refuses and permits correctly — the `403` the console reads is
  the right answer to the question it asked, and the wrong question.
- The seeded demo operators and the shared login.

## Done when

- [x] The platform owner signing in lands on `/owner` without touching the address bar.
      `CallbackPage` asks `12-03`'s existing `GET /api/v1/owner/sites?limit=1` probe once
      `operators/me` has answered `403`, and routes an accepted caller to `/owner`.
- [x] `10-02`'s bootstrap endpoint refuses a platform-owner identity, proven by a test that fails if
      the check is removed — the client-side gate alone does not count.
      `AuthorizationPolicies.NotThePlatformOwner` on `POST /api/v1/sites`;
      `SiteRegistrationTests.RegisterSite_WithThePlatformOwnersToken_Is403AndWritesNothing`. With the
      policy removed the same test observes `201 Created` and a committed `operators` row — checked,
      not assumed.
      **Reversed by `12-05` the next day** (`adr/0063`'s amendment): the refusal made platform owner
      and operator exclusive at one endpoint, which is the opposite of what this item's own ADR
      concluded. Both the policy and this test are gone; the routing outcome above, which is what
      actually closed the defect, stands. `12-05`'s file has the full argument.
- [x] An operator and a new registrant are both unaffected, proven rather than assumed: all three
      existing states still route where they did. `CallbackPage.test.tsx` keeps its original six
      cases and adds an assertion that an operator's sign-in never asks the owner question at all.
- [x] The banner says nothing false to a platform owner. `demoNotice.test.tsx`, five cases, including
      that the two clauses which are true for every reader survive the owner variant.
- [ ] **Not done: verified in a browser on the live deployment, as the owner.** Two reasons, both
      structural rather than skipped work. The fix is not deployed — this change opens PRs and
      deploying is a separate, deliberate step (`redeploy.md`) — so a live check today could only
      re-observe the bug. And signing in as the owner needs that account's password, which the
      session doing this work has no business holding. **This is the one Done-when to re-run by hand
      after the redeploy**, and it is the one that found the defect in the first place.

## Open questions

**Whether the ambiguity should be closed centrally instead of per surface.** Three surfaces have now
each guessed what "a Keycloak identity with no `operators` row" means, and each guessed differently.
A single server-side answer — something like "what kind of principal is this token" — would make the
next surface impossible to get wrong, and would be a genuine platform-shaped question rather than a
product one. It is also the kind of abstraction `clean-architecture.md` warns about building from
three examples rather than from a need. Worth deciding deliberately; this item can be built either
way, and if it is built per-surface again, that choice should be recorded rather than defaulted into.

> **Answered: per surface, chosen — `adr/0063`.** Not on "three examples is not a need", which is
> true but would have been the lazy version of this answer. On the fact that **the central question
> is not well-posed**: a classifier must return one kind, and "platform owner" and "operator" are
> orthogonal, not alternatives. One identity can be both — the author's own account on the public
> deployment is, which is exactly why `12-03` shipped without anyone hitting this — so a
> single-valued answer would be wrong for one of the two surfaces asking it. What each surface is
> really choosing is a *precedence*, which belongs to the surface.
>
> What is centralised instead is narrower and real: the **recognition rule** has one implementation
> (`PlatformOwnerRealmRole.IsHeldBy`, shared by `RequirePlatformOwner`'s handler and the new
> registration refusal), and the **defect class** is named — all three bugs read the *absence* of one
> kind as the *presence* of another, and would have done so with a classifier available, because they
> never asked anything at all.

## How it was closed

- **`ago-chat`** — *(withdrawn by `12-05`; kept here as the record of what this item did.)*
  `AuthorizationPolicies.NotThePlatformOwner`, a second policy on
  `POST /api/v1/sites` beside the unchanged `RequireKeycloakIdentity`. Policy layer, matching
  `17-06`'s fix for the same ambiguity and `adr/0032`'s "recognising the owner is a property of the
  token, decided before any use case runs". A delegate rather than a named policy so it travels with
  the route and no host can map the endpoint without it. The reading of `realm_access.roles` moved out
  of `PlatformOwnerAuthorizationHandler` into `PlatformOwnerRealmRole` so both callers share one copy.
- **`ago-console`** — a fourth destination in `CallbackPage` (operator → queue, then owner → `/owner`,
  then registrant → `/onboarding`, in that precedence); `/onboarding` explains itself to an owner who
  arrives anyway and links to `/owner`; the `8-06` demo strip takes a `demoNoticeAudience` whose
  default is the stricter shared-login wording, narrowed only by the three callers holding the
  server's own answer.
- **Deliberately not done** — no `operators` row for the platform owner (`adr/0032` stands), no
  central principal classifier (`adr/0063`), and no change to `12-02`'s API.

**One thing the fix cannot cover, worth stating rather than leaving implied.** `/onboarding` renders
the form until the probe answers, not a spinner. An owner who bookmarks that page sees the form for a
moment before the explanation replaces it. That is the deliberate trade: gating the page on a probe
that exists for one person on the deployment would strand the *common* reader — a real
self-registering shop — on a spinner whenever the owner endpoint is slow. It is safe only because the
server refuses the submission independently, which is why that half is the one with the test.
