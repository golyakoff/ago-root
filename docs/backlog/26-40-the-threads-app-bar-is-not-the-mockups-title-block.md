# 26-40 · The thread's app bar is not the mockup's title block

- **Stage**: 26
- **Status**: done — merged as [ago-android#47](https://github.com/golyakoff/ago-android/pull/47)
- **Found**: 2026-09-23, reading the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) against `ago-android` `main` at `ad2859b`.

## Found

The mockup's thread app bar carries a two-line title block — a name, and under it a quiet line of
context:

```html
<div class="appbar">
  <div class="iconbtn"><svg class="i"><use href="#i-back"/></svg></div>
  <div class="ttl sm">Лиса · Апельсин<span class="sub">Виджет &middot; в работе &middot; 2 мин</span></div>
  <div class="iconbtn"><svg class="i"><use href="#i-more"/></svg></div>
</div>
```

with its own rules:

```css
.appbar .ttl{font-size:19px; font-weight:700; letter-spacing:-.01em; flex:1; min-width:0}
.appbar .ttl.sm{font-size:17px}
.appbar .sub{display:block; font-size:11.5px; font-weight:500; color:var(--ink-soft); letter-spacing:0}
```

Two things are wrong against that, in opposite directions. The second line **is absent**, and the
first line **carries something the mockup does not draw**: the eight-character visitor code.

The mockup's thread title is the words `Лиса · Апельсин` and nothing else — no emoji glyphs, no code.
The same is true of every other place the mockup draws this visitor on a conversation surface: the
visitor sheet's own header (`<div class="rname"><span class="ename">Лиса · Апельсин</span></div>`) and
the tablet detail pane's head (`Лиса · Апельсин · виджет`). The one place the mockup still draws eight
hex characters is the storage screen, where the id being shown is a *conversation* id an operator may
have to match against a log (`Диалог <span class="mono">7c4e18f0</span>`) — a different id doing a
different job.

## This finishes a sentence `26-30` wrote, rather than contradicting it

