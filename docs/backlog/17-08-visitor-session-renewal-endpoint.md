# The server half of visitor-session renewal, and the seven-day token

- **Stage**: 17
- **Status**: implemented 2026-08-26 — one Done-when still open, the end-to-end walk against a
  running stack. Everything else below is shipped and tested.
- **Depends on**: `17-07-visitor-session-silent-renewal.md` — merged, and it specified this contract
  rather than guessing at one. `adr/0048` is the specification; this item is the implementation.

## Goal

`ago-widget` can renew a visitor session against a real endpoint, and `JwtTokenService`'s visitor
token lifetime comes down from thirty days to seven — the number `adr/0048` argued for and could not
land, because lowering it without a renewal path only moves the day a returning visitor silently
loses their conversation from day 31 to day 8.

## Why this is a separate item rather than part of `17-07`

`17-07` was deliberately built to be correct against the API **as it was then deployed**: the widget
treats a `404` on renewal as a transient failure, so a visitor kept the valid token they already held
and nothing regressed. That was the right split — it let the client half land and be reviewed on its
own — but it meant the feature did nothing until this item landed, and the constant still said thirty
days.

**Nothing in the documents claimed otherwise in the meantime**, and that was deliberate:
`authorization.md` still stated thirty days and no renewal, because that was true of what was
running. This item is what made those sentences false, and it updated them in the same change (see
the Done-when list, and the section at the end for the ones outside its lane).

## The contract, from `adr/0048`

Read the ADR rather than this summary before implementing — it carries the reasoning, not just the
shape.

- **`POST /api/v1/visitor-sessions/renew`**, authenticated on the **Visitor** scheme. `sub` and
  `site_id` come from the validated principal, **never from the body**.
- **A separate endpoint, not a flag on the mint.** A flag would make one endpoint both
  public-unauthenticated and authenticated depending on a body field, with different rate-limit keys
  and different status codes per path — two endpoints wearing one route.
- The body carries the site's **public key**; reuse the cached `GetSiteConfigByPublicKeyHandler`, and
  **reject a request whose resolved `SiteId` does not equal the token's claim.** Origin is checked the
  way the mint checks it (`5-01`'s layer 2).
- **`200 OK`**, not `201` — nothing is created — with **the same response shape as the mint**. That
  shape also closes a limitation `ago-widget/src/storage.ts` has recorded since `11-03`: it wanted "a
  session endpoint that can return current config without minting a new visitor", and this is one.
- **Rate-limited per visitor** (`visitor-session-renew:visitor:{visitorId}`), not per site. This is a
  deliberate deviation from the shape the mint uses, and the reason is that the mint has no visitor
  identity to key on while renewal does: per-visitor stops one abusive token-holder exhausting a
  bucket shared with an entire site. `429` with `Retry-After`, which the widget already honours with
  jittered backoff.
- **`JwtTokenService.VisitorTokenLifetime` → `TimeSpan.FromDays(7)`.**

## Scope

- The endpoint, its handler, and the rate-limit policy, following the shapes the mint already uses —
  this is not a new pattern, it is the same pattern with an authenticated principal.
- The lifetime constant, and the documents that state the old number: `authorization.md` (line ~33 and
  the "visitor token's lifetime is a decision now" paragraph), and any others a grep for "thirty days"
  or "30 days" turns up in this context.
- `adr/0034`'s superseded-in-part banner and `adr/0048` both need their "the `Ago.Chat.Api` half is
  queued" notes turned into "shipped", with the date.
- Integration tests at the level the mint's already have: a real token renewed, a token for site A
  refused against site B's public key, an expired token refused, an unauthenticated call refused, and
  the rate limit actually limiting.

## Out of scope

- Any change to how the token is minted, or to the public mint endpoint's own rate limiting.
- Revocation. `adr/0034` answered that with "no, and here is the trigger", and a renewal endpoint does
  not change the answer — it shortens the window instead, which was the point.
- `ago-widget`. It is finished and already handles this endpoint's absence, its success and its `429`.
  If implementing this turns up something the widget got wrong, **report it rather than fixing it
  here**; the two repositories should not move in one change without a reason.

## Done when

- [ ] A widget holding a valid token near expiry renews it against the real API and keeps the same
      `VisitorId` and the same conversation — verified end to end against a running stack, not only by
      an integration test. **Not done — the only unmet criterion.** The equivalent is proven at the
      HTTP boundary (`ARenewal_Returns200_WithAFullFreshLifetimeForTheSameVisitor`: a real six-day-old
      token, renewed over a real request pipeline, comes back with the same `VisitorId` and a full
      fresh seven days), and the widget half has its own tests against a stubbed endpoint (`17-07`),
      but nobody has driven a browser against a running stack. See below for what that walk still
      has to show.
- [x] A token minted for one site cannot be renewed by presenting another site's public key, proven by
      a test that fails if the check is removed —
      `ATokenForOneSite_CannotBeRenewedByPresentingAnotherSitesPublicKey`, verified to return `200`
      instead of `403` with the comparison deleted.
- [x] The rate limit is per visitor and is proven to limit, with `Retry-After` present — two tests,
      because "it limits" and "it is keyed per visitor" are different claims: re-keying the bucket to
      the site leaves the first passing and fails the second.
- [x] `VisitorTokenLifetime` is seven days, asserted at the wire
      (`TheTokenARenewalIssues_LastsSevenDays`) rather than only next to the constant, and every
      document in this change's reach that stated thirty is updated — `authorization.md` (the actor
      table and the `17-06` paragraph, both deliberately left stating thirty until now), `adr/0034`
      and `adr/0048`.
