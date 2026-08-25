# Visitor sessions renew silently, so the lifetime can finally come down

- **Stage**: 17
- **Status**: ready
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

- [ ] A visitor whose stored token is near expiry gets a fresh token for the **same** `VisitorId`, and
      their conversation history is still theirs — proven end to end, not asserted.
- [ ] `JwtTokenService.VisitorTokenLifetime` is 7 days, and `adr/0034`/`authorization.md` say so.
- [ ] A test covers the expired-token path explicitly, whichever behaviour is chosen for it.
- [ ] The renewal endpoint is rate-limited, with a test that it is actually wired to the limiter
      (`3-05`'s own Done-when precedent — proving `IRateLimiter` exists somewhere is not the same
      thing).

## Open questions

- Sliding renewal (each renewal restarts the 7 days, so an active visitor never expires) or an
  absolute cap after which re-identification is forced regardless? Sliding is what the product wants;
  an absolute cap is what bounds a stolen token. The answer belongs in this item.
