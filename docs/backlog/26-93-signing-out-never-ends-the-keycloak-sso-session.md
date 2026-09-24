# 26-93 · Signing out of the app never ends the Keycloak SSO session in the browser

- **Stage**: 26
- **Status**: done — merged as [ago-android#75](https://github.com/golyakoff/ago-android/pull/75). The
  realm client also needed a live fix outside this repo: `ago-android`'s Keycloak client had no
  `post.logout.redirect.uris` registered, and Keycloak 26 treats that as zero valid post-logout
  redirects (not "same as `redirectUris`") — every real sign-out failed with "Invalid redirect uri"
  until this was applied by hand against the live realm and persisted in
  [ago-deploy#264](https://github.com/golyakoff/ago-deploy/pull/264).
- **Found**: 2026-09-24, by the author, live on a real device — "я не могу по-настоящему
  разлогиниться в приложении на телефоне, чтобы зайти под другим аккаунтом. Очистка кэша приложения
  и даже переустановка не помогают, у меня не спрашивают логин и пароль, а сразу логинят в
  демо-пользователя."

## Root cause, confirmed against the real code

`AgoAuthSession.kt`'s own KDoc states the design plainly: sign-in is Authorization Code + PKCE in a
**Custom Tab** (`26-11`), chosen specifically over a WebView because "there is no shared SSO session
with the system browser" is one of the reasons a WebView is *wrong* — which is a direct statement
that a Custom Tab **does** share the system browser's cookies, by design (RFC 8252).

`signOut()` (`AgoAuthSession.kt:226-239`) only discards the local `AuthState` and clears
`SessionStore` — it never calls Keycloak's own `end_session_endpoint` (RP-Initiated Logout). The
Keycloak SSO session cookie therefore survives in the device's system browser (Chrome) after
in-app sign-out, and — because that cookie lives in the browser's own storage, not the app's —
survives an app **reinstall** too (`allowBackup="false"` correctly stops app data from following the
app; it was never the app's data holding this session). The next sign-in opens the same Custom Tab,
Keycloak sees the still-live cookie, and silently completes the authorization code flow with no
credential prompt at all — which is exactly what was observed.

This is not only a testing annoyance: it means a second operator using a phone that previously
signed in stays silently signable-in as the first operator's identity until that browser's own
cookies are cleared by hand.

## Scope

- `AgoAuthSession.signOut()`: before clearing local state, perform an OIDC RP-Initiated Logout —
  discover the realm's `end_session_endpoint` (already available from the discovery document
  `beginAuthorization` fetches) and launch it via `net.openid.appauth.EndSessionRequest`, passing the
  current `id_token_hint` and a `post_logout_redirect_uri` the app can catch, the same Custom Tab
  mechanism as sign-in. Local state clears only after the end-session round trip completes (or fails
  in a way that must not block sign-out — decide and write down which failures are which, mirroring
  this function's own existing device-revocation ordering comment).
- A new redirect target for the post-logout callback (`ago-android://logout-callback` or similar),
  registered in the realm's client config alongside the existing sign-in redirect (`26-11`'s own
  territory) and in the manifest's intent filter next to the existing one.
- `MainActivity`'s existing Custom Tab result handling gets the new callback's own branch.

## Out of scope

- Device revocation on sign-out — already implemented (`26-06`), untouched.
- Any change to sign-*in* — the Custom Tab choice and its reasoning stand.
- A "sign out everywhere" / revoke-all-sessions admin action — a different, larger feature.

## Done when

- [~] After sign-out, the same device's Chrome no longer holds a live Keycloak session for that
      realm — not yet reproduced on a real device by the managing session since the realm fix landed;
      the mechanism (RP-Initiated Logout via Custom Tab) is proven at the ordering-test level.
- [~] Signing in again after signing out prompts for credentials, on the same device — same as above,
      pending a real-device check now that the realm client carries the redirect URI.
- [x] A failure of the end-session call does not prevent local sign-out from completing —
      `completeSignOut(data: Intent?)` runs unconditionally regardless of how the round trip ended,
      proven in `AgoAuthSessionSignOutOrderingTest`.
- [x] `./gradlew ktlintCheck lint test` green — 430 tests, 0 failures, independently re-verified with
      `--rerun-tasks`; both sign-out tests extended for the new two-step ordering.
- [x] No new string literal in any view — none was needed; nothing user-facing was added.
