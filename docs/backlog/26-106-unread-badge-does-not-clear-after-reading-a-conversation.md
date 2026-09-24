# 26-106 · The unread-count badge does not clear after opening and reading a conversation

- **Stage**: 26
- **Status**: done — merged as [ago-android#102](https://github.com/golyakoff/ago-android/pull/102).
- **Found**: 2026-09-25, by the author on a real device — the purple unread-count bubble on a
  conversation row (e.g. «Птица · Бургер» showing «1») stays for a long time after the operator opens
  that conversation and reads the message; it does not clear promptly on read.

## What is actually true today (to confirm against the code)

Opening a conversation and reading its messages should drop that row's unread count to zero in the
list. On device the badge persists well after the thread was opened and read. Likely area:
`ago-android` `conversations/ConversationListViewModel.kt` / the conversation-row unread rendering, and
the read-marking path. Note `26-80` ("opening a conversation never tells the server it was read")
covers the *server* read-receipt; this item is about the **client-side badge not clearing** after a
read — confirm whether the local list state is updated on read (optimistically and/or from the
server's own unread-count update), and whether `26-63`'s incremental-update work interacts with it.

## Scope

- `ago-android`: when the operator opens a conversation and its messages are read, the row's unread
  badge clears promptly (optimistically on open/read, and reconciled with the server's unread count),
  and does not reappear on the next queue refresh unless genuinely unread again.
- Confirm the interaction with `26-80` (server read-receipt) and `26-63` (per-message incremental list
  update) so the badge reflects the true read state after both.

## Out of scope

- The server-side read-receipt mechanism itself (that is `26-80`), except where the client must
  consume its result to clear the badge.

## Done when

- [x] Opening a conversation and reading its messages clears that row's unread badge promptly, proven
      by a unit test on the list view-model's unread state.
- [x] The badge stays cleared across a subsequent queue refresh (does not flicker back) unless a new
      unread message actually arrives.
- [x] `./gradlew ktlintCheck lint test` green.
- [~] Verified on a real device (badge clears on read, does not linger). — delivered and CI-green (build/unit/ktlint/lint); on-device check pending, phone disconnected 2026-09-25.
