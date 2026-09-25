# ADR-0182: A visitor's own conversation history is scoped per-visitor-on-site, not by channel identity

- **Status**: Accepted
- **Date**: 2026-09-25
- **Stage**: 26 (`26-114`, implementing `26-111`'s design)

## Context

`18-07` built an operator's "has this person talked to us before" panel — `GetVisitorHistoryHandler`,
backed by `GET /api/v1/conversations/{id}/visitor-history`. Its access rule was, and remains, "an
operator assigned to a live conversation with this visitor may see that visitor's other conversations on
this site." But before this item, a second gate sat in front of that rule: a short-circuit that returned
an empty, explicitly-gated result (`HasChannelIdentity: false`) for any visitor with no
`ChannelIdentity` row at all — `14-01`'s structural model for a widget-only visitor, one who has never
been heard from on SMS/MAX/Telegram/WhatsApp/VK/Avito/email.

`26-111`'s design pass for the Android contact-detail panel (`docs/design/26-111-thread-contact-detail-panel.md`,
GAP-3) named the actual cost of that gate: **most** AGO Chat visitors are widget-only — the product's
primary channel is the embeddable widget itself, with the other channels added later as `AGO Inbox`
extensions (`docs/roadmap.md` Stage 14). For most conversations, "Прошлые диалоги" therefore always read
empty and never opened — a mockup element that is dead for the common case, not a rare edge. The
author's own decision (`26-111`'s "Author decisions" §3) was to widen the read rather than accept a
panel row that is usually inert: *"the row lists this visitor's other conversations on this site, so it
is never dead."*

This is deliberately an authorization-boundary change, not a query tweak: before this item, a widget-only
visitor's other conversations were **unreachable** by this read path, full stop, regardless of who was
asking. After it, the same operator who could already open any one of those conversations directly
(`conversation:read`, scoped to the site) can also see that they exist and skim their previews from this
panel. The question this ADR answers is whether that widening is sound, and what it changes.

## Decision

**Drop the channel-identity short-circuit in `GetVisitorHistoryHandler.HandleAsOperatorAsync`.** Every
visitor now reaches the identical `IConversationReadStore.GetVisitorHistoryAsync` read this method always
had, scoped by `VisitorId` alone. Nothing about that query's own SQL changes — it was never itself gated
on channel identity; the gate lived one layer up, in the handler, as a call to
`IChannelIdentityRepository.FindMostRecentForVisitorAsync` before the read ever ran. Removing that call is
the entire mechanical change.

**The real authorization boundary does not move.** It was never "does this visitor have a channel
identity" — that was a *scoping* decision about which visitors the feature applied to, not a *security*
decision about who could read what. The security boundary has always been, and remains: RBAC's
`conversation:read` for this site (`adr/0016`), and the per-conversation check that the requesting
operator is assigned to *some* live conversation with this same visitor
(`GetVisitorHistoryHandler`'s own remarks explain why this, not a stranger's own historical assignment,
is the check that matters). An operator who could not already open a widget-only visitor's other
conversation one at a time gains nothing new here; an operator who could, now also sees that it exists
without having to already know its id.

**`26-114` also adds a sibling read, `GET /api/v1/conversations/{id}/visitor-summary`**
(`GetVisitorSummaryHandler`), returning `visitorFirstSeenAt` and `conversationCount` — this visitor's
distinct conversations on this site, **including** the one currently open. It shares the identical
two access checks and the identical underlying scope (`IConversationReadStore.GetVisitorSummaryAsync`
applies the same `blocked_at is null` predicate `GetVisitorHistoryAsync` does), so the header count and
the list beneath it always agree once the current conversation is accounted for
(`count == historyList.Count + 1`) — one scoping decision, read twice, rather than two independently
written queries that could drift apart. This is a new capability, not merely the widening of an old one;
it is included in this ADR because it reads the same widened, per-visitor-on-site scope this decision
establishes, for a visitor who previously had no summary at all (`docs/design/26-111-*.md`'s GAP-1/GAP-2).

**The wire contract loses `VisitorHistoryResponse.HasChannelIdentity`.** The field existed only to carry
the now-removed gate to the console, so a caller could render "no panel" (structurally impossible) apart
from "an empty panel" (possible, simply empty right now). That distinction no longer exists to report —
every visitor's history is now the second case, or a real list. A console still reading the old field
needs its own follow-up change; that follow-up is not built by `26-114` (backend-only, per that item's
own Depends-on) and is named as a known consumer to update, not as work this ADR performs.

## Consequences

**Positive.** The panel's own reason for existing — "has this person talked to us before" — now answers
truthfully for the majority of AGO Chat's traffic (widget-only visitors), not only for the minority who
happen to have also messaged through a linked channel. The count and the list are provably the same
scope, by construction, rather than by two SQL statements that started identical and could silently
diverge on a future edit. No schema or migration is needed — `visitors.first_seen_at` and every column
`GetVisitorHistoryAsync`/`GetVisitorSummaryAsync` read already existed; this is a widened predicate and
one new read, not a new fact stored.

**Negative.** This is a genuine widening of what one operator's own past assignment can surface about a
visitor: previously, a widget-only visitor's earlier conversations were invisible to this exact read path
no matter who asked; now they are visible to whichever operator happens to hold the current one, subject
to the unchanged per-conversation check. `docs/architecture/personal-data.md`'s `18-07` row is updated in
this same change to state the widened boundary, since that file already tracks this exact
cross-conversation-history read as the "genuinely new way a message becomes visible to an operator who
was never a party to the conversation that contains it" — the class of fact this document exists to make
loud. No new access-record write accompanies the widening: the existing design already treats the
*summary list* (previews only) as not itself a boundary-crossing read — only *opening* a specific
historical conversation's real messages writes an `access_records` row (`24-12`, unchanged by this item),
and that write's own precondition (assigned to a live conversation with the same visitor) is identical
for a widget-only visitor and a channel-identified one. A console consumer of the removed
`HasChannelIdentity` field needs a follow-up change to keep rendering correctly (it should show the row
unconditionally now); that follow-up is out of this item's own scope.

## Alternatives considered

**Keep the gate, and give widget-only visitors nothing (`26-111`'s own Q5 Option B).** Rejected by the
author: it costs nothing to build but leaves the mockup's own «Прошлые диалоги» row dead for most
conversations, which is the exact regression `26-111`'s design pass surfaced rather than silently
designed around.

**Widen the read but keep `HasChannelIdentity`, redefined to mean something else** (e.g. always `true`,
or "this visitor has any prior conversation"). Rejected: a field whose name promises information about
channel identity while actually meaning something unrelated is a worse API than removing it — a future
reader would have to discover the redefinition by reading the handler, exactly the kind of stale-name
trap this codebase's own conventions warn against. Removing it is honest about what changed.

**Fold `visitor-summary` into `ConversationSummaryDto`** (the queue row), rather than a new endpoint
(`26-111`'s own §5-Q3 Option B). Rejected for the reason that design document already gives: the queue
DTO is polled and paginated, and a per-visitor fact only the currently-open thread needs does not belong
riding along on every row of a screen that lists many conversations at once.

**Record an `access_records` row for the widened list read too**, on the theory that "more visitors can
now reach this" should mean "log more." Rejected: the list already returns only thin previews under the
identical two access checks a channel-identified visitor's list always used, and `24-12`'s own design
already drew this exact line — a summary list is not the boundary-crossing event, opening one historical
conversation's real messages is. Widening *who* can reach the list does not change *what kind* of read it
is.
