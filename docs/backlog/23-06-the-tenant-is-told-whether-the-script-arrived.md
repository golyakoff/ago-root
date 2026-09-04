# the tenant is told whether their script arrived — and whether the product is being used at all

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: `docs/design/decisions.md` §3, the install half and the *two facts, not one*
  amendment (2026-09-04)

## Goal

A tenant who has installed the widget can tell which of these is true: *the script has not arrived
yet*, *it is here and quiet*, *it is here and every request is being refused*, or *the widget has
never been seen and the product is being used anyway* — the last of which is an ordinary state for a
tenant whose customers arrive over a channel.

Today `POST /api/v1/visitor-sessions` resolves the site by public key and persists nothing, so there
is no evidence to give them. `flows.md` 4.1 names guessing between those states as the thing the
tenant must not be made to do, and calls this the weakest flow in the product.

## Two facts, not one — and why getting this wrong is the harm the decision forbids

§3's amendment. `last_seen_at` written from a visitor-session mint measures **the widget**, and whole
classes of activity never take that path: a booking, a reminder, a reply over a channel and a
cancellation mint no session at all. Without a second fact, a tenant whose customers arrive by
channel reads "the script has not arrived yet" and the advice logic sends them to fix an install that
is irrelevant — the mirror image of the harm §3 exists to prevent.

So this item records **the widget was seen** and reads **the product was used**, and the diagnosis
branches on both.

## Why the refused origin is half the answer

§3's reasoning, and it is the part an implementation drops: the common failure is not a tenant
spreading the script over extra sites — it is `www.` against the bare domain, `http` against
`https`, or a staging subdomain. Then *everything* is refused, `last_seen_at` never updates, and
without the refusal record the product tells somebody whose script is installed and running that it
has never seen their site. Two states, indistinguishable, and the wrong one is the discouraging one.

## Context to read first

- `docs/design/decisions.md` §3, especially the inverted-failure-mode paragraph — three zeros are the
  *normal first state* — and the two-facts amendment
- `docs/design/flows.md` 4.1; `docs/design/ui-inventory.md` §6.1 (the three install panels, and the
  origins panel that renders nothing at all when the list is empty)
- `Ago.Chat.Api/Auth/AuthEndpoints.cs` — `HandleVisitorSessionAsync`,
  `HandleVisitorSessionRenewalAsync`, and both `origin-not-allowed` branches
- `docs/architecture/caching.md` — `GetSiteConfigByPublicKeyHandler` is a cache-aside read on the
  hottest endpoint in the product, and these four columns must never be served from it

## Scope

- Four additive columns on `sites`: `first_seen_at`, `last_seen_at`, `last_refused_origin`,
  `last_refused_origin_at`. All nullable; the migration backfills nothing. (`sites` holds none of
  these today — the `first_seen_at`/`last_seen_at` pair in the schema belongs to `visitors`.)
- `HandleVisitorSessionAsync` records a sighting on success and a refusal on the `origin-not-allowed`
  branch. `HandleVisitorSessionRenewalAsync` records a sighting too — a returning visitor renews
  rather than mints.
- **At most one row write per site per minute**, as a conditional
  `UPDATE sites SET last_seen_at = @now WHERE id = @id AND (last_seen_at IS NULL OR last_seen_at <
  @now - interval '1 minute')`, with `first_seen_at` written in the same statement only when null.
  The statement runs once per mint or renewal; the row write happens once a minute. **Say that cost
  in the code**, because it is the reason it is a conditional update and not a job.
- The write goes to Postgres directly and **must not** be routed through the site cache. A stale
  `last_seen_at` served from Redis is a lie on exactly the screen this exists for.
- **The second fact is a read, not a column.** *The product was used* is answered from
  `conversations` — any conversation created for this site in the window, over any channel. Nothing
  new is stored for it, which is the point: the data already exists and only the question is new.
- `GET /api/v1/sites/{siteId}/installation` (a handler and DTO beside the existing site reads, gated
  on `Permission.SiteConfigure` like every other `/sites/{siteId}/...` read) returns the four facts,
  the used-at fact, and a **resolved state** — computed server-side so the console does not re-derive
  the rule.
- A `RecentlyThresholdDays` option, default `7`, in configuration. §3 names the number and says it is
  configuration.
- `ago-console` `/settings/install`: the states, worded so *not seen at all* reads as a next step
  rather than a failure, so *installed and quiet* says how long it has been quiet, and so *never seen
  but in use* does not tell a channel-only tenant to go and fix an install.

## Out of scope

- The funnel and its advice — `23-07`, which depends on this.
- The beacon. It belongs to `23-07`, which is where the count it feeds lives; this item's sighting is
  written from the session paths that exist today. Note in the code that a returning visitor whose
  token needs no renewal makes no call at all (`ago-widget/src/session.ts` `start()`, the
  `isInRenewalWindow` short-circuit), so `last_seen_at` under-reports that visitor — tolerable for a
  once-a-minute freshness signal, and closed properly by `23-07`.
- Exact accounting. §3: "nobody audits 273 against 271."
- Recording *every* refused origin, or a history of them. One value plus its timestamp answers the
  question; a table of refusals is a different feature with a retention question attached.
- Telling the tenant which of *their* origins is unused.

## Done when

- [ ] A visitor-session mint updates `last_seen_at` at most once a minute, proven by two mints inside
      one minute and one row write.
- [ ] A request from an origin not in the site's list records `last_refused_origin` and does **not**
      update `last_seen_at`.
- [ ] A site never seen and a site seen long ago are distinguishable through the installation read.
- [ ] A site never seen whose conversations exist resolves to the *in use, widget unseen* state, and
      the advice for *zero loads* is not produced for it.
- [ ] The site cache cannot serve a stale `last_seen_at` — an integration test that writes and then
      reads through the API.
- [ ] Another tenant's installation state cannot be read (a tenant-isolation test).
- [ ] `/settings/install` renders every state, and *never seen* is the one a brand-new tenant gets on
      day one.
- [ ] `data-model.md`'s `sites` section carries the columns and the once-a-minute rule; `caching.md`
      states that these four are never cached.

## Open questions

None.
