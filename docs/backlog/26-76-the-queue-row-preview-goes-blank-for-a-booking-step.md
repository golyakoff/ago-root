# 26-76 · The queue-row preview goes blank for a booking step, when the real words already exist

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, by the author, live on a real device — a conversation with 7 unread messages
  and a booking flow in progress showed no snippet line at all, reading identically to a conversation
  with zero messages. Discussed in chat rather than filed as an open question, because the author's own
  proposal below resolves the design question this would otherwise have needed.

## Found

`26-29`'s own `ToPreview` (`GetOperatorQueueHandler.cs:167-182`) refuses to render a preview whenever
the latest message's `ContentKind` is non-null — a module step (a booking flow's date picker,
confirmation card, and so on). That was the right call **given what `26-29` assumed**: "the backend
cannot tell a real human caption apart from a client-supplied placeholder standing in for a file or a
card, and a client is better served by an honest 'no preview' than a guess dressed up as one."

**That assumption is false for a module step, and only true for an attachment.** An attachment's
caption really is client-supplied, opaque, unverifiable text. A module step's `Message.Body` is not a
guess at all — it is Chat's own server-composed rendering, already produced once and already shipped
verbatim to SMS/Telegram/MAX visitors on channels with no rich UI:

- `RouteConversationToModuleHandler.cs:295`: `var body = PrimitiveTextRenderer.Render(prompt,
  PrimitiveKinds.ChoiceList, payload, actions, locale);`
- `RouteConversationToModuleHandler.cs:1050`: `var body = PrimitiveTextRenderer.Render(fallback,
  step.Kind.Value, step.Payload, step.Actions, locale);`
- Both call sites then do `c.AddSystemMessage(messageId, new MessageBody(body), now, content: content)`
  — **the exact text `ToPreview` throws away is already sitting in `Message.Body`**, unconditionally,
  for every module-step message that has ever existed in this system.

The author's own proposal, verbatim: the module already duplicates its structured content as plain
text for text channels, and the first line of that text is already exactly the right words —
"К кому вы хотите записаться", "Выберите дату", "Выберите время на вторник", "✅ Готово!" — so showing
that first line, with a 📅 prefix "потому что мы знаем что это от него", is the fix. No guessing, no
new rendering, no new captions to invent per content kind.

## What is actually true today, confirmed against real code

- `PrimitiveTextRenderer.Render` (`Ago.Chat.Domain/PrimitiveTextRenderer.cs`) is pure, Domain-owned,
  and reads only the fields this vocabulary's own six primitives define (`"prompt"`, or `"title"`/
  `"lines"` for `ConfirmationCard`) — never a module's own domain fields. Its own header states this
  is deliberately not the opacity rule being broken: "knowledge of *the four primitives Chat itself
  defines*, not of any module's domain."
- For every non-`ConfirmationCard` kind, `Render` returns the prompt line, then (for choice-shaped
  kinds with actions) a `\n`-separated numbered list, then a trailing `\n` + "Ответьте номером." For
  `ConfirmationCard`, `TryRenderConfirmationCard` returns the title line, then each `label: value` pair
  on its own `\n`-separated line. **In every case, the first line alone is the actual prompt or title —
  everything after the first `\n` is channel-rendering chrome** (the numbered menu, the reply
  instruction, the line-item detail), not part of "what was asked".
- `LatestMessageRow`/`LatestMessageSummary` (`Ago.Chat.Infrastructure.Postgres/LatestMessageRow.cs`,
  `Ago.Chat.Application/Abstractions/LatestMessageSummary.cs`) already carry `ContentKind` — the batched
  read-model query already selects it. **No new column and no new join are needed**; the query is
  unchanged.
- `ConversationSummaryDto` does not expose `ContentKind` today. `26-29`'s own remarks already named
  this exact deferral: "a localized client-side label is a client concern; the DTO should be honest
  about the content kind rather than sending a server-composed Russian string" — this item is that
  deferred step, now that there is a concrete reason to take it.
- Whether a message is a plain attachment (no `ContentKind`, `AttachmentId` set) is unchanged and stays
  exactly as blank as it is today — that half of `26-29`'s reasoning was correct and nothing here
  revisits it.

## Scope

One promise: **a queue row's preview shows the real first line of a booking step, prefixed so an
operator can tell at a glance that it is one.**

