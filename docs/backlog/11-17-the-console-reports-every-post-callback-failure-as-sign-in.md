# the console reports every post-callback failure as "Sign-in failed"

- **Stage**: 11
- **Status**: done (2026-09-03)
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

- [x] A CORS-blocked or unreachable API after a successful sign-in reads as something other than "Sign-in failed", and names the API. — it reads *"Signed in, but couldn't load your account"*, names `GET /api/v1/operators/me`, and says in as many words that this is not an identity-provider problem.
- [x] Reloading the callback URL, or opening a stale one, does not render an error box — proven by doing it. — nothing renders; `RequireAuth`'s existing no-session redirect takes it back to sign-in, reusing the redirect rather than adding OIDC logic to the callback page.
- [x] A genuine identity-provider refusal still reads as a sign-in failure. — unchanged wording, still `role="alert"` (`11-05`), and guarded in the safe direction by `instanceof ErrorResponse` so a real refusal can never be mistaken for a reload.
- [x] Each of the three is covered by a test; `CallbackPage.test.tsx` already asserts on this text, so it is the file that has to grow rather than a new one. — it did grow, plus `src/auth/replayedCallback.test.ts` for the predicate.

## Context

Found 2026-09-03, moving the console to `office.reserve-me.ru` (`22-10`). The CORS half was a real defect and is fixed; this is the half that made it expensive to find.

## Outcome

Done 2026-09-03, `ago-console#96`.

**The hinge is a library's literal strings, and that is now a test rather than a comment.**
`oidc-client-ts` has no error type for an already-consumed authorization code — `readSigninResponseState`
throws a plain `Error` carrying `"No matching state found in storage"` or `"No state in response"`.
Recognising a replay therefore means matching on those strings, which a library reword would silently
break: the suite would stay green while the console went back to blaming Keycloak for a page reload.

The first pass documented that fragility honestly and left every test constructing the error by hand,
which is a doc comment doing a test's job. It was sent back for one addition: `replayedCallback.test.ts`
now constructs a real `OidcClient` and calls `readSigninResponseState` itself, asserting the library
still throws exactly the strings production matches on. Its failure message names the set, the file and
the pinned `^3.3.0` range, so the next person updates the set instead of chasing a mystery.

**One narrower variant is knowingly left as it was.** If a double-submit race reaches the token
endpoint, Keycloak answers `invalid_grant` as an `ErrorResponse`, which still reads as a sign-in
failure. The dominant, reproducible case — a full-page reload after the exchange already completed —
is the one covered.

The extraction into `src/auth/` is not tidying: exporting the predicate from a page file trips
`react-refresh/only-export-components`, and `registrationUrl.ts` set that precedent. The rule was
resolved rather than suppressed.

Verified independently before merge: typecheck and lint clean, 623 tests in 65 files, ux-gate 25
passed / 5 skipped.
