# an invited operator has nowhere to enter the code

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-22` built the whole backend this needs; only the console half is
  missing.
- **Found**: 2026-09-05, while verifying `23-22`. Filed under CLAUDE.md rule 14.

## Goal

Somebody handed an invite code can join the site they were invited to, using the console, without
anybody running anything on their behalf.

## What is actually wrong today, verified

The backend is complete. `POST /api/v1/operator-invites/redeem` exists, takes a code, is gated on
`RequireKeycloakIdentity` rather than on an operator identity — deliberately, because the person
redeeming is not yet an operator — and `RedeemOperatorInviteHandler` behind it does the work.

`ago-console` contains **no screen, no route and no API call** for it. The only occurrence of the
word in its source is a comment in `SignupPage.tsx` about something else.

So the invite feature ends at a code the tenant can generate and nobody can use. The tenant's half of
`23-22` works and looks finished, which is what makes this worth a number rather than a note: the
screen that creates invites gives no sign that the other end is missing.

## Scope

- **A redemption screen**, reachable by somebody who has signed in but is not yet an operator on any
  site — which is the state an invited person is in, and is worth stating because the console's
  routing otherwise assumes an operator identity exists.
- The API client call, alongside the console's existing ones.
- **The outcomes a person can actually hit, each worded for them, not for an engineer**: the code is
  wrong, the code has already been used, the code has expired, and the happy path. The handler
  already distinguishes these; the screen must not collapse them into one "something went wrong".
- **Where they land afterwards.** A newly redeemed operator has an identity they did not have a
  moment ago, and the console's navigation is built from permissions — so the redirect has to happen
  after that state is refreshed, not before it.
- Every string through the translation files, in every locale the console ships.

## Out of scope

- **Any backend change.** If the redemption endpoint turns out to be wrong, that is a finding and its
  own item — this one is the missing half of a shipped feature, not a re-opening of it.
- **Emailing the invite.** How the code reaches the person is `10-05`'s territory and is in progress
  elsewhere; this item assumes the code arrived somehow.
- **The tenant-facing invite screen**, which `23-22` shipped.

## Done when

- [ ] A signed-in person who is not an operator anywhere can enter a code and become an operator on
      the inviting site.
- [ ] Each of the four outcomes shows a distinct message a shop assistant would understand.
- [ ] After a successful redemption the navigation reflects the permissions just granted, without a
      manual reload — the failure worth testing, because it is invisible to anyone who reloads out of
      habit.
- [ ] No untranslated literal: `ux-gate` passes.
