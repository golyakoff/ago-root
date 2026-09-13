# ADR-0168: A visitor restriction is keyed to the visitor, checked at conversation creation, and carried by a second flag rather than reusing `BlockedAt`

- **Status**: Accepted
- **Date**: 2026-09-14
- **Stage**: 23 (`23-69`, `23-77`)

## Context

`24-10` gave an operator a real block, but keyed it on `(ConversationId, SiteId)`. Two independent
items found the same gap from opposite directions: `23-69`'s "close as spam" wants to auto-mute the
*visitor* for a window, and `23-77` found that `24-10`'s own block does not stop the same visitor's
*next* conversation at all — "as a block on a person it is decorative." A visitor identity is free to
mint (deliberately, per `23-77`'s own reasoning about IP addresses), so a mechanism that cannot see a
visitor's next conversation cannot make good on the word "block."

Both items were answered together, in dialogue with the author, 2026-09-13: one new table,
`visitor_restrictions`, keyed `(SiteId, VisitorId)`, additive to `24-10` rather than a repurposing of
it. This ADR records the two mechanical choices that decision still left open — where the check lands,
and how a restricted visitor's new conversation is kept silent — because both are guarantees a reviewer
would otherwise have to reverse-engineer from the code.

## Decision

**1. The check runs once, in `StartConversationHandler`, at the moment a genuinely new conversation
would be created** — alongside the handler's own pre-existing `GetActiveForVisitorAsync` read, not a
new pattern. A visitor's *already-open* conversation is never re-checked; both items' own scope is "the
next conversation", not the current one, and `IsActiveAsync`'s own fresh-every-time read means a mute
that has since expired, or a block that has since been lifted, is never enforced against stale
information — no background sweep is needed to "notice" either.

**2. Silence is real, not simulated.** `StartConversationHandler`'s response is not special-cased for a
restricted visitor — no error, no altered shape, no different `IsNew`. Instead, `Conversation.Start`
gains a second, honest flag, `RoutingSuppressedAt`, stamped only when the visitor already carries an
active restriction. A routing-suppressed conversation is otherwise ordinary: `Waiting`, it accepts and
stores the visitor's own messages exactly like any other (`AddVisitorMessage` never inspects this flag),
and it is excluded from exactly two places — `WaitingConversationClaimQuery`'s dispatch and
`GetOperatorQueueHandler`'s own queue view — the same two guarantees `24-10`'s `blocked_at` already
gives, extended rather than duplicated.

**3. `RoutingSuppressedAt` is deliberately not `BlockedAt`/`BlockedBy`.** That pair's own invariant is
"a named operator decided to block this one conversation." Nobody decides anything at the moment a
new conversation is silently suppressed — a restriction created earlier, possibly against a different
conversation, is only being carried forward. Reusing the pair would force either a fabricated operator
attribution or a `BlockedAt` set with `BlockedBy` null, a case `IsBlocked`'s own three years of callers
never had to consider. A second nullable column is cheaper than that ambiguity.

## Consequences

**Positive.** Both items are enforced by the identical mechanism a reviewer can check in one place
(`IVisitorRestrictionRepository`), not two parallel ones. `24-10` is untouched — no existing behaviour,
test, or permission changes. The silence guarantee is provable by asserting the response shape, not by
trusting a code path never to leak a distinguishing error.

**Negative.** Two routing gates now exist on the same aggregate (`IsBlocked`, `IsRoutingSuppressed`),
and any future "must an operator never see this" read has to remember to exclude both — the exact
duplication risk `24-10`'s own single-flag decision (ADR-0124) tried to avoid, now reintroduced for a
different reason. `GetConversationHistoryHandler`/`GetVisitorHistoryHandler`/the offline auto-reply
deliberately still treat a routing-suppressed conversation as ordinary content — an operator who
searches for it, or the visitor's own history panel, can find what routing silently withheld. That is a
scope choice, not an oversight: nothing in either item asks for the conversation to be unfindable, only
unrouted, and narrowing further would have meant editing three more read paths this change did not
need to touch. `visitor_restrictions` rows are not yet drained by `16-02`'s own erasure cascade — flagged
in `personal-data.md` rather than fixed here.

## Alternatives considered

**Reuse `IConversationBlockRepository`/`conversations.blocked_at` for the new mechanism.** Rejected
outright by the author's own dialogue: that table's key cannot express "this visitor", only "this
conversation", and widening it would repurpose a shipped, tested mechanism rather than add beside it.

**Refuse the request** (a `4xx`) when a visitor is restricted, instead of silently succeeding.
Rejected: both items' own answered "no message to the visitor" requirement (`23-77`: "тихо, без всяких
оповещений") rules out any response shape a client-side script could distinguish from success.

**A fourth `ConversationState`** (e.g. `Suppressed`) instead of a second boolean flag. Rejected: it
would touch the state machine's own closed vocabulary and every switch over it, for a distinction that
is orthogonal to `Waiting`/`Assigned`/`Closed` — a suppressed conversation is still, mechanically,
`Waiting`.
