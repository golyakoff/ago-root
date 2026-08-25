# Visitor sessions renew silently, so the lifetime can finally come down

- **Stage**: 17
- **Status**: done in `ago-widget`; the `Ago.Chat.Api` half is specified and queued (see Outcome)
- **Depends on**: nothing. Created by `17-06`, which decided the visitor token's lifetime and found
  that the number cannot move on its own. Pairs with `17-03`, whose key-rotation drain window is
  whatever this item leaves the lifetime at.
- **Not `5-16`, despite both saying "token renewal".** The two were written the same day, from
  opposite sides, and the titles invite confusion — so, plainly: `5-16` is `ago-console`, where an
  OIDC access token *does* renew and the renewal silently drops the operator's subscription to the
  conversation they are watching. This item is `ago-widget`, where a visitor token never renews at
  all, which is why its lifetime cannot come down. Different repository, different token, different
  failure. Neither supersedes the other and neither blocks the other.

## Goal

A returning visitor keeps their conversation without holding a 30-day bearer token to do it. Today
those are the same thing: `ago-widget`'s `getOrCreateVisitorSession` stores the token it was first
given and reuses it forever — it never inspects `exp` and never re-mints — so the token's lifetime *is*
how long a returning visitor still sees their own history, and shortening it would only move the day
the widget silently stops working from day 31 to day 8.

Once renewal exists the two stop being the same number, and the lifetime drops to **7 days** in the
same change.

## What `17-06` established, so this item does not re-argue it

`adr/0034` decided 30 days and stated why the number could not simply be lowered. Three facts from
that decision are inputs here, not questions:

