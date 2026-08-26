# The platform owner is a fourth state the console does not have, and it offers to make them an operator

- **Stage**: 12
- **Status**: ready — and it is a live trap, not only an inconvenience
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

- [ ] The platform owner signing in lands on `/owner` without touching the address bar.
- [ ] `10-02`'s bootstrap endpoint refuses a platform-owner identity, proven by a test that fails if
      the check is removed — the client-side gate alone does not count.
- [ ] An operator and a new registrant are both unaffected, proven rather than assumed: all three
      existing states still route where they did.
- [ ] The banner says nothing false to a platform owner.
- [ ] Verified in a browser on the live deployment, as the owner, because that is the only way this
      was found in the first place.

## Open questions

**Whether the ambiguity should be closed centrally instead of per surface.** Three surfaces have now
each guessed what "a Keycloak identity with no `operators` row" means, and each guessed differently.
A single server-side answer — something like "what kind of principal is this token" — would make the
next surface impossible to get wrong, and would be a genuine platform-shaped question rather than a
product one. It is also the kind of abstraction `clean-architecture.md` warns about building from
three examples rather than from a need. Worth deciding deliberately; this item can be built either
way, and if it is built per-surface again, that choice should be recorded rather than defaulted into.
