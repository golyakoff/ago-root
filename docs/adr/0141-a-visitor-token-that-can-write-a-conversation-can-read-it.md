# ADR-0141: A visitor token that can write a conversation can read it

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-53`)

## Context

`23-53`: reopening the widget showed a returning visitor an empty transcript, even when their own
earlier messages and the operator's replies were still sitting in the same, still-open conversation on
the operator's screen. The actual defect was narrower than it looked - `ago-widget`'s
`VisitorConnection.start()` sent the browser's stored `lastKnownSequence` cursor on the very first join
of a fresh page load, the same cursor `resumeAfterReconnect` correctly sends to resume a *live*
connection whose DOM already holds everything up to it. A fresh page load's DOM holds nothing, so a
present-and-caught-up cursor answered with an empty delta into an empty screen - not stale, not
partial, exactly what `23-53`'s own report describes. The fix removes that cursor from the one call
where it never belonged; the server-side history read this depends on (`GetConversationHistoryHandler.
HandleAsVisitorAsync`, scoped by the signed visitor token's own `VisitorId` claim, never by anything a
caller supplies) needed no change and was already correctly scoped - `NoteLeakProofTests` (`18-04`) and
this item's own new tests prove an operator note and a real system event (an assignment) never reach it.

What is new is not a capability the token lacked - `sendMessage` already let anyone holding this
browser's stored token add to the transcript with no further proof - but the fact that *reading* now
exercises the same reach *writing* always had. Before this item, a second person at a shared device
could continue a conversation they had never seen; after it, they can read it too. `23-53`'s own
backlog item names this as one of two things the implementation must settle rather than leave implicit,
and offers two honest shapes: show it, on the reasoning that continuing already implies access; or
bound it to the current session, discarding anything from before the browser's current connection.

## Decision

**Show it.** A join request presenting a valid visitor token gets that conversation's own history,
exactly as `HandleAsVisitorAsync` already computed it before this item - no new bound tied to when the
current connection started, no distinction between "this session's own messages" and "everything this
token has ever been party to."

The reasoning is the token's own existing reach, not a new argument invented for this item: a bearer of
this browser's stored visitor token already has standing to write into this conversation with no
further proof (`VisitorHub.SendMessageAsync` checks nothing beyond the token), and already has standing
to keep it alive indefinitely by writing to it (`IConversationRepository.GetActiveForVisitorAsync` finds
the same conversation for as long as it stays open). A token that can extend a transcript is not a
weaker credential than one that can merely read it; bounding *reading* while leaving *writing*
unbounded would not close the shared-device exposure `23-53` names, it would only make the two
capabilities disagree about how much the same token is trusted with - a session-bounded reader sitting
down at the same browser could still write themselves into full visibility of everything before them by
sending one message and reading the conversation an assigned operator's reply then contains, so the
narrower option buys a delay, not a boundary.

## Consequences

- A shared device now shows more than it did: whoever next opens the widget on that browser reads the
  first visitor's own words and the operator's replies, not only the ability to add more. This is the
  exposure this item's own backlog item asked to be answered rather than discovered - answered here as
  "accepted, and bounded by the token's own existing lifetime and scope," not as an oversight.
- No new server-side check, no new column, no new endpoint. The scoping this decision leans on -
  `conversation.VisitorId == token's VisitorId`, nothing a caller can widen - already existed and is
  unchanged by this item.
- The exposure's actual bound is `docs/architecture/realtime.md`'s own token lifetime (`adr/0048`): as
  long as a stored token keeps renewing, the history it can read keeps growing with it. A shared device
  that is shared for a single conversation and never again carries this exposure only as long as the
  token itself is still on it, which `17-07`'s renewal already makes indefinite for a browser that keeps
  returning - a pre-existing property of the token, not a new one this decision introduces.
- History across devices is unchanged and out of this item's scope: the token is still per-browser, so
  this decision only widens what one already-trusted browser can see of its own conversation, never what
  a different device can see without presenting that same token.

## Alternatives considered

- **Bound history to the current connection - only messages sent since this `start()` call, or since
  this browser's session began.** Rejected: as argued above, it does not close the shared-device
  exposure, only delays it by one message-and-reply exchange, while adding a real cost this item's own
  Scope explicitly warns against - a second, narrower read model or a second cursor concept living
  beside `lastKnownSequence`, for a boundary the write path does not honour either. A guarantee that
  degrades to "buys a few seconds" under the first message sent is not a guarantee worth building a
  second mechanism for.
- **Require the visitor to re-prove something (a returning-visitor challenge, a short-lived second
  factor) before a join returns history older than the current connection.** Rejected as a materially
  larger feature than this item's own scope - `23-53`'s Out of scope names "history across devices" and
  a proof-of-continuity challenge is the same shape aimed at a single device, adding real UX cost (a
  visitor made to prove something to read their own words back) for a threat model (a stranger with
  physical access to an already-authenticated browser) `docs/architecture/personal-data.md`'s existing
  `visitors` row already accepts for every other capability the stored token carries.
