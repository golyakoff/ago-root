# 26-90 · Android has no analog of the console's admin "all conversations" page

- **Stage**: 26
- **Status**: done — merged as [ago-chat#359](https://github.com/golyakoff/ago-chat/pull/359) (backend
  contract) and [ago-android#82](https://github.com/golyakoff/ago-android/pull/82) (the tab itself).
  Real finding, reported not silently fixed: rows are not tappable — `OperatorHub.JoinConversationAsync`
  assigns before it reads, and `Conversation.AssignTo` accepts only a `Waiting` conversation, so a tap
  on this admin-wide list would incorrectly claim a queued conversation or throw for one assigned
  elsewhere/closed. Shipped with a quiet on-screen note; the real gap (a server-side read-only history
  for a `site:configure` holder without assigning) is named, not filed as its own item yet.
- **Found**: 2026-09-24, by the author — "у нас не хватает в разделе Диалоги аналога страницы
  `https://office.reserve-me.ru/conversations/all`. Администратор должен мочь видеть список диалогов,
  зайти в них, почитать историю диалога. Сейчас на этой странице можно даже удалить диалоги старые."
- **Verified/designed**, 2026-09-24 — three rounds with the author (a throwaway local sketch, refined
  against real feedback three times) settled the logic; a design pass then added it to the real mockup
  and found three real gaps between that design and the current server code (below). **One promise**:
  an administrator sees and manages every conversation on the site from their phone, the way they
  already can from the console.

## Design reference

<https://claude.ai/code/artifact/8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3>, section "02 · Диалоги", the two
frames added after "Список диалогов": the one tagged **"Новая вкладка"** (the list itself, with a row
mid-swipe) and the one after it, **"фильтр по статусам"** (the panel open). Both are drawn on the
artifact's own tokens and icon sprite; they are the contract for layout and copy, not this file's prose.

## Scope

**`ago-chat`** — the list this tab reads does not carry what the design shows:

- `GetAllConversationsForSiteHandler.ToSummary` builds `ConversationSummaryDto` without
  `LastMessagePreview`/`LastMessageAt`. Both fields already exist on the record and
  `GetOperatorQueueHandler`'s two lists populate them; populate them here too, inside
  `IConversationReadStore.GetAllForSiteAsync`'s own query — not in memory after the page, for the
  reason that method's own remarks already give about `18-04`'s tag filter.
- No "total messages in this conversation" value exists anywhere in the contract. Add one to
  `ConversationSummaryDto` and to `GetAllForSiteAsync`. It is a total, never an unread count —
  `OperatorUnreadCount` keeps its present meaning and is not reused for this.
- `GET /api/v1/conversations/all` takes `beforeId`/`pageSize`/`tag` and has no state filter. Add a
  repeatable `state` query parameter pushed into SQL: the list is keyset-paginated, so a page of 50
  filtered client-side can legitimately come back empty.
- Add no count endpoint, no total, no per-state tally (see Out of scope).

**`ago-android`** — the tab:

- A third segment "Все" in the Диалоги segmented control, rendered **only** when the operator holds
  `site:configure` — the permission `GetAllConversationsForSiteHandler` actually enforces, not
  `conversation:read`. Without it the control stays two segments; never a greyed-out third one (the
  same "hide, don't disable" rule the thread screen's attachment button already follows).
- Rows are the existing conversation-row composable, not a table. Lines one and two are unchanged:
  identity + time since the conversation was created, then last-message preview + time since that
  message. The third line is the new part — a status pill on the left (**Не начат** for `Waiting`,
  **Назначен: {OperatorName}** for `Assigned`, **Закрыт** for `Closed`, read off
  `ConversationSummaryDto.State`) and `Сообщений: N` on the right, in the second line's own weight and
  colour. No unread badge on this tab.
- Newest-first, keyset paging on scroll via `beforeId`.
- A status filter: a chip under the segmented control opening an anchored panel of three checkboxes —
  Не начат / Назначен / Закрыт. Default: the first two on, **Закрыт off**. The checked set becomes the
  `state` parameter of the request.
- Swipe-left on a row reveals one destructive action, shown only to a holder of `conversation:erase`:
  a large icon over a two-line `Удалить` / `диалог` caption on `--danger`, nothing else. The icon is
  Material Symbols "delete_forever" in shape (a bin with a large X, not the three-line bin) but
  **redrawn** in `AgoIcons.kt`'s own stroke idiom — one family, 1.8 width, round caps and joins. The
  artifact's `#i-trash-forever` symbol is the reference geometry.
- `POST /api/v1/conversations/{conversationId}/erase` answers **`202 Accepted`**
  (`RequestConversationErasureHandler`): erasure is a request, carried out later. The row must not
  disappear optimistically, or it reappears on the next page and reads as a bug. Settle and write down
  the behaviour — a confirmation, then the row held in an "erasing" state until it stops coming back —
  before writing the screen, not during.

## Out of scope

- **Any count, anywhere on this tab**: no per-status tally in the filter, no total on the "Все"
  segment, no badge on the filter chip. Decided by the author, 2026-09-24, against a live site with
  tens of thousands of closed conversations — it is a `COUNT(*)` over the whole history on every open,
  for a number nobody acts on.
- Opening a conversation from this tab: it is the existing thread screen, unchanged. No admin-only
  read-only variant.
- Changing who may erase, or making `conversation:erase` separately grantable. It is bundled into the
  admin set by `RegisterSiteHandler`/`MintDemoTenantHandler` alongside `site:erase`/`site:export`, and
  stays that way.
- The tablet/wide layout for this tab, and the console's own `/conversations/all` page.

## Done when

- [ ] `GET /api/v1/conversations/all` returns `LastMessagePreview`, `LastMessageAt` and a total message
      count per row, and accepts a repeatable `state` filter applied in SQL — proven by an integration
      test paging a site holding a mix of `Waiting`/`Assigned`/`Closed`.
- [ ] "Все" appears as a third segment for an operator holding `site:configure` and the control stays
      two segments for one who does not — asserted in a test, not only by eye.
- [ ] A row renders the three lines of the artifact's "Новая вкладка" frame, with `Сообщений: N` as a
      total and no unread badge.
- [ ] The status filter is three checkboxes defaulting to Не начат + Назначен on / Закрыт off, and
      changes the request rather than filtering an already-fetched page. No number appears in the
      panel, on the chip, or on the segment.
- [ ] Swipe-reveal delete exists only for a holder of `conversation:erase`, uses the redrawn
      stroke-style `delete_forever` icon with the two-line caption, and its post-`202` behaviour is the
      one written into Scope above — never an optimistic removal.
- [ ] `dotnet format`/`build`/`test` (ago-chat) and `./gradlew ktlintCheck lint test` (ago-android) both
      green, re-run and counted by the managing session.
- [ ] If implementation departs from the artifact, the artifact is updated in the same change — its
      transition graph already records "Все" as a tab of `ConvList` rather than a separate
      `site:configure`-gated screen.
