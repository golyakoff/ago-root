# Fix: renewing the access token silently stops the open conversation receiving messages

- **Stage**: 5 — `OperatorConnection` and its provider are `5-07`'s, and this is a defect in them
- **Status**: ready
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
      lifetime rather than by reasoning.
- [ ] Exactly one connection per operator tab exists in the registry after several renewals.
- [ ] `accessTokenFactory` reads the current token.
- [ ] A frontend test covers the behaviour and fails against the current code.
- [ ] The visitor side is checked and the result recorded.

## Open questions

None. The choice between the two shapes is this item's own to make and record.