- [x] `adr/0034` and `adr/0048` no longer describe this half as queued — `0034`'s banner and `0048`'s
      new **Implemented** line both state both halves shipped, with the date.

## What the end-to-end walk still has to show

Left open rather than ticked, since it needs a running stack and a browser:

- A widget whose stored token is inside its renewal window (an existing visitor, or one whose token
  was minted with the clock wound back) loads the page and issues exactly one
  `POST /api/v1/visitor-sessions/renew`.
- The `VisitorId` in `localStorage` is unchanged afterwards, and the open conversation continues —
  the same thread, no new one, and the hub reconnects with the renewed token rather than the captured
  one (`adr/0048`'s `accessTokenFactory` case, which is the reason at-use renewal was chosen).
- The refreshed widget config in the response is applied, closing `storage.ts`'s `11-03` limitation
  in practice and not only in `ARenewal_ReturnsTheSitesCurrentWidgetConfig_...`.

## Open questions

None. `adr/0048` decided the shape, the status code, the rate-limit key and the lifetime, each with
its reasoning. If implementation contradicts one of those decisions, that is a finding worth writing
down rather than a licence to quietly choose differently.

**Nothing contradicted it.** Two cases the ADR did not name came up and are now recorded in it
("Two things `17-08` had to decide that this section did not name"): an unknown public key answers
`404` like the mint rather than `403`, and the site-claim check runs before the origin check.

## Documents outside the implementation's lane, found by grep and fixed at merge

The implementation was scoped to a lane that excluded these, so they were reported rather than
edited, and then fixed in this same change by the session that merged it — a doc this change makes
false is this change's problem regardless of who typed it:

- **`docs/architecture/personal-data.md`**, the visitor's-own-browser row: said "the signed visitor
  token (30-day `exp`)" and "The token expires after 30 days". Now seven, and it says the token
  renews — which matters there specifically, because renewal means the shorter number buys **no**
  deletion on the visitor's device. The row's own point ("the `localStorage` entries themselves never
  expire") is unaffected and stands.
- **`docs/backlog/17-03-secret-handling-and-rotation.md`**, which stated the key-rotation drain window
  as thirty days and said it "becomes seven when `17-07` gives the widget a renewal path". It has, so
  the window is seven — and the fact that the number has now moved once is written down there as the
  argument for building the retirement delay as configuration rather than reading a constant.
- **`docs/architecture/tenant-isolation.md`** — not a thirty-day hit, but its route table enumerates
  every tenant-carrying surface and had no row for `/renew`. Added, noting that it is the one route
  where two `siteId` sources are compared rather than one being trusted.
- **`docs/roadmap.md`** — this item's queue row swept, `17-07` and `17-08` recorded as done in the
  Stage 17 section, and `17-06`'s done-record annotated so its "thirty days is a stated decision"
  cannot be read as current.
- **`docs/backlog/17-02-...`** (a lifetime table), **`5-14`**, **`5-16`**, **`17-06`**, **`17-07`** —
  historical records of what was true when each was written; correct as history, worth a glance if a
  reader is likely to mistake one for current state.
