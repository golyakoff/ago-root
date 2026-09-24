# 26-90 · Android has no analog of the console's admin "all conversations" page

- **Stage**: 26
- **Status**: ready — filed to hold the item, not dispatched
- **Found**: 2026-09-24, by the author — "у нас не хватает в разделе Диалоги аналога страницы
  `https://office.reserve-me.ru/conversations/all`. Администратор должен мочь видеть список диалогов,
  зайти в них, почитать историю диалога. Сейчас на этой странице можно даже удалить диалоги старые."
- **Not to be taken into work yet** — the author explicitly asked only to file this so it is not
  forgotten; scoping and dispatch are for a later session.

## What is actually true today (from the author's own report — verify before scoping)

The console's `/conversations/all` page gives an administrator: a list of every conversation on the
site regardless of assignment or state, the ability to open one and read its full history, and the
ability to delete old conversations. `ago-android`'s own Диалоги section today only ever shows «Мои» и
«Ожидают» — an administrator-scoped "everything, including closed and others'" view has no Android
equivalent.

## Scope (not yet finalized — this is a placeholder, not a committed design)

- A real `/conversations/all`-equivalent view reachable from Диалоги, gated to whoever the console's own
  page is gated to (read the console's own route guard before assuming which permission — likely an
  administrator-level permission, not `conversation:assign`).
- List, open, and read history for any conversation on the site.
- The delete-old-conversations action the console page carries — confirm the real permission and
  confirmation-flow the console uses (`Permission.ConversationErase`, from the same enum `26-85`/`26-86`
  already read) rather than inventing a new one.

## Out of scope (for now — genuinely undetermined until this item is actually scoped)

- Everything about *how* this fits into the existing «Мои»/«Ожидают» segmented control — a third tab, a
  separate admin-only screen reached another way, or something else entirely is an open design question
  this filing does not answer.

## Done when

- [ ] Scoped for real (this item's own Scope section rewritten from an actual read of the console's
      page and its permission gates) before any code is written.
- [ ] Implemented and verified once scoped.
