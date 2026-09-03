# the console reports every post-callback failure as "Sign-in failed"

- **Stage**: 11
- **Status**: ready
- **Found**: 2026-09-03

## What happened

The author signed in at the console's new hostname and saw:

```
Sign-in failed
Failed to fetch
```

**Sign-in had succeeded.** Keycloak accepted the redirect, issued the code, and the callback processed it. What failed was the call *after* it — `GET /api/v1/operators/me`, blocked by CORS because the new origin was not yet in any site's `allowed_origins`.

## Why the message is the defect

`CallbackPage`'s effect chains three steps under **one** `catch`:

```ts
userManager.signinRedirectCallback()
  .then(async (user) => {
    const state = await resolveOperatorState(user.access_token);   // ← a network call
    ...
  })
  .catch((err) => setError(err instanceof Error ? err.message : "Unknown error."));
```

So at least three unrelated failures render identically:

| what actually happened | what the operator reads |
|---|---|
| the API is unreachable, or the origin is refused by CORS | `Sign-in failed: Failed to fetch` |
| a stale or already-consumed `code` left in the URL (a reloaded or bookmarked callback) | `Sign-in failed: <oidc error>` |
| the identity provider genuinely refused | `Sign-in failed: …` |

**Both of the first two happened on 2026-09-03, and both misdirected the person diagnosing them** — the author went looking at the URL, I went looking at CORS, and each of us was half right. That is the cost: the message names the wrong step, so it sends whoever reads it to the wrong place.

## What this must produce

- **The three cases are distinguishable in the message.** Sign-in failing, the callback being replayed, and the first API call failing are different problems with different fixes.
- A **replayed callback is not an error at all** in the ordinary case — a reloaded page or a stale bookmark should send the operator back to sign in, not show a red box. `12-04`'s own reasoning is the precedent: an unanswerable probe means "go to `/onboarding`", not "fail loudly".
- The wording says what to do. `Failed to fetch` is the browser's words, not ours.

## Done when

- [ ] A CORS-blocked or unreachable API after a successful sign-in reads as something other than "Sign-in failed", and names the API.
- [ ] Reloading the callback URL, or opening a stale one, does not render an error box — proven by doing it.
- [ ] A genuine identity-provider refusal still reads as a sign-in failure.
- [ ] Each of the three is covered by a test; `CallbackPage.test.tsx` already asserts on this text, so it is the file that has to grow rather than a new one.

## Context

Found 2026-09-03, moving the console to `office.reserve-me.ru` (`22-10`). The CORS half was a real defect and is fixed; this is the half that made it expensive to find.
