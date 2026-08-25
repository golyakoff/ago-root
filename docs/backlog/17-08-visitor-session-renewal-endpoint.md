# The server half of visitor-session renewal, and the seven-day token

- **Stage**: 17
- **Status**: ready
- **Depends on**: `17-07-visitor-session-silent-renewal.md` — merged, and it specified this contract
  rather than guessing at one. `adr/0048` is the specification; this item is the implementation.

## Goal

`ago-widget` can renew a visitor session against a real endpoint, and `JwtTokenService`'s visitor
token lifetime comes down from thirty days to seven — the number `adr/0048` argued for and could not
land, because lowering it without a renewal path only moves the day a returning visitor silently
loses their conversation from day 31 to day 8.

## Why this is a separate item rather than part of `17-07`

`17-07` was deliberately built to be correct against the API **as deployed**: the widget treats a
`404` on renewal as a transient failure, so a visitor keeps the valid token they already hold and
nothing regresses. That was the right split — it let the client half land and be reviewed on its own
— but it means the feature does nothing until this lands, and the constant still says thirty days.

**Nothing in the documents claims otherwise today**, and that was deliberate: `authorization.md` still
states thirty days and no renewal, because that is true of what is running. This item is what makes
those sentences false, and it must update them in the same change.

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
      an integration test.
- [ ] A token minted for one site cannot be renewed by presenting another site's public key, proven by
      a test that fails if the check is removed.
- [ ] The rate limit is per visitor and is proven to limit, with `Retry-After` present.
- [ ] `VisitorTokenLifetime` is seven days, and every document that stated thirty is updated in this
      same change — including `authorization.md`, which was deliberately left stating thirty because
      that was true until now.
- [ ] `adr/0034` and `adr/0048` no longer describe this half as queued.

## Open questions

None. `adr/0048` decided the shape, the status code, the rate-limit key and the lifetime, each with
its reasoning. If implementation contradicts one of those decisions, that is a finding worth writing
down rather than a licence to quietly choose differently.
