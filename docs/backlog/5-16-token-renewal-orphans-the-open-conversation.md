# Fix: renewing the access token silently stops the open conversation receiving messages

- **Stage**: 5 — `OperatorConnection` and its provider are `5-07`'s, and this is a defect in them
- **Status**: done (live verification of the renewal still open — see Outcome)
- **Depends on**: nothing — `ago-console` only

## Goal

An operator watching a conversation keeps receiving its messages for as long as they are watching it.
Today they stop, silently, the first time their access token is renewed — while the screen keeps
showing the conversation as though nothing has changed.

## How this was found

Reported live (2026-08-25): after a long idle, an operator sent a message; the visitor received it and
the operator's own thread never showed it. Then, decisively: *"switched to another chat and back — it
recovered."*

That last detail is what identifies the defect. A dead connection could not have re-joined; a missed
push that reappears on re-entering the conversation is a subscription that was lost while the
connection stayed alive.

## The mechanism

`OperatorConnectionProvider` builds the connection as
`useMemo(() => new OperatorConnection(accessToken), [accessToken])`.

`oidc-client-ts` renews the access token silently, and the realm sets no `accessTokenLifespan`, so
Keycloak's own default applies — minutes, not hours. Every renewal changes `user.access_token`, and
therefore:

1. A **brand-new** `OperatorConnection` is constructed, with `conversationId = null`, a fresh
   `SequenceTracker` and fresh `SeenMessageIds`.
2. The effect calls `start()` on it.
3. **Nothing re-joins the conversation the operator is looking at.** `resumeAfterReconnect()` exists
   and is correct, but it is wired to SignalR's own `onreconnected`, which does not fire here — this
   is a new connection, not a reconnected one.
4. The old connection is never stopped. The provider says so deliberately, for a reason that is right
   about navigation and does not cover this case.

So the operator's thread goes deaf while the UI shows it as open, and re-entering the conversation
fixes it because that path calls `joinConversation` on the new connection.

**The same defect explains a second anomaly** found while investigating: the connection registry held
twelve live entries for one operator. Not twelve tabs, and not a tracker leak — one tab that had
renewed its token twelve times, each renewal orphaning a connection the server only reaps on its own
timeout.

## Context to read first

`ago-console/src/realtime/OperatorConnectionProvider.tsx` — the `useMemo` dependency, and the
deliberate absence of `stop()` with its reasoning, which is correct about in-app navigation and silent
about token renewal. `ago-console/src/realtime/operatorConnection.ts` — `resumeAfterReconnect()`, which
already does exactly the right thing for the case it is wired to, and `accessTokenFactory: () =>
accessToken`, which returns a captured constant rather than reading the current token (see Scope).
`docs/backlog/3-03-reconnect-resume-protocol.md` — the protocol being implemented, including why
resume is keyed on `lastKnownSequence`. `docs/architecture/realtime.md`'s reconnect section.

## Scope

- **Decide which of the two shapes to take, and say why.** Either the connection survives a token
  renewal — `accessTokenFactory` reads the current token at call time instead of closing over one, and
  the `useMemo` no longer depends on the token — or the rebuild stays and whatever replaces it re-joins
  the open conversation and restores the sequence state. The first is smaller and removes the orphaned
  connections as well; the second keeps the current structure. This is the item's one real decision.
- **`accessTokenFactory` should read the current token regardless.** It is a factory precisely so it
  can be called per connect and per reconnect attempt; returning a captured string defeats that, and
  today it is only survivable *because* of the rebuild this item is removing.
- **Stop the old connection** whenever one is genuinely replaced, so connections stop accumulating
  server-side.
- **A test at the level `conventions/testing.md` now names for the frontends**: a token renewal must
  leave the open conversation still receiving messages. This is the behaviour, and it is exactly the
  kind `11-08` argues for — no unit test of `backoff` or `SequenceTracker` could have caught it.
- **Verify live**, with a deliberately short token lifetime so the renewal happens in seconds rather
  than minutes, and confirm both that messages keep arriving and that the registry stops accumulating
  entries for one operator.

## Out of scope

- The visitor side. `ago-widget` uses its own long-lived visitor token issued by `Ago.Chat.Api`
  (thirty days, `17-03`), not an OIDC token that renews, so this mechanism does not apply — confirm
  rather than assume, and say so either way.
- The token lifetime itself — `17-06` owns whether Keycloak's defaults are right.
- The thirty-day visitor token and its rotation — `17-03`.
- The connections gauge — `7-07`, found in the same investigation and unrelated in cause.
- Any change to `3-03`'s protocol. The protocol is right and its implementation is right; it is simply
  not reached on this path.

## Done when

- [ ] A token renewal leaves the open conversation receiving messages, proven with a short token
      lifetime rather than by reasoning. — **proven in a test, not yet live.** The behaviour holds in
      `operatorConnection.test.tsx` (a renewal no longer produces a second connection at all, so the
      subscription it would have orphaned still exists), and the live half is the open item below.
