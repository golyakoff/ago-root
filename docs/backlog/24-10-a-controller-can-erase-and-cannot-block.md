# a tenant can suspend processing of one person's data without destroying it

- **Stage**: 24
- **Status**: ready
- **Depends on**: `16-02` (shipped — the erasure this sits beside)
- **Decision**: `docs/adr/0076-*` — the tenant is the controller; AGO builds the mechanism

## Goal

A tenant instructed to stop processing a particular person's data, but not to destroy it, has
something to invoke.

## What is actually true today, verified 2026-09-05 (`24-06`)

There are exactly two states for a conversation's personal data: processed normally, or gone.
`conversations.erasure_requested_at` (`Stage16AddErasureRequestedAt`) marks a row for
`ConversationErasureJob`; there is nothing between. Nothing hides a conversation from operators while
retaining it, nothing suspends its inclusion in exports, reports or the visitor-history read
(`18-07`), and nothing marks a `visitor_contact_details` row unusable without deleting it.

The statutory operation list that a processing instruction enumerates includes blocking as a distinct
operation from destruction. `processing-instruction-facts.md`'s Element 2 records the answer as **"no
mechanism"**, which is honest and is why this item exists.

## Why this is a gap rather than an oversight

`16-02` was scoped from the product question — "delete my data" — and answered it completely. The
statutory operation list is a different list, and nobody had put the two side by side until `24-06`
did. That is also why the gap is invisible from inside the product: every screen that would show a
blocked state does not exist, so nothing looks missing.

It is a real gap rather than a theoretical one because blocking is what a controller reaches for
precisely when they *cannot* delete — an unresolved dispute, a retention obligation pulling the other
way — which is exactly when getting it wrong is expensive.

## Scope

- A per-conversation (and, where it makes sense, per-visitor) blocked state that is honoured
  everywhere the data is read: the console, the analytics reads, exports, and `18-07`'s cross-
  conversation history.
- Reversible, and recorded — who blocked, when, on what request.
- Blocking must **not** silently become deletion, and must not be a second name for the erasure queue.
- `personal-data.md` and `processing-instruction-facts.md` Element 2 updated: the operation stops being
  "no mechanism".

## Out of scope

- Deciding whether a given tenant is ever obliged to block. Their lawyer's.
- Any bulk or site-wide block. A whole site already has `SiteErasureJob` and a subscription lifecycle;
  this item is about one person.

## Done when

- [ ] A blocked conversation is unreachable from every operator-facing read path — asserted per path,
      because the failure mode is one read that was not updated.
- [ ] A blocked conversation is excluded from a tenant export.
- [ ] Unblocking restores exactly the prior state, and both acts are recorded.
- [ ] Neither doc still says "no mechanism".

## Open questions

- **Does a blocked conversation still receive inbound messages?** A visitor writing from a channel does
  not know they are blocked. Refusing silently, refusing visibly, and accepting-into-the-block are three
  different products and this decides one of them.
- **Whether "block" is one state or two** — hidden from operators versus frozen against all processing.
  Deciding this is most of the work; `24-06`'s own finding does not decide it.
