# smoke.sh cannot tell that the console's origin is refused by the API

- **Stage**: 15
- **Status**: ready
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

- [ ] `smoke.sh` fails when the console's origin is absent from `sites.allowed_origins`, proven by removing it and watching it go red.
- [ ] It passes with a control origin refused in the same run.
- [ ] The 30-second negative cache cannot make it flaky, or its message says that is what happened.

## Context

Found 2026-09-03. The console moved to `chat.` in the morning and `office.` in the evening; both times the manifest half was updated and verified, the database half was not, and `smoke.sh` was green throughout. The second time, the failure reached the author as `Sign-in failed: Failed to fetch` — see `11-17` for why that wording made it worse.
