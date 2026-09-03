# smoke.sh cannot tell that the console's origin is refused by the API

- **Stage**: 15
- **Status**: done (2026-09-03)
- **Found**: 2026-09-03

## The gap

`smoke.sh` reports **43 passed, 0 failed** against a deployment where the operator console could not make a single API call. It did that twice on 2026-09-03 — once for `chat.` and once for `office.` — because nothing in it exercises the console's own REST path.

## Why it misses it

AGO Chat has **two** origin checks, and the suite covers one:

- **The operator hub** is gated by `Console:AllowedOrigins`, a manifest setting. `smoke.sh` checks this (`5-18`: *"an operator holds a hub connection from the console's origin"*) — and it passes, because it uses a minted demo operator against a demo site.
- **REST is gated per site by `sites.allowed_origins`, from the database**, through `SiteOriginCorsPolicyProvider`. **Nothing checks this at all.**

So a console can hold a websocket and still be unable to fetch anything — which is precisely the state both hostname moves produced, and precisely what a suite of 43 green checks failed to notice.

The two layers being in *different places* — one in a manifest, one in a database row — is what makes this easy to half-fix. `redeploy.md` and `deploy.sh` both describe the manifest half; the database half is invisible to every tool.

## What this must produce

A check that the console's origin gets `Access-Control-Allow-Origin` from the chat API, **with a control** that an unknown origin does not — the same shape the widget checks already use:

```
Origin: https://<console-host>      -> allow-origin: https://<console-host>
Origin: https://not-a-real-origin   -> allow-origin: (empty)
```

Both matter. The positive alone would pass against a wildcard; the control is what proves the policy is discriminating rather than permissive.

**One property to respect while writing it**: `CheckCorsOriginHandler` caches a denial for **30 seconds** deliberately (*"an origin approved moments ago should not read as denied for long"*). A check run immediately after a database change can legitimately fail. Either the check says so in its failure text, or the runbook does — a false red here trains people to ignore it.

## Done when

- [x] `smoke.sh` fails when the console's origin is absent from `sites.allowed_origins`, proven by removing it and watching it go red. — proven against the live deployment by removing the row, not against a local stand-in.
- [x] It passes with a control origin refused in the same run. — an unknown origin gets no `Access-Control-Allow-Origin`, asserted on the *header* rather than the status, because a refused origin still answers `200`.
- [x] The 30-second negative cache cannot make it flaky, or its message says that is what happened. — the check documents both cache directions in its own text: a denial is remembered for 30 seconds, an approval for five minutes.

## Context

Found 2026-09-03. The console moved to `chat.` in the morning and `office.` in the evening; both times the manifest half was updated and verified, the database half was not, and `smoke.sh` was green throughout. The second time, the failure reached the author as `Sign-in failed: Failed to fetch` — see `11-17` for why that wording made it worse.

## Outcome

Done 2026-09-03, `ago-deploy#126`.

**The 30-second cache nearly cost the fix its credit.** Re-running the check immediately after adding
the console's origin to `sites.allowed_origins` still showed it refused, which reads exactly like a
fix that did not work. It was the negative cache this item's own text had already warned about —
documented in the source, and still nearly mistaken for a broken change while writing the check that
exists to prevent that mistake. The check now says so in its failure text, so nobody has to remember.

**Asserting on the header, not the status, is the part that would have been easy to get wrong.** A
request from a refused origin still returns `200`; only the absent `Access-Control-Allow-Origin` tells
the two apart. A status-based check would have been green in exactly the state this item exists to
catch — which is how the original 43-passed run happened.
