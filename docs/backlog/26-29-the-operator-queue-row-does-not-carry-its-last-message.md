# 26-29 · The operator-queue row does not carry its last message, so no client can show one

- **Stage**: 26
- **Status**: done — merged as `ago-chat#355`, independently verified by the managing session
  (`dotnet build -c Release` 0 warnings/errors, `dotnet format --verify-no-changes` clean, full suite
  3982/3982 passed per-project: Domain 791, Application 1512, Architecture 53, FakeCrm 21, Concurrency
  90, Integration 1515, FakeMax empty).
- **Found**: 2026-09-22, by the author, comparing the real `ago-android` conversation list against the
  approved mockup. Two of his notes land on the same missing data: "Не хватает обрезанной последней
  строчки диалога второй строкой (под именем)", and "Время - это время создания чата? но мне кажется,
  что это бесполезная инфа - надо смотреть время последнего поста в чате? ... Тогда у нас будет
  некоторая консистентность - последние слова в диалоге и время этих последних слов."

## What is actually true today, confirmed against real code

`ConversationSummaryDto` (`src/Ago.Chat.Contracts/ConversationSummaryDto.cs`) is the wire row for
`GET /api/v1/conversations/queue`, and it is the row both the console's queue and the Android
conversation list render from. Its full field list today:

```
ConversationId, VisitorId, State, CreatedAt, OperatorUnreadCount,
OperatorId, OperatorName, HasAttachmentUploadGrant, AttachmentUploadGrantedAt,
AttachmentUploadGrantedByOperatorId, EmojiCreature, EmojiFood, VisitorName
```

**There is no last-message text and no last-message timestamp on it.** `CreatedAt` is the
conversation's own creation instant, and it is the only time value a client has — which is why both
the console (`ConversationList.tsx`, `strings.queueOpenLabel` + `formatElapsed(started, now)`) and
Android (`ConversationListScreen.elapsedText(row.createdAt, ...)`) render age-since-creation. The DTO's
own header says so deliberately: "deliberately thin (no message body, no full history) since the queue
view lists conversations, it does not read them."

`26-23`'s own report already named the snippet as a gap it could not close, for exactly this reason,
and was right to: that item was presentation-only and may not invent data. This item is the backend
half it was waiting for.

A `LastMessageAt` does already exist elsewhere — on `OwnerSiteSummaryDto` (`OwnerSitesResponse.cs`) —
which is a different aggregation (a site's own most recent activity) and not reusable here.

## Scope

One promise: **a queue row knows what its last message said and when it was said.**

Two additive, nullable fields on `ConversationSummaryDto`, following the same additive-only rule every
optional field already on that record follows (`api-design.md`):

- a short plain-text preview of the conversation's most recent message,
- that message's own timestamp.

### How it must be read

`GetOperatorQueueHandler` loads full `Conversation` aggregates, and `Conversation.Messages` is an EF
navigation. **Do not reach for it.** Materialising every message of every queued conversation to read
the last one of each is an unbounded read on a hot screen the console polls. `IConversationReadStore`
(`Application/Abstractions/IConversationReadStore.cs`) is the project's own place for exactly this —
a Dapper read-model query (`adr/0004`) — and already carries siblings of this shape
(`GetUnreadCountAsync`, `GetMostRecentCreatedAtAsync`). Add **one batched** read there that answers
"for these conversation ids, the latest message's body and timestamp", and call it once per request
with both lists' ids, the same one-batch-not-a-loop shape `GetManyByIdsAsync`/`GetNamesForVisitorsAsync`
already establish in this very handler. Check the index situation for that query and say what you
found; add an index only with the reason written down (`data-model.md`).

### What the preview must and must not contain

- Truncated server-side to a stated maximum, so an 8000-character message never crosses the wire for a
  list row. State the number and why.
- Plain text only. A message that is an attachment, a module step, or any non-text content kind has no
  sensible body to preview — decide and document what each renders as (a localized client-side label
  is a client concern; the DTO should be honest about the content kind rather than sending a
  server-composed Russian string, since this contract also feeds an English console locale).
- A system message counts as the last message if it genuinely is the last one — hiding it would make
  the timestamp and the text disagree, which is the exact inconsistency the author is asking to remove.
- `personal-data.md` applies: this is visitor-authored text appearing in a new place. Confirm nothing
  about retention or erasure changes because of it, and say so.

## The open question this item deliberately does not answer

The author invited disagreement on the timestamp, so it is recorded here rather than decided.

**Agreed, for the «Мои» tab.** Age-since-creation on an assigned conversation is close to useless — a
conversation the operator has been working for three hours reads "Открыт 3 часа" whether the visitor
last wrote three hours ago or ten seconds ago. Pairing the last words with the time of those last
words is the right consistency, and it is also the sort key the console already wants
(`mostRecentlyActiveFirst(queue.assignedToMe, attention)`).

**Not obviously right for the «Ожидают» tab.** That list is sorted `oldestFirst(queue.waiting)` and
labelled «Ждёт», and it answers a different question: how long has this visitor been waiting with
nobody answering. Switching it to last-message-time would make a waiting visitor who sends a second
message *jump to looking newer* — "20 мин" becomes "2 мин" — and sort themselves down the queue for
the crime of asking again. That is backwards for a queue.

**Resolved by the author, 2026-09-22** — a third option neither this item nor `26-30` had proposed,
which dissolves the collision outright rather than picking a side: **show both instants, each beside
the text it actually describes, instead of choosing one per tab.**

- The name line keeps the conversation's own age-since-creation (unchanged, so both tabs' existing
  sort order — «Ожидают» sorted oldest-first — needs no change at all), in the name line's own
  font weight — "more active" (the author's own words), because it describes the whole dialog.
- The new snippet line (`26-30`) carries the last-message instant beside the snippet text itself, in
  the snippet line's own (lighter) weight — so the timestamp closest to the words is the timestamp
  those words were said.

Both fields this item asks for are still needed exactly as scoped below — nothing about the DTO
changes from this resolution, only which line a client puts each timestamp on (`26-30`'s own concern).
No client-side branching on tab is needed either: both instants render, unconditionally, wherever the
data is present.

## Out of scope

- Any client rendering of these fields — `26-30` (Android) and the console's own item if one is filed.
- Channel/tag pills. There is no channel and no tag on a conversation today; that is Stage 14.

## Done when

- [x] `ConversationSummaryDto` carries a last-message preview and a last-message timestamp, both
      additive and nullable, documented in the record's own XML comment the way every field above them
      already is.
- [x] `GetOperatorQueueHandler` populates them from **one** batched `IConversationReadStore` read, not
      from the `Conversation.Messages` navigation, and not one query per row.
- [x] A conversation with no messages at all sends both as null, and no client is required to guess.
- [x] Non-text content kinds have a documented, decided representation.
- [x] The preview is truncated server-side to a stated maximum.
- [x] Integration test over the real query: a conversation with several messages reports the latest
      one, including when the latest is a system or operator message.
- [x] `dotnet format --verify-no-changes`, `dotnet build -c Release`, `dotnet test -c Release` green.