`26-30` removed the short code from the list row and wrote, in its own Scope: "the code is still the
right thing elsewhere (**the thread screen**, anywhere an operator has to dictate or match an id) —
this removes one call site, not `IdentifierText`." That was a reasonable guess at the time and the
mockup does not support it for this call site. The author's original note that drove `26-30`
(«восьмизначные коды диалога - на экране они лишние») is about the same code on the same visitor, one
screen over. `IdentifierText` itself stays — `SettingsScreen`'s site rows and the sign-in site picker
are both real uses of it, and both are ids an operator genuinely may have to match.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/thread/ThreadScreen.kt:192-200` renders the title as
  `VisitorDisplayPrefix` alone, with no subtitle slot of any kind:

  ```kotlin
  title = {
      // Plain text, not a chip - see this file's own top-of-file doc comment.
      VisitorDisplayPrefix(
          emojiCreature = emojiCreature,
          emojiFood = emojiFood,
          visitorName = visitorName,
          visitorId = visitorId,
      )
  },
  ```

- `VisitorDisplayPrefix` (`ui/components/VisitorDisplayPrefix.kt:47-63`) draws three parts in a `Row`:
  the emoji pair at `titleLarge` size, then `parts.displayName`, then — **unconditionally, with no
  caller opt-out** — `IdentifierText(id = parts.visitorId, style = baseStyle)` at `:62`. That last
  call is the eight-character code on the thread's app bar today.
- The data for the mockup's own subtitle is one additive field short, not a backend change:
  - **«2 мин»** — the row's `createdAt` is already in hand. `ConversationsTabHost.kt:66` resolves the
    open conversation's `ConversationRowUi` out of the list state before calling `ThreadRoute`, and
    that object carries `createdAt` (`conversations/ConversationListUiState.kt:19`). The screen does
    not receive it today only because `ThreadRoute`'s parameter list
    (`ThreadScreen.kt:87-95`) was never given it.
  - **«в работе»** — the conversation's state is on the wire already:
    `ago-chat/src/Ago.Chat.Contracts/ConversationSummaryDto.cs:84` declares `string State` as a
    non-optional positional field of the queue DTO. `ConversationSummary`
    (`core/domain/.../conversations/ConversationSummary.kt`) deliberately does not carry it — its own
    doc comment: "`state`/`operatorId`/`operatorName`/the attachment-grant fields are on the wire DTO
    and are not carried here because nothing in this screen reads them; a later item that needs one
    grows this type". This is that later item.
  - **«Виджет»** — the channel. There is no channel field anywhere: not on `ConversationSummaryDto`,
    not on `Conversation`. Incoming-channel expansion is `Ago.Chat`'s Stage 14 and is not built. This
    part is not in scope and must not be faked with a hardcoded «Виджет».

## Scope

One promise: **the thread's app-bar title block is the mockup's title block.** Both halves change the
same `title = {}` slot of the same `TopAppBar`, and either landing alone leaves that slot half-rebuilt
— the same reason `26-30` kept its own five row parts together rather than splitting them.

1. **The title line is the name alone.** `parts.displayName` — which since `26-30` is the visitor's
   real name or the emoji pair's localized label («Лиса · Апельсин») — with no `IdentifierText`.
   Give `VisitorDisplayPrefix` a way for a call site to say it does not want the id, or give the
   thread its own small title composable reading the same `visitorDisplayPrefixParts`; pick whichever
   leaves the rule about *which parts exist* stated exactly once in `:core:domain`, which is the
   principle `ConversationRowIdentityLine` already follows for the row. Drawing the emoji pair inline
   here is a judgement call the mockup does not draw either — decide it, and say which way in the
   report; the mockup's own title is plain text.
2. **A subtitle line under it**, in the mockup's `.sub` treatment (small, medium weight,
   `onSurfaceVariant`), composed of the parts that have real fields: the conversation's state,
   rendered as words an operator reads rather than the wire enum spelling, and the same short elapsed
   form the list row already uses («2 мин» / «4 ч» / «2 д»). Reuse that formatter rather than writing
   a second one — it lives in `ConversationListScreen.kt` today and wants to move somewhere both
   screens can read it.
3. **Grow `ConversationSummary`/`ConversationRowUi` with the conversation's `State`**, additively, the
   way `26-15` grew them with `hasAttachmentUploadGrant` and `26-30` with the snippet pair, and pass
   it plus `createdAt` into `ThreadRoute` from `ConversationsTabHost`. A thread opened with no matching
   row in hand (`ConversationsTabHost.kt:66` can answer `null`) renders no subtitle rather than a
   guessed one.

## Out of scope

- **The channel half of the subtitle** («Виджет»). No field, Stage 14. The subtitle renders the two
  parts that are real and does not leave a separator hanging where the third would go.
- **The `⋮` overflow the mockup draws at this bar's trailing edge.** Its one menu item in the mockup's
  own graph is `Thread -- "⋮ Закрыть" --> CloseSheet`, and closing a conversation is not built in this
  app — an overflow that opens an empty menu is the same "inert control" shape `26-15` rejected for
  the visitor chip. It arrives with the action, not before it.
- **Making the title tappable.** `ThreadScreen`'s own top-of-file doc comment settles that
  deliberately ("absent, not inert") and the visitor sheet is still not built. Unchanged here.
- `IdentifierText` itself, and its other call sites.

## Done when

- [x] The thread's app bar shows the visitor's name with no eight-character code.
- [x] A second line under it shows the conversation's state and its age, in the mockup's `.sub`
      treatment.
- [x] The state is a word an operator reads, localized in `strings.xml`, not the wire spelling.
- [x] A thread opened without its list row in hand renders the title with no subtitle and does not
      crash or draw a stray separator.
- [x] Nothing hardcodes a channel name.
- [x] `./gradlew ktlintCheck lint test assembleDebug` green.
- [x] Checked against the mockup on a real device, on a conversation with a real elapsed time.

Confirmed live on the real device (`F6VCHEZDAMRCPNJZ`): "Тигр · Пончик" / "в работе · 21 ч", no code.
