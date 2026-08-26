# ADR-0058: Demo credentials are minted per viewer, with a tenant of their own

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 8 (`backlog/8-07-ephemeral-demo-tenants.md`), with consequences for 13, 16 and 17

## Context

The public demo has one operator account, shared by everyone who looks at it. `8-06` is the interim
honesty about what that means; this is the fix. The shared account makes capacity, unread counts and
the conversation queue shared state between strangers, lets anyone send as that operator, and — the
part that actually matters — makes **every visitor's demo conversation readable by every other
viewer**.

`8-07` names two forks and leaves both to this item. Building it settled a third the item did not
anticipate, and produced two findings about somebody else's software that changed the design after it
was written.

**One dependency the item asserts and does not have.** `8-07` says expiry should "reuse `16-02`'s
deletion rather than writing a second one". `16-02` is `ready` and **not built** — it is scoped only.
So there was nothing to call, and the item's Done-when #3 ("a minted account and everything under it
is gone after its window, proven by letting one expire") had no mechanism behind it.

## Decision

### 1. A minted viewer gets a whole tenant of their own, not a seat on the shared demo site

Its own `Site`, its own two roles, its own `Operator`. Produced by `10-02`'s existing bootstrap
transaction (`ISiteRegistrationRepository.TryRegisterAsync`), so a demo tenant is structurally an
ordinary tenant and differs by exactly one column, `sites.demo_expires_at`.

Joining the shared site was the far smaller change and it was rejected on what it fixes. It would
give each viewer their own identity — their own queue position, their own capacity, no more sending as
somebody else — and would leave every viewer able to read every other viewer's conversations, which
`8-07` calls "the main thing this is meant to fix". Buying the cheap half of a fix and calling the item
done would have been the worse outcome.

**What the choice costs, and it is not nothing.** The public demo pages carry a fixed site key, so a
per-viewer tenant is only reachable if the page can be pointed at it. The API therefore returns a
`visitorUrl` carrying the new tenant's own public key (`https://<demo-page>/?site=<publicKey>`), and
the tenant is minted with that page's origin in its `allowed_origins` so `5-01`'s layer 2 will let the
widget connect. **The demo page's side of that — reading `?site=` and booting the widget against it —
is not built** (see Consequences). Until it is, a minted viewer has a console of their own and no
visitor can reach it, which is a worse demo than the shared account. That is the honest state, and it
is why the `visitorUrl` exists in the response before anything consumes it.

**So the feature ships disabled everywhere, including the demo overlay** (decided at merge,
2026-08-26). `DemoTenant__Enabled` is present in `overlays/demo` and set to `false`, rather than
omitted, so that turning it on later is a one-word diff in a file that already carries the reasoning.
Enabling it before the page half exists would publish an unauthenticated tenant-creating endpoint on
the public internet that nothing can usefully call — all of the exposure, none of the feature — and
the cap and the rate limit bound that exposure without giving any reason to accept it. `8-09` owns
the page, the button, and flipping this flag as its last step.

The query parameter belongs to the **demo page**, never to the widget. A widget that read `?site=`
from its host page's URL would let anyone repoint any customer's widget at another tenant by crafting
a link.

### 2. The Keycloak user is created through the Admin API, by a service-account client scoped to `manage-users`

`13-01` named the cost: an admin credential is "a new class of secret this project has avoided
holding". This item pays it, for a reason the pre-seeded-pool alternative turns out not to avoid.

**The pool does not actually deliver the property.** A pool of N accounts handed out in rotation needs
no new secret only if the passwords stay fixed. If they do, the previous holder of a recycled account
can log back in and see the *next* viewer's tenant — strictly worse than the shared account, because it
looks isolated and is not. Rotating the password on recycle requires the Admin API, at which point the
pool's only advantage is gone and what remains is a capped, non-generalising version of the same thing.
That is the argument that decided this, and it is not in `8-07`: the item presents the pool as "no new
secret, and correspondingly capped", which is true only of a pool that leaks.

The credential is narrowed in two ways that are properties of the realm rather than of the code: the
service account holds exactly one role, `realm-management:manage-users` on the `ago-chat` realm, and it
is a **realm** client, not the `master` realm admin that `apply-realm-settings.sh` uses from the node.
It cannot read the realm's configuration and cannot touch another realm. It is in `17-03`'s inventory.

A third option — the API minting its own operator token and bypassing Keycloak entirely — was rejected
without much thought and is recorded so nobody re-proposes it: `adr/0022` chose Keycloak as the
operator identity provider, and a second operator-auth path existing only for demos would make every
statement about operator authentication conditional.

