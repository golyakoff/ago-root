# Demo credentials minted on request, expiring in a day

- **Stage**: 8
- **Status**: ready — the shape is the author's decision (2026-08-25); one real fork remains, named
  below, and it is this item's own to decide
- **Depends on**: `10-02-site-and-operator-registration.md` (shipped) for the registration path this
  reuses. Deliberately **not** on `10-05` — see "Why this sidesteps email".

## Goal

Anyone who wants to try the operator console gets their own credentials on the spot, valid for about a
day, instead of everyone sharing one public account. After this, two people looking at the demo at the
same time are two different operators with their own queue and their own conversations, rather than two
windows onto the same inbox.

## Why the shared account has to go

It is not only untidy. One public operator means capacity, unread counts and the conversation queue are
shared state between strangers; it means anyone can send as that operator; and it means every visitor's
demo conversation is readable by every other viewer (`8-06` is the interim honesty about that). It also
produced a real diagnostic dead end: twelve connections on one operator looked like a leak until it
turned out to be one tab renewing its token (`5-16`), and with per-viewer accounts that ambiguity would
not have existed.

## Two properties worth noticing before designing it

**It reuses machinery that already exists, in both directions.** Creating a demo tenant is
`10-02`'s `RegisterSite` bootstrap — `Site` + two `Role`s + `Operator` + assignments in one
transaction — which is built and shipped. Expiring one is `16-02`'s account deletion, which is
scoped but not built. So this item is mostly wiring, and it gives `16-02` its first continuous
consumer: erasure that runs every day against real data is erasure that is known to work, rather than
a path exercised once by a test.

**Why this sidesteps email.** `10-05` exists because Keycloak's self-registration cannot complete
without a verification mail. A minted demo account has no such problem: the credentials are generated
and shown on screen, there is no address to verify and nobody to mail. So this can ship while `10-05`
is still open, and it is one of the few things in the current queue that can.

## Context to read first

`docs/backlog/10-02-site-and-operator-registration.md` — the bootstrap transaction, and its own note on
why `10-02` deliberately rejected an `Account` aggregate above `Site`. `docs/backlog/16-02-erasure-
account-and-conversation.md` — the deletion this needs, including the stores it must reach.
`docs/backlog/13-01-operator-invitations-and-seat-entitlement.md` — its statement that a Keycloak Admin
API credential is "a new class of secret this project has avoided holding", which is exactly the fork
below. `adr/0028` — why Keycloak's own hosted registration was chosen, and what minting a user
out-of-band means against that decision. `docs/architecture/caching.md`'s rate-limit machinery
(`3-05`) — an endpoint that creates tenants on request is a resource-creation endpoint facing the
internet.

## Scope

- An endpoint and a button — "try the console" — that mints an operator and returns credentials shown
  on screen. Rate-limited per IP with the existing limiter, and capped in total, because this creates
  rows on request.
- **Whether a minted operator gets a whole tenant of their own, or joins the shared demo site**, is the
  substance of the item and it decides how much it actually fixes. Its own tenant isolates conversation
  visibility as well as identity, but the public demo pages carry a fixed site key, so a per-viewer
  tenant needs the demo page to learn which site it is talking to. Joining the shared site is far less
  work and leaves visitors' conversations mutually visible — which is the main thing this is meant to
  fix. Decide, and say what the choice costs.
- An expiry — around a day — and a job that removes the account and everything under it when it
  passes. Same shape as `15-04`'s prunes; reuse `16-02`'s deletion rather than writing a second one.
- Everything minted is recognisably temporary: names, the on-screen credentials, and whatever the owner
  view (`12-03`) shows, so a demo tenant is never mistaken for a real customer.
- The existing seeded demo tenants stay. They are what `8-05` uses to show tenant isolation live, and
  they are not created on demand.

## The fork this item has to resolve

**How the Keycloak user is created.** Two answers, both real:

- **Keycloak Admin API from the API host.** Flexible, unbounded, and it means holding an admin
  credential the project has so far avoided — `13-01` named that cost deliberately. It also makes the
  same capability available later for `13-01`'s invitations, so the cost is not paid only for a demo.
- **A pre-seeded pool of accounts handed out in rotation.** No new secret, no admin API, no unbounded
  creation, and correspondingly capped: N concurrent viewers and a recycling policy instead of an
  expiry. Much smaller, and it does not generalise.

Pick one with the reasoning written down. If it is the first, the credential's handling belongs in
`17-03`'s inventory the day it exists.

## Out of scope

- Self-service signup for real customers — Stage 10. This is a demo affordance and must not become a
  second registration path with its own rules.
- Email of any kind (see above).
- Billing, tiers or entitlements for demo tenants — they are free by construction and short-lived.
- `8-06`'s notice, which is needed now and stays useful afterwards: the public demo pages remain shared
  even if every viewer gets their own console account.

## Done when

- [ ] A stranger can obtain working console credentials without the author doing anything.
- [ ] Two simultaneous viewers are two distinct operators, demonstrated with two browsers.
- [ ] A minted account and everything under it is gone after its window, proven by letting one expire
      rather than by reading the job.
- [ ] The creation endpoint is rate-limited and capped.
- [ ] The Keycloak-user decision is recorded, and any new credential is in `17-03`'s inventory.
- [ ] The seeded `8-05` tenants still exist and still demonstrate isolation.

## Open questions

None that block starting. The two decisions above are this item's own to make and record.
