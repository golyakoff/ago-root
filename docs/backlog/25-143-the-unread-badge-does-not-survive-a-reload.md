# 25-143 · The unread badge does not survive a reload

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-18. `25-141` built the closed-launcher unread badge in-memory only, because the
  widget never fetches message history before the panel opens (`connect()`, the only thing that
  fetches history, is only ever triggered by opening it - eagerly connecting on every page load would
  start a real conversation for every visitor who never engages, which `adr/0148`'s lazy-connect design
  exists to avoid). The author's own decision, asked directly and answered immediately: build a
  lightweight REST endpoint instead of changing the connect timing.
- **Depends on**: `25-141` (done, `ago-widget#96`).

## Scope

One new **read-only** endpoint on `Ago.Chat.Api`: given an existing `conversationId` (the widget
already has one in `WidgetStorage` for a returning visitor - a brand-new visitor has no conversation
and nothing to check, so the widget simply skips the call), return the count of messages with
`authorKind != Visitor` newer than a given sequence.

**Must not go anywhere near `JoinCoreAsync`** - `VisitorHub.JoinAsync`'s own doc comment states it
"starts or resumes the visitor's conversation," which is exactly the side effect this endpoint must
not have. This is a plain read against an existing conversation's own messages, the same shape
`Ago.Chat.Application`'s read side already uses elsewhere - find whatever the closest existing
"read a conversation's messages" query is (there is very likely one behind the console's own
transcript view) and give it a visitor-facing, count-only sibling rather than inventing the read path
from scratch.

On the widget side (`ago-widget`):
- A new `WidgetStorage` key, `last-read-sequence` (per conversation, following the exact
  `WIDGET_STORAGE_DISCLOSURE` convention `has-known-contact-detail` used for `25-136`) - advanced to
  the latest sequence whenever `open()`/`openForAutoGreeting()` clears the badge, the same two places
  `25-141`'s in-memory `unreadCount` already resets.
- On page load, before the panel opens, if a `conversationId` exists in storage: call the new endpoint
  with the stored `last-read-sequence`, and seed `unreadCount`/the badge from its answer instead of
  starting at zero.
- No change to `connect()`'s own timing - this is additive, a call this endpoint makes possible
  without touching when the hub connects.

## Where this is likely to go wrong

- The endpoint is visitor-facing, so it needs the same auth/tenancy check every other visitor-facing
  read already has - a visitor must only ever be able to ask about their own conversation, never an
  arbitrary id. Reuse whatever check the widget's existing REST calls (contact-capture submission,
  etc.) already go through rather than inventing a new one.
- Don't let this become a second source of truth for "read" that can disagree with the live
  in-memory count `25-141` already built for the same page load - `last-read-sequence` is what seeds
  the badge on load; once seeded, `25-141`'s own live increment/reset logic keeps it current for the
  rest of that page's life unchanged.

## Done when

- [ ] A visitor who received messages while the tab was closed sees the correct count on the next
      page load, before opening the panel
- [ ] A brand-new visitor (no stored conversation) makes no extra call and shows no badge
- [ ] The endpoint never starts or resumes a conversation - a read against a conversation the visitor
      never returns to has no side effect at all
- [ ] A visitor cannot query another conversation's unread count
