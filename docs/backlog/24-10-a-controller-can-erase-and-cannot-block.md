# a tenant can suspend processing of one person's data without destroying it

- **Stage**: 24
- **Status**: done (2026-09-06)
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

- [x] A blocked conversation is unreachable from every operator-facing read path — asserted per path,
      because the failure mode is one read that was not updated.
- [x] A blocked conversation is excluded from a tenant export.
- [x] Unblocking restores exactly the prior state, and both acts are recorded.
- [x] Neither doc still says "no mechanism".

## Open questions

- **Does a blocked conversation still receive inbound messages?** A visitor writing from a channel does
  not know they are blocked. Refusing silently, refusing visibly, and accepting-into-the-block are three
  different products and this decides one of them.
- **Whether "block" is one state or two** — hidden from operators versus frozen against all processing.
  Deciding this is most of the work; `24-06`'s own finding does not decide it.

## Outcome (2026-09-06)

`adr/0124` carries both decisions the item left open. Recorded here: how the read paths were found,
and what is honestly not closed.

**The Done-when that mattered was "asserted per path, because the failure mode is one read that was
not updated."** So the paths were enumerated from the code *before* any production line was written.
The enumeration found **eleven**, of which the brief had named six. The five it had not:

- `GetOperatorQueueHandler` — the console's own queue and dashboard.
- `ConversationSearchStore` — full-text search.
- `ExportConversationHandler`/`ExportVisitorHandler` — `24-11`'s subject-access exports, which reuse
  two read-store methods and were therefore closed by fixing those.
- `WaitingConversationClaimQuery` — not a read at all, but the mechanism for "not routed".
- `SendOfflineAutoReplyHandler` — the mechanism for "not auto-replied".

That is the argument for enumerating rather than asserting: a mechanism described once would have
shipped with search and the operator's own queue still showing a blocked conversation.

**Eight of thirteen guards were individually disproven, and the report says which five were not.**
The five are the identical pattern applied to sibling read stores. Stating that distinction is the
point — "all thirteen were proven" would have been the easy sentence and the false one.

**What is not closed, and is not hidden.** Write paths beyond auto-reply and auto-assignment are not
frozen: closing, assigning, transferring, setting an outcome, adding a note, and the realtime push to
an operator's already-open tab. A blocked conversation cannot be *found* through any discovery path,
so this bites only where an operator already held the id — but that is a consequence of scoping the
work to reads, not a guarantee the mechanism makes. `adr/0124` names it in its own Consequences.

**No console screen.** The comparable precedent was measured rather than guessed:
`EraseConversationButton.tsx` plus its poll hook and tests come to roughly 500 lines for one
button-and-poll pattern. A Block/Unblock pair is comparable — "substantial" by this item's own test —
so the backend was built in full and the console left for its own number.

**The repeated predicate is the thing to watch.** `blocked_at IS NULL` is written by hand in about a
dozen queries and nothing enforces that a future read remembers it. That is the same failure mode
`24-06` found for blocking's total absence, one level down, and it is named in the ADR rather than
left for somebody to rediscover.