### 3. Expiry deletes the tenant subtree, and this item builds that deletion rather than waiting for `16-02`

`DemoTenantExpiryJob` (`Ago.Chat.Worker`), a bounded-batch `PeriodicTimer` sweep in the same shape as
`AttachmentOrphanSweepJob` and `15-04`'s prunes. Per expired tenant, in this order:

1. **Object store first** — every `object_key` and `thumbnail_key` belonging to the site. After the
   rows are gone nothing can name the bytes, and `personal-data.md` already records exactly that gap
   for conversation deletion. This is the one place in the codebase that does not have it.
2. **Postgres second** — `DELETE FROM sites WHERE id = @id`, one statement. What it reaches is a
   property of the schema, not of the method: every table holding a tenant's data has a foreign key to
   `sites` with `ON DELETE CASCADE`. A hand-ordered list of deletes would be a second, weaker copy of
   the schema that silently stops being complete the first time somebody adds a table.
3. **Keycloak last** — the most likely step to fail and the least harmful to leave undone for a cycle.
   A user whose site is gone can log in and reach nothing. And the sweeper still finds the tenant next
   cycle, because it works from `sites`.

**What the deletion does not reach**, because a deletion that quietly misses something is worse than
one that says what it misses:

| Store | Reached? |
|---|---|
| `sites`, `visitors`, `conversations`, `messages`, `attachments` rows, `operators`, `roles`, `operator_roles`, `channel_identities`, `webhook_endpoints`, `webhook_deliveries` | **Yes** — asserted table by table in `DemoTenantLifecycleTests`, not assumed from the cascade |
| MinIO objects and thumbnails | **Yes** in code; proven against a recording double, **not** against a live MinIO (see Consequences) |
| The Keycloak user | **Yes** — asserted against a real Keycloak, including that the credentials stop working |
| `outbox` rows | **No.** Body-free by contract, but they carry this site's ids. `16-02` owns this |
| Backups | **No**, until `15-02`'s retention window ages them out — the answer `16-02` already states |
| RabbitMQ node queues, Jaeger traces, container logs | **No.** `16-01`/`adr/0057` own these |
| Redis cache entries derived from the site | **No.** They expire on their own; `16-02`'s Done-when requires invalidation rather than expiry, and this item does not do it |

This is a **narrow** erasure, shaped so `16-02` generalises it rather than replacing it: same job shape,
same bounded batch, same ordering, one scope. `8-07` predicted this would give `16-02` "its first
continuous consumer"; it does, for the stores in the first three rows only.

### 4. Both guards, and the cap is a correctness property

Per-IP rate limit through the existing limiter (`3-05`) **and** a total cap on live demo tenants. They
defend different things: a limiter bounds one caller's rate, and a thousand callers each politely
minting one tenant passes every rate limit ever written. The cap is counted from the database inside
the request that acts on it, never cached (CLAUDE.md rule 8 — a cached count is a cap that can be
exceeded by exactly the traffic it exists to stop), and it has a boundary test on both sides.

The endpoint is **off unless a deployment turns it on**. `8-07`'s Out of scope forbids this becoming a
second registration path for real customers; a default of `false` is the cheapest enforcement.

### 5. Everything minted is recognisably temporary

`sites.name` reads `Demo tenant — expires <date> UTC`, the public key is `demo_…`, and the username is
`demo-…`. The name is the field `12-03`'s owner view already renders, so a demo tenant cannot be
mistaken for a real customer without that view changing at all. A structured flag in the owner
response would be better and is deliberately deferred — it is a console change for a cosmetic gain.

The seeded `8-05` tenants have no `demo_expires_at` and are therefore invisible to the sweeper, however
old they get. There is a test that says so.

## Two things Keycloak does that this ADR was written not knowing

Both were found by tests, after the code was written the other way, and both changed the design.

**Keycloak assigns the subject id, and silently ignores one the caller chose.** The handler was first
written to generate the id itself, write the operator row, then create the identity — an ordering whose
half-failure is self-healing (a tenant nobody can log into, removed by the sweeper within a day) rather
than an orphaned identity-provider user nothing knows about.