1. **`ConversationSummaryDto`**: add one additive, nullable field, `LastMessageContentKind: string?` —
   the raw `MessageContentKind` value, exposed exactly as `26-29` already anticipated. Populated in
   `GetOperatorQueueHandler.ToSummary` from `latestMessage?.ContentKind`, no read-model change needed.
2. **`ToPreview`**: three cases instead of two —
   - `latestMessage is null` → `null`, unchanged.
   - `AttachmentId is not null` → `null`, unchanged — still a genuine client-supplied placeholder,
     `26-29`'s own reasoning stands for this one case.
   - `ContentKind is not null` → **the first line of `Body`** (split on `\r\n`/`\n`/`\r`, take the
     first segment), truncated to the existing `MaxPreviewLength` the same way plain text is. Do not
     apply the existing collapse-all-lines-into-one-line transform here — that transform is correct for
     genuine multi-line prose (nothing is lost by joining it) and wrong for a module step's rendered
     menu (joining "Выберите дату" with "1) Понедельник" and "Ответьте номером." into one line is not
     what anyone wants to read, and is not what the author asked for).
   - Otherwise (plain text) → unchanged.
3. **Say so in the doc comments** — `ConversationSummaryDto`'s own remarks currently say attachment and
   content-kind "get the same treatment because the backend cannot tell a real human caption apart from
   a client-supplied placeholder". That sentence becomes false for content-kind and needs rewriting to
   state the actual, narrower reason attachments alone stay blank.
4. **Android**: `ConversationSummary`/the network DTO gains `lastMessageContentKind: String?`,
   threaded through `ConversationRowUi` the same way `state` (`26-40`) already threads an additive
   field from the DTO to the row. The snippet line (`26-30`) prefixes `"📅 "` to the preview text
   whenever `lastMessageContentKind` is non-null, nothing extra otherwise.
5. **Name the simplification plainly rather than pretending it is not one**: the 📅 prefix is correct
   *today* because `IModuleGateway` has exactly one live implementation site-enable-able anywhere in
   this system — the booking module — so "this message has a `ContentKind`" and "this message came
   from Calendar" currently mean the same thing by elimination, not because Chat or the client actually
   know which module produced a step (they deliberately do not — `adr/0065` decision 4, restated in
   `PrimitiveTextRenderer`'s own header). If a second module is ever wired to any site, this icon
   choice needs revisiting — worth a comment at the client call site so the next reader does not have
   to re-derive this, not worth solving now for a module that does not exist.

## Out of scope

- The console's own equivalent rendering — no item asks for it today; the DTO field is additive and
  costs the console nothing whether or not it reads it.
- Distinguishing "still waiting for a reply" from "the visitor abandoned this step and is never coming
  back" — both look identical from `ContentKind` and `Body` alone, and telling them apart needs an
  elapsed-time heuristic nobody has asked for yet. The 📅-prefixed first line is honest about *what the
  last step said*, not about whether anyone is still going to answer it, and that is the whole promise
  this item makes.
- Any change to `PrimitiveTextRenderer` itself, to the module wire contract, or to what gets stored in
  `Message.Body` — this item reads data that already exists, unchanged, in a new place.

## Done when

- [ ] `ConversationSummaryDto` carries `LastMessageContentKind: string?`, additive, documented.
- [ ] A conversation whose latest message is a real module step renders its preview as the first line
      of that step's already-rendered `Body` — unit tested against a multi-line fixture (prompt +
      numbered actions + "Ответьте номером.") asserting only the first line survives.
- [ ] A conversation whose latest message is a `ConfirmationCard` renders its own title line, not the
      `label: value` detail lines under it — unit tested.
- [ ] A conversation whose latest message is an attachment still renders no preview and no content
      kind — unchanged behaviour, regression-tested.
- [ ] The Android conversation list shows a 📅 prefix on the snippet line whenever the row's last
      message came from a module step, and no prefix otherwise — confirmed live against a real
      in-progress booking conversation on a real device.
- [ ] `ConversationSummaryDto`'s own doc comment states the real, narrower reason attachments alone
      stay blank, replacing the sentence this item makes false.
- [ ] `ago-chat`: `dotnet format --verify-no-changes`, `dotnet build -c Release`, `dotnet test -c
      Release` green.
- [ ] `ago-android`: `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green.
