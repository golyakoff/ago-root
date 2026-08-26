# Demo credentials minted on request, expiring in a day

- **Stage**: 8
- **Status**: **partly done** (2026-08-26). The backend is built and proven; the button and the demo
  page's side are not. Both forks are resolved and recorded in `adr/0058`. See Done-when for exactly
  which boxes are ticked and why the others are not.
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

- [ ] A stranger can obtain working console credentials without the author doing anything. **Moved to `8-09`** - the endpoint does this and there is no button, so a stranger has a terminal, not a browser.
      *At the API: one unauthenticated `POST /api/v1/demo/credentials`, and the credentials it returns
      genuinely authenticate against the realm - `DemoTenantLifecycleTests.AMintedTenantsCredentialsActuallyLogIn`
      runs a real password grant against a real Keycloak, which is what the console's own login does.*
      **Left unticked deliberately.** The item says "a stranger", and a stranger has a browser, not a
      terminal. The mechanism is done and the affordance is not.
- [ ] Two simultaneous viewers are two distinct operators, demonstrated with two browsers. **Moved to
      `8-09`** - proven here as a property (two mints, two sites, two working logins), which is not the
      same claim as two people in two browsers.
      *`TwoMintsAreTwoTenantsWithNothingShared` asserts two mints produce two usernames, two site rows
      and two working logins - the property the two browsers would have been showing. **Left unticked
      deliberately**: the item asks for a demonstration with two browsers and there was none.*
- [x] A minted account and everything under it is gone after its window, proven by letting one expire
      rather than by reading the job.
      *`WhenTheWindowPasses_TheTenantAndEverythingUnderItIsGone`: a tenant is minted with a visitor, a
      conversation, a message and an attachment under it; the clock passes its window; one sweep runs;
      then every table is checked individually, the Keycloak user is checked with a different credential
      than the one that deleted it, and the credentials are checked to have stopped working.*
      **The deletion is narrow and `adr/0058` states exactly what it does not reach** - `outbox` rows,
      backups, node queues, traces, logs and Redis entries all survive. It is not `16-02`; it is the
      shape `16-02` can absorb.
- [x] The creation endpoint is rate-limited and capped.
      *Both, and the cap is a correctness property with a boundary test on each side
      (`MintDemoTenantHandlerTests`). Counted from the database inside the request, never cached.*
- [x] The Keycloak-user decision is recorded, and any new credential is in `17-03`'s inventory.
      *`adr/0058` Decision 2 - including the argument that the pre-seeded pool does not avoid the
      credential, which this item found and the item above did not anticipate.
      `KEYCLOAK_DEMO_PROVISIONER_SECRET` is in `17-03`.*
- [x] The seeded `8-05` tenants still exist and still demonstrate isolation.
      *They carry no `demo_expires_at`, so the sweeper cannot see them however old they get -
      `ASiteWithNoExpiryIsNeverSweptAwayHoweverOldItIs` moves the clock five years forward and checks.*

## Not done, and not claimed

- **The button.** `8-07`'s Scope says "an endpoint and a button"; this is the endpoint. Nothing in
  `ago-console` or `ago-landing` calls it, so Done-when #1 and #2 hold at the API and not in a browser.
- **The demo page's `?site=` handling.** The mint returns a `visitorUrl` carrying the new tenant's own
  public key, and the tenant allows that page's origin - but the page still boots the widget against
  its baked-in key. Until `ago-widget`'s two `public-demo*/index.html` pages read the parameter, a
  minted viewer has a console of their own that no visitor can reach. `adr/0058` Decision 1 states this
  plainly, because it is the cost of choosing a per-viewer tenant and it is not yet paid.
- **A live MinIO in the expiry test**, and **cache invalidation on deletion** (`16-02` requires it).
- **Any deployment.** Nothing here has run against a cluster, local or public.

## Open questions

None that block starting. The two decisions above are this item's own to make and record.