- [x] Exactly one connection per operator tab exists in the registry after several renewals. — one
      connection is now built per provider mount and never replaced; the test asserts exactly one
      after four renewals, against four before.
- [x] `accessTokenFactory` reads the current token.
- [x] A frontend test covers the behaviour and fails against the current code. — six tests; four
      failed against `origin/main` and all six pass after.
- [x] The visitor side is checked and the result recorded. — not affected, with one thing to watch;
      see Outcome.

## Open questions

None. The choice between the two shapes is this item's own to make and record — see Outcome.

## Outcome

**The defect was a lost subscription, not a dead connection**, exactly as the reproduction detail
said. `oidc-client-ts` renews the access token on its own — `UserManager.automaticSilentRenew`
defaults to **true**, and `signinSilent` only reaches for a hidden iframe when there is *no* refresh
token to use; Keycloak's authorization-code flow returns one, so renewal happens off the refresh
token with no `silent_redirect_uri` and nothing to wire. `userManager.ts`'s note claiming silent
renew "is deliberately not wired up here" was true of the iframe plumbing and false about whether
renewal happens, and that is what let `5-06` and `5-07` both reason as though an access token never
changed after sign-in. The note is corrected in place.

Each renewal fired `userLoaded` → a new `user` → a new `access_token` → `useMemo`'s dependency
changed → a **brand-new** `OperatorConnection` whose subscription record was empty. Nothing re-joined
it: `resumeAfterReconnect` was correct but wired to `onreconnected`, which does not fire for a
connection that was never reconnected, and `ConversationPage`'s `joinedConversationId` guard —
correctly refusing to re-join a conversation it believed was already joined — was reset only by a
change of route param, not by a change of connection. So the thread went deaf while rendering
normally, and re-entering the conversation recovered it because that path calls `joinConversation`
on the current connection.

**Chosen: the connection survives the renewal** (the item's first shape). The token is not what
identifies a connection — the operator is, and the operator cannot change under a mounted provider
(a different `sub` only arrives via a Keycloak redirect, which is a full page load). So the memo has
no dependencies at all, and the token reaches SignalR through a factory reading the live value at
connect and reconnect time, which is what `accessTokenFactory` is for.

**Rejected: keep the rebuild and re-join from the new connection.** It fixes the reported symptom
while keeping the orphaned connections — a second, separately reported anomaly that turned out to
have the same cause — and it leaves the console permanently doing the most expensive thing available,
a full WebSocket teardown and negotiate, on a schedule set by Keycloak's token lifetime.

**Also done, and the more durable half:** `OperatorConnection` now names its subscription record
(`subscribedConversationId` + `SequenceTracker`) and has **one** replay path, `resumeSubscription`,
reached from every way this connection enters a connected state — `start()` and `onreconnected`
alike, rather than only the latter. Removing one cause of a connection coming back up empty is not
the same as covering them all, and "switched to another chat and back and it recovered" is what a
lost subscription looks like from *any* cause. A `stop()`/`start()` restart previously replayed
nothing; it now resumes from `lastKnownSequence` like a reconnect does. A failed replay after a
reconnect used to be an unhandled rejection that left the badge stuck on "reconnecting" forever; it
now logs and reports "disconnected", on the same judgement — the badge is the only channel that can
tell an operator their thread is not live, and a pessimistic badge over a live socket is a far
smaller harm than a healthy badge over a deaf thread.

**The bullet about stopping the replaced connection is answered by removal, not by machinery.**
Nothing replaces the connection any more, so there is no old connection to stop; the file says so
explicitly, and says that any future change reintroducing a dependency there owes it a `stop()`.

**Tests** — the first at `testing.md`'s new "Component / behaviour" level for this repository, which
also needed `vitest.config.ts`'s `include` widened to `.tsx` (the old glob predated that level
existing). `@microsoft/signalr` is faked; no new package was added — React 19's own `act` plus
`createRoot` in the already-configured jsdom environment are enough, so no testing-library
dependency. **Four of the six failed against `origin/main`**, including the headline one ("leaves the
open conversation still receiving messages": the message pushed to the live connection after a
renewal was dropped, because that connection's record was empty). All six pass after. Full suite:
91 tests green, plus `typecheck`, `lint` and `build`.

**The visitor side is not affected, confirmed rather than assumed.** `ago-widget` mints its visitor
token once via `getOrCreateVisitorSession` and stores it (thirty days, `17-03`); there is no OIDC
renewal path in the widget at all, and `VisitorConnection` is constructed once per page load. Worth
noting for `17-03`: the widget's `accessTokenFactory` also closes over a captured value, which is
harmless only because that token never rotates — the day rotation ships, it is the same defect.

**Left open: live verification.** Both remaining live checks — that messages keep arriving across a
renewal with a deliberately short `accessTokenLifespan`, and that the registry holds one entry per
tab after several — need a signed-in operator, and the session that did this work cannot sign in (it
cannot type a password into Keycloak's form). Nothing here was verified against a running stack, and
that is stated rather than papered over. The reasoning and the tests are what stand behind the
change today.
