# 25-105 · The office console loses the session silently after being idle

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session after the implementing
  worker's own report: rebased cleanly onto `main` (by then including `25-104`, i18n files
  auto-merged with no conflicts), `npm run typecheck`/`lint` clean, full console suite re-run at
  1467/1467.
- **Depends on**: nothing
- **Found**: 2026-09-15, the author leaving the office console idle and returning to it: a stuck
  "Подключение…" followed by "Failed to load the queue: 401", recoverable only by a manual re-login.
  The author's own framing, after an initial narrower fix was proposed and corrected: "надо не
  оставлять [4 часа как есть], а сделать так чтобы 4 часа реально работали, а не 5 минут" — the
  4-hour idle SSO window (`ssoSessionIdleTimeout`, `keycloak-realm-import.json`) is the right business
  choice and stays; what was broken is that the app did not actually survive it.

## What is actually true

`accessTokenLifespan` is 5 minutes; `ssoSessionIdleTimeout` is 4 hours — a refresh token lives exactly
as long as the SSO session it belongs to (`adr/0034`). The real-world symptom tracked the 5-minute
number, not the 4-hour one.

Root cause: `oidc-client-ts`'s own `SilentRenewService` retries only its internal `ErrorTimeout`
class, and only when `maxSilentRenewTimeoutRetries` is configured — this app never sets it, so a
timeout in fact retries forever and never reaches `AuthProvider`'s handler at all. Every *other*
renewal failure (a dropped fetch, a request starved while the tab was suspended) gets zero retries and
fires `silentRenewError` on the first miss. `AuthProvider` wired that straight to `removeUser()`,
turning one ordinary renewal hiccup into an immediate, irreversible sign-out. The most plausible source
of those hiccups: `oidc-client-ts` schedules renewal with a plain browser timer, which Chrome and other
browsers are free to throttle or fully suspend on a backgrounded tab — exactly the state an operator
"waiting for messages" leaves their console tab in for most of a 4-hour idle window.

## Scope

- `AuthProvider`: only a genuine `ErrorResponse` (Keycloak's token endpoint actually rejecting the
  refresh grant — `invalid_grant`, the shape a truly-dead or revoked session produces) is treated as
  fatal. A plain `Error`/`TypeError` from a request that never completed is not evidence the session
  is dead, and no longer triggers a sign-out on its own.
- `AuthProvider`: a `visibilitychange` listener fires `signinSilent()` the moment a hidden tab becomes
  visible again — closing the gap a purely timer-driven renewal leaves for as long as the tab was
  backgrounded, which is this item's actual fix for the 4-hour window surviving in practice, not just
  failing honestly once it is genuinely over.
- `RequireAuth`: redirects on `user.expired` as well as `user === null` — a page load can restore an
  already-expired `User` from `sessionStorage` before any renewal has had a chance to run.
- `conversationsApi.ts`'s four read functions that threw a bare `Error` with the status baked into
  English text (`"Failed to load the queue: 401"` — the exact text the author saw) now throw
  `ApiProblemError` via this file's own established `problemDetailsFrom` convention, so a residual 401
  race can be told apart from a real outage; `WorkspaceLayout`/`ConversationPage`/
  `AdminConversationsPage` show an honest, translated "session expired, sign in again" message for
  that case instead of the raw status text.

## Out of scope

- Changing `ssoSessionIdleTimeout` itself — 4 hours is a deliberate business choice for this product's
  operator model, confirmed explicitly by the author, and this item is entirely about making that
  number true in practice, not about picking a different one.
- A second, independent path to end a session (e.g. redirecting straight from the renewal-error
  handler) — `23-51`'s own lesson was that two paths racing to the same outcome is how a clean
  sign-out turns into a coin toss; this item reuses that item's one sanctioned path
  (`removeUser()` → `userUnloaded` → `user === null` → `RequireAuth`'s redirect) rather than adding a
  second one.

## Done when

- [x] A renewal hiccup that is not a genuine OAuth rejection no longer signs an operator out — proven
      by `src/auth/sessionExpiry.test.tsx`'s own cases distinguishing `ErrorResponse` from a generic
      `Error`.
- [x] A hidden tab regaining visibility triggers an explicit renewal attempt, so the 4-hour idle
      window is not solely dependent on a timer the browser is free to throttle while the tab is
      backgrounded — proven by the same test file's visibility-triggered-renewal cases (success and
      failure paths).
- [x] A `401` reaching the console's own read calls surfaces as a translated "session expired, sign in
      again" message, not raw status text — `WorkspaceLayout`/`ConversationPage`/
      `AdminConversationsPage` all updated, through `strings.authSessionExpiredError`.
- [x] Full console suite green after the change: 1467/1467 across 139 files, independently re-run by
      the managing session, not only claimed by the implementing worker.
