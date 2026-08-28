# Returning-visitor history

- **Stage**: 18
- **Status**: ready
- **Depends on**: `18-06-auto-close-inactive-conversations.md` — not architecturally (the data already
  exists without it), but closing conversations automatically is what makes a returning visitor with
  *multiple* past conversations a routine case instead of a rare one; build this after so there is
  real history to show, not an empty state nobody will believe

## Goal

An operator opening a conversation with a visitor who has a `channel_identity` (MAX, Telegram, SMS —
not an anonymous widget session, see below) can see that this person has talked to the shop before, and
open what was said. Without this, `18-06` privately keeps every prior conversation's data intact but
delivers none of its value to the person who would actually use it — a phone number AGO has recognized
for a year is worth nothing to an operator who cannot see that recognition happened.

## Context to read first

`docs/backlog/14-01-external-channel-identity-and-inbound-port.md` — `ChannelIdentity` maps an
external identifier to a `Visitor`; this item's whole premise is that mapping being durable and
`visitor_id`-scoped, unlike a widget visitor (see Out of scope).

`Ago.Chat.Infrastructure.Postgres/ConversationReadStore.cs`'s `GetAllForSiteAsync` — the closest
existing query, but it is the **admin's** every-conversation-for-a-site read (`5-08`), unfiltered by
visitor and not operator-scoped. This item needs its own read: every conversation (any state, most
recent first) for one `visitor_id`, callable by the operator currently assigned to *a* conversation
with that visitor — not every operator at the site, matching `adr/0016`'s existing per-conversation
permission split (`ConfirmAttachmentHandler.HandleAsOperatorAsync`'s own "RBAC answers may this
operator act at all, a per-conversation comparison answers on this one").

`docs/architecture/personal-data.md` — a visitor's message history *is* the personal data this doc
already has to account for; this item is a new read path over data that document should already list,
not new data. If it introduces a genuinely new way personal data becomes visible (an operator seeing a
year-old conversation they were never part of), say so there in the same change, since `16-01`/`16-02`'s
erasure guarantees have to keep covering it.

`ago-console/src/workspace/ConversationList.tsx`'s own doc comment (`11-06`) — the "Assigned to me" /
"Waiting" split this feature sits next to; a history panel is a third, clearly different kind of list
(past, not current; not live, not actionable the same way) and should not visually imply either of the
existing two.

## Scope

- A new read (`Ago.Chat.Application`, backed by `ConversationReadStore` or a sibling query): given a
  `visitor_id`, every past conversation for that visitor, ordered most recent first, each with enough
  to render a summary (state, started/closed timestamps, first or last message preview).
- An endpoint an operator can call from within a conversation they are assigned to, scoped by the
  per-conversation permission check named above — not a general "look up any visitor" search, which is
  `18-01`'s job if it is ever wanted.
- Console: a panel on the conversation view showing this visitor's prior conversations (if any),
  openable read-only — reusing `11-06`'s existing history-rendering rather than a second message-list
  component.
- Gated on the conversation actually having a `channel_identity` behind its `visitor_id` — a widget
  visitor with no such identity has no history to show and the panel should not appear at all, not show
  an empty state that implies one could exist.

## Out of scope

- Widget (anonymous) visitors. Point 1 of the discussion that opened this item stands: a returning
  widget visitor cannot be recognized at all today, so there is nothing this item can show for one —
  building UI for a case that cannot occur would be exactly the kind of untested, unreachable code
  `CLAUDE.md` already rules out.
- Cross-site history. A visitor's `channel_identity` is scoped to one `Site` already (`14-01`); this
  item does not change that boundary or search across tenants.
- Full-text search over history — `18-01`.
- Editing, annotating, or acting on a past conversation from this panel. Read-only, matching its own
  Goal.

## Done when

- [ ] An operator on a conversation with a channel-identified visitor sees a list of that visitor's
      prior conversations, most recent first.
- [ ] Opening one shows its real message history, through the existing history read path.
- [ ] A widget-only visitor's conversation shows no such panel — proven with a test, not left implicit.
- [ ] The permission scoping (assigned-to-this-conversation, not site-wide) is proven with a test that
      shows a different operator at the same site cannot pull it for a conversation they are not on.
- [ ] `docs/architecture/personal-data.md` reflects this new read path if it changes what that document
      already has to say.

## Open questions

None — the shape follows directly from `14-01`'s existing identity model; if that model turns out not
to support this cleanly once someone is inside the code, that is a note on `14-01`, not an open question
here.