- **The minting endpoint is public and unauthenticated by design** (`POST /api/v1/visitor-sessions`,
  `api-design.md` — a site's public key is not a secret). So a shorter lifetime is not primarily an
  anti-theft measure; anyone positioned to read a token can mint their own. What it bounds is one
  visitor's own transcript staying reachable from a shared or lost device.
- **There is no revocation and deliberately none planned** (`adr/0034`) — no deny-list, because
  nothing in the system can currently decide that one token should stop working. Renewal is the
  cheaper half of that same trade, and this item is where it gets built.
- **The current failure mode is silence.** An expired token does not prompt anything; the widget keeps
  presenting it and the hub connection simply fails. Whatever this item builds should make that path
  observable rather than moving it.

## Scope

- **A renewal endpoint in `Ago.Chat.Api`** that takes a still-valid visitor token and returns a fresh
  one **for the same `VisitorId`**. Preserving the identity is the whole point — re-minting through
  the existing endpoint already "works" and is exactly what loses the history.
- **Widget-side renewal** in `ago-widget`'s `getOrCreateVisitorSession`: on load, if the stored token
  is within some fraction of its lifetime of expiring, exchange it before using it. Decide and record
  whether the check reads `exp` from the token or stores the expiry alongside it in `storage.ts` —
  `VisitorSession` already carries fields beyond the token itself (`11-03`).
- **A decided answer for the expired case**, which renewal does not remove, only makes rarer: a
  visitor who returns after the window is a genuinely new session. Whether the widget re-mints
  silently (losing history, no error) or surfaces something is a product choice this item should make
  rather than inherit.
- **Drop the lifetime to 7 days** (`JwtTokenService.VisitorTokenLifetime`) in the same change, and
  update `adr/0034` and `authorization.md`, both of which currently state 30 with this item named as
  the reason.
- **Rate limiting on the renewal endpoint**, keyed the way `3-05`'s existing visitor-session limiter
  is. A renewal is cheaper to abuse than a mint, since the caller already holds a valid token, but it
  is still an endpoint that issues credentials.

## Out of scope

- Revocation of any kind — `adr/0034` decided against it, and renewal does not reopen that.
- Per-site visitor signing keys, and the rotation mechanics — `17-03`.
- Anything about operator/Keycloak sessions; those lifetimes were set in `17-06` and are unrelated.

## Done when

- [x] A visitor whose stored token is near expiry gets a fresh token for the **same** `VisitorId`, and
      their conversation history is still theirs — proven by `ago-widget`'s `session.test.ts` and
      `ui/sessionRenewal.test.ts` against a faked API, **not** end to end: the endpoint they drive
      does not exist in `Ago.Chat.Api` yet (see Outcome). That gap is named rather than papered over.
- [ ] `JwtTokenService.VisitorTokenLifetime` is 7 days, and `adr/0034`/`authorization.md` say so.
      **Decided (`adr/0048`), not applied** — `ago-chat` was out of this session's lane. `adr/0034`
      carries the decision plus an explicit note that the constant is still 30; `authorization.md`
      moves with the code rather than ahead of it.
- [x] A test covers the expired-token path explicitly — both of them, since the answer differs by
      moment: expired at page load (re-mint, cleared cursor, a sentence in the panel) and expired
      while the page is open (the session ends visibly, no second identity).
- [ ] The renewal endpoint is rate-limited, with a test that it is actually wired to the limiter.
      Specified in Outcome and in `adr/0048`; belongs to the `ago-chat` change.

## Open questions

None. Both are answered in `adr/0048`: **sliding, no absolute cap** (the cap evicts the honest
visitor and not the attacker, because the minting endpoint is public and a visitor cannot
re-identify — with a named trigger for revisiting), and the expiry check **reads `exp` from the
token** rather than storing it alongside (a stored expiry cannot exist for the sessions already in
visitors' browsers, forcing a choice between a renewal storm on release day and the silence this item
exists to end).

## Outcome

**Split across two repositories, and only one of them was in reach.** `ago-widget` is done;
`Ago.Chat.Api` had an open PR and a package follow-up queued behind it, so the server half is
**specified precisely and deliberately not written**. That is a real state, not a failure: the widget
was built to be lifetime-agnostic and to treat a missing endpoint as a transient failure, so it runs
correctly against the API as deployed today (a `404` on renewal leaves the visitor on their existing
valid token) and starts renewing the moment the endpoint lands, with no second change on this side.

### What shipped in `ago-widget`

`getOrCreateVisitorSession` is now `VisitorSessionManager` (`src/session.ts`), plus `tokenExpiry.ts`,
a ~40-line JWT payload reader that verifies nothing and exists only to decide *when* to renew.

- **Renewal at the point of use, not on a timer.** Every place the token is presented — the hub's
  negotiate and the three attachment calls — goes through one method that exchanges the token first
  if less than a third of its own lifetime is left. `adr/0048` carries why this beats a timer; the
  short version is that a timer does not fire across a sleeping device, which is the ordinary case
  for a multi-day window.
- **The `5-17` trap, closed.** `accessTokenFactory` closed over a captured token — "harmless only
  because the token never rotates", which stopped being true here. It takes an async provider now, so
  a connection opened days ago and dropped negotiates with a token valid *at that moment*. This is
  the single change that decides whether the widget survives its own token's lifetime, and it is what
  `ui/sessionRenewal.test.ts`'s first test asserts.
- **The window comes from the token** (`exp - nbf`), never from a constant mirroring the server's, so
  the same code is correct against 30 days and 7.
- **Two different answers for expiry, by moment.** At page load: mint a new identity, clear the
  conversation cursor (a `lastKnownSequence` into a conversation the new `VisitorId` does not own
  would make the resuming `JoinAsync` ask for a delta of someone else's transcript), and say so in
  the panel. While the page is open: end the session visibly and stop the connection — re-identifying
  there would put the visitor in a different conversation underneath the first one's transcript,
  typing to an operator who cannot see them.
- **A transient failure never ends an identity.** Only a definitive `401`/`403` does; an unreachable
  API, a `5xx` or a `429` leaves the visitor on the token they still hold, throttled to one retry a
  minute so a dead API costs one request per minute rather than one per reconnect attempt.

103 tests (up from 72), `typecheck`/`lint`/`test`/`build` green, bundle **22.0 KB gzipped** (from
21.0) against the 45 KB budget. Ten deliberate breaks, each reverted at once, listed in the handback.

### What `Ago.Chat.Api` still needs — specified, not written

`adr/0048` carries the full contract. In brief: `POST /api/v1/visitor-sessions/renew`, authenticated
on the Visitor scheme, body carrying the site's public key (reusing `3-05`'s existing cached
`GetSiteConfigByPublicKeyHandler` lookup and rejecting a token whose `site_id` does not match),
`200 OK` with the **same response shape as the mint** — which also closes `ago-widget`'s recorded
`11-03` config-staleness limitation, since that shape is exactly the "session endpoint that can
return current config without minting a new visitor" it said did not exist. Rate-limited **per
visitor** rather than per site (the mint has no visitor identity to key on; renewal does, and
per-visitor stops one abusive holder exhausting a bucket shared with a whole site), `429` +
`Retry-After`, origin checked as the mint is. Plus `JwtTokenService.VisitorTokenLifetime` →
`TimeSpan.FromDays(7)` and the `authorization.md` paragraphs that state the old number.
