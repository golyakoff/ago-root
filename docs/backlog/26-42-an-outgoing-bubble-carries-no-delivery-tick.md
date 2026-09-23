# 26-42 · An outgoing bubble carries no delivery tick

- **Stage**: 26
- **Status**: done — merged as [ago-android#47](https://github.com/golyakoff/ago-android/pull/47)
- **Found**: 2026-09-23, reading the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) against `ago-android` `main` at `ad2859b`.

## Found

Every outgoing bubble in the mockup's thread ends its timestamp with a tick, and the number of ticks
is the point:

```html
<div class="bub out">Добрый день! Сейчас посмотрю по заказу, одну минуту.<span class="t">09:39 ✓✓</span></div>
<div class="bub in">Спасибо<span class="t">09:40</span></div>
<div class="bub out">Платёж завис у банка, деньги вернутся в течение суток. …<span class="t">09:41 ✓</span></div>
```

The mockup's own caption for this screen says exactly what the second tick means and warns against the
obvious wrong reading:

> Порядок — это назначаемый сервером `sequence`, никогда не часы, а вторая галочка — это
> `Message.DeliveredAt`, собственное подтверждение виджета, **а не квитанция об отправке**.

One tick is "the server has it". Two ticks is "the visitor's widget acknowledged it". Incoming bubbles
carry no tick at all, which the mockup also shows.

The app draws the clock time and nothing else, on both directions.

## The field already exists on the wire — this is a client-side change

- `ago-chat/src/Ago.Chat.Contracts/MessageDto.cs:47` already carries it:

  ```csharp
  IReadOnlyList<MessageActionDto>? Actions = null, DateTimeOffset? DeliveredAt = null);
  ```

  with `:35-39` recording why: "`25-119`: `DeliveredAt` is additive, appended last… Sourced from
  `Domain.Message.DeliveredAt` on the same read".
- `Ago.Chat.Domain.Message.DeliveredAt` (`src/Ago.Chat.Domain/Message.cs:98`) is the real property,
  set once and only for an operator's own message (`:112-132`, which refuses a non-operator message
  outright) — which is why a visitor's bubble has no tick to draw and never will.
- There is also a live push for it: `MessageDeliveredDto(ConversationId, MessageId, DeliveredAt)`
  (`src/Ago.Chat.Contracts/MessageDeliveredDto.cs:9`), resolved and fanned out by
  `ResolveMessageDeliveredTargetsHandler`. So the second tick can arrive after the bubble is already
  on screen, without a refetch.

Nothing in `ago-chat` has to change.

## What is actually true today, confirmed against real code

- The Android wire type does not declare the field.
  `core/network/src/main/kotlin/ago/chat/android/core/network/realtime/MessageDto.kt:39-48`:

  ```kotlin
  public data class MessageDto(
      val id: String,
      val sequence: Long,
      val conversationId: String? = null,
      val authorKind: String = "",
      val body: String = "",
      val createdAt: String = "",
      val attachmentId: String? = null,
      val clientMessageId: String? = null,
  )
  ```

  That type's own doc comment already names this as the expected shape of growth — "`26-14`:
  `authorKind` is the first of that growth… Every new field defaults to a value that is never a
  genuine wire value… so `26-13`'s own fixtures keep compiling unchanged." A nullable
  `deliveredAt: String? = null` follows that rule exactly.
- The bubble renders a bare clock time.
  `app/src/main/kotlin/ago/chat/android/thread/ThreadScreen.kt:408-415`:

  ```kotlin
  clockTimeOrNull(message.createdAt)?.let { time ->
      Text(
          text = time,
          style = MaterialTheme.typography.labelSmall,
          color = LocalContentColor.current.copy(alpha = BUBBLE_TIMESTAMP_ALPHA),
          modifier = Modifier.padding(top = 2.dp),
      )
  }
  ```

  `isOperator` is already computed one screen up (`:392`, `message.authorKind == "Operator"`), so the
  "only an operator's own bubble gets a tick" rule needs no new signal.
- There is no `MessageDelivered` hub handler on the client.
  `core/network/.../realtime/` carries `MessageSubscription.kt` and `ConversationAssignedDto.kt`; no
  file mentions delivery. So the live second tick is genuinely new wiring, not a field read.

## Scope

One promise: **an operator's own bubble says whether the visitor's widget acknowledged it.**

1. Grow the client `MessageDto` with `deliveredAt: String? = null`, additive, defaulting to a value
   that is never a real wire value — the rule that type's own doc comment already states.
2. An operator's bubble renders one tick when `deliveredAt` is absent and two when it is present,
   after the clock time, inside the same `.t` line and therefore in the same `LocalContentColor` alpha
   the timestamp already uses (`26-23` made that alpha-over-content-colour choice for a reason: a
   fixed colour is unreadable on the solid brand fill). A visitor's or system bubble renders no tick.
3. Subscribe to the hub's `MessageDelivered` push and apply it to the message already on screen, so
   the tick goes from one to two without leaving and re-entering the thread. Idempotent — the same
   delivery arriving twice must not produce a third tick or a re-render loop; at-least-once is assumed
   everywhere (`CLAUDE.md` rule 5).
4. Decide, and state in the report, whether the ticks are glyph characters or vectors. The mockup uses
   the literal `✓`; `26-23`'s own lesson was that a literal character standing in for an icon is how
   this app ended up with `"←"` and `"📎"`. A tick *inside a text run beside a timestamp* is not the
   same case as a tap target, so either answer may be right — but it should be an answer, not a
   default.

## Out of scope

- A third state ("read"). There is no read receipt in the product and inventing one is exactly the
  kind of number this project does not invent.
- A failed-send indicator. That path already has its own rendering — `state.pendingRetry` and the
  retry banner (`ThreadScreen.kt:220-226`) — and conflating "not yet delivered" with "failed" is the
  misreading the mockup's own caption warns about.
- The composer below it — `26-41`.

## Done when

- [x] An operator's bubble shows one tick before delivery and two after; a visitor's shows none.
- [x] The second tick appears live, on a bubble already on screen, with no navigation away and back —
      verified against a real widget acknowledging a real message, not only against a fixture.
- [x] A repeated `MessageDelivered` for the same message changes nothing.
- [x] The tick is legible on the solid brand fill in both light and dark.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.

Verified end-to-end against the real deployed backend: a scripted visitor client (real visitor
session, real hub connection, calling `AcknowledgeDeliveredAsync` exactly the way `ago-widget`'s own
`connection.ts` does) received a real operator message sent from the connected device and acknowledged
it — the app's own bubble, already on screen with no navigation away and back, updated from one tick to
two. Confirmed the wire method name (`"MessageDelivered"`) matches `ago-chat`'s own
`ResolveMessageDeliveredTargetsHandler` exactly.