That reading survived one wrong turn worth recording, because the wrong turn is the more useful lesson.
The first evidence was a `409 Conflict` from `POST /admin/realms/{realm}/users`, and it was attributed
to the `id` in the body; the ordering was rebuilt around a refusal that was not happening. The 409 was a
**username** collision — see the third finding below. A test written specifically to separate the two
claims (`KeycloakSilentlyIgnoresACallerChosenUserId`) then established the real behaviour, and it is
worse than a refusal: **Keycloak answers `201 Created` and assigns an id of its own**, ignoring the one
supplied. Nothing errors. Had the original design shipped, every minted operator row would have carried
a subject id no identity has, and every minted login would have failed to resolve — silently, with no
failed request anywhere to notice.

So the identity is created first, the id is read back from the `Location` header, it becomes
`Operator.ExternalSubjectId`, and a failed registration deletes the user it just made. The conclusion is
the one this ADR reached before the evidence was understood; the reasoning behind it is not, and the
difference matters because the next person to touch this will otherwise re-run the same experiment
against the same 409 and reach the same wrong place. **One window remains uncovered: a process death between the
two writes orphans a Keycloak user with no site, which nothing expires** — the sweeper works from
`sites`, so an identity with no site is invisible to it. It is bounded by this endpoint's own cap and
rate limit, and it is the price of Keycloak's constraint rather than of a choice.

**A username is not enough to make an account usable.** Keycloak's declarative user profile (default
since 24) leaves a username-only account with pending required actions, and the password grant then
answers `invalid_grant: Account is not fully set up`. The user is therefore created with
`requiredActions: []`, a first and last name, and an address at `demo.invalid` — a domain RFC 2606
reserves and which can never resolve. That keeps `8-07`'s "email of any kind is out of scope" true in
substance: nothing is sent, nothing is verified, and there is no address anybody could be reached at.
`emailVerified` is set true because there is nothing to verify and an unverified address blocks the
login this item exists to enable; it is the one place this code asserts something it did not check.

**And one thing about this codebase.** The username was first derived from the new operator's UUIDv7 —
`demo-` plus its first eight hex characters. A UUIDv7's leading bits *are* the millisecond timestamp,
so those characters change about once a minute and every mint inside the same window produced the same
username. The second mint in a test got a 409. A time-ordered id is the right thing for a primary key
and the wrong thing for anything that must be unique *and* short; the username now comes from the
credential generator's CSPRNG.

## Consequences

**A new secret exists.** `Keycloak:Admin:ClientSecret`, held by `Ago.Chat.Api` and `Ago.Chat.Worker`
and deliberately not by `Ago.Chat.Webhooks` — which is why its registration is not in `ChatModule`,
unlike almost everything else. In `17-03`'s inventory.

**A new project, `Ago.Chat.Infrastructure.Keycloak`.** Until this item nothing in `ago-chat` ever
*called* Keycloak; the Api validates tokens Keycloak signed, which needs no client. One project per
external technology, per `clean-architecture.md`.

**The capability generalises to `13-01`.** Operator invitations need exactly this credential and
exactly this kind of call. The port is deliberately narrow — `IDemoIdentityProvisioner`, two methods,
both about a demo identity — so widening it is a decision somebody has to make rather than something
that is simply available.

**What is not built, and therefore what `8-07` does not deliver yet:**

- **The button.** There is an endpoint and no UI. A stranger can obtain working credentials with one
  unauthenticated `POST`; a stranger with a browser cannot. Done-when #1 is met at the API and not in a
  browser, and Done-when #2 is proven as a property (two mints are two tenants with nothing shared)
  rather than demonstrated with two browsers.
- **The demo page's `?site=` handling**, without which a per-viewer tenant has no visitor side —
  see Decision 1.
- **A live MinIO in the expiry test.** The object-store step is asserted against a recording double.
- **Cache invalidation on deletion**, which `16-02` requires and this does not do.
- **Any deployment.** Nothing here has run against a cluster.

## Alternatives considered

**Join the shared demo site.** Far less work; leaves conversations mutually visible, which is the
thing the item exists to fix. Rejected in Decision 1.

**A pre-seeded pool of accounts.** Rejected in Decision 2: it avoids the new secret only in the version
that leaks access between viewers.

**Minting an operator token in the API, bypassing Keycloak.** Rejected: `adr/0022` chose one operator
identity provider, and a second path existing only for demos makes every statement about operator
authentication conditional.

**Waiting for `16-02` before shipping expiry.** Rejected: it would have meant either no expiry at all,
or Done-when #3 ticked on a job that deletes a Keycloak user and leaves the rows behind. The narrow
deletion here is smaller than `16-02` and shaped to be absorbed by it.

**A separate `is_demo` boolean beside the expiry.** Rejected: two columns that must agree are two
columns that can disagree, and the expiry is the one the sweeper reads.
