# Keyboard shortcuts, and being told when something needs you

- **Stage**: 18
- **Status**: done, except the live two-browser check — which is the author's to run and is the same
  bar `11-06` held, for the same reason it recorded there: the console is behind a Keycloak password
  form and an implementing session may not enter credentials. What that leaves unverified is stated
  precisely below rather than glossed.
- **Depends on**: `11-06-operator-workspace.md` (shipped) — this extends its attention model rather
  than replacing it

## Goal

An operator working several conversations moves between them without the mouse, and finds out that a
new one arrived without watching the tab.

## Context to read first

`ago-console/src/workspace/` and `11-06`'s own scope — it already ships Enter/Shift+Enter, an unread
badge and a document-title count, and it deliberately named "a keyboard-shortcut system" and "desktop
notifications and sound" as out of scope for a stage about appearance. This item is that deferral
coming due, and it should extend `attention.ts` rather than add a second idea of what needs attention.
`docs/backlog/5-15-*` — unread is now cleared server-side, so the badge means something durable and a
notification can be trusted not to fire for something already read.

## Scope

- A small, discoverable set of shortcuts: move between conversations, focus the composer, close, and
  whatever the workspace's own layout makes obvious. Discoverable means listed somewhere in the
  interface, not only in a file.
- Desktop notifications for a newly assigned conversation, **off until the operator turns them on** —
  the browser permission prompt on first load is the single most common way a product teaches people
  to click Block forever.
- Sound as a separate switch from notifications, because the people who want one frequently do not
  want the other.
- Respect the existing state: nothing fires for a conversation the operator is already looking at.

## Out of scope

- A command palette. A bigger interaction idea; if the shortcut list grows enough to want one, that is
  its own item with its own argument.
- Notifications when the tab is closed (push, service workers) — a different mechanism entirely, and
  it needs a subscription store and a server-side sender.
- Configurable key bindings.

## Done when

- [x] The shortcuts work and are discoverable from inside the console.
      Five: `J`/`K` move through "Assigned to me" in the order the rail draws it, `C` focuses the
      composer, `Esc` closes the open thread, `?` opens the list. Discoverable two ways, because a
      help screen reachable only by a shortcut is not discoverable: a **Shortcuts** button in the
      conversation rail, and `?`. The dialog is generated from `SHORTCUTS` — the same array the key
      handler dispatches on — so a shortcut cannot exist without being listed, and a test asserts the
      two cannot drift apart.
- [x] Notifications and sound are separate, both default off, and neither fires for the conversation on
      screen. Two independent switches in an **Alerts** dialog beside it. See "What *already looking
      at* was decided to mean" below for the rule, which is stricter than either obvious reading.
- [ ] **Verified live with two browsers, the same bar `11-06` held. Not done, and not this session's
      to do.** The console is behind a Keycloak password form; an implementing session may not enter
      credentials, which is exactly what `11-06` recorded when it hit the same wall. So **no real
      browser has shown a real desktop notification from this code**, and nothing below should be
      read as claiming otherwise. What is proven is every decision underneath it, against the real
      modules, in jsdom.

      What the live check has to cover, in the order it will break:
      1. Load the console. **No permission prompt appears.** (The regression this item most exists to
         prevent; a test fails if the call moves to mount, but a browser is what proves the page as
         shipped.)
      2. Open **Alerts**, turn on notifications — *now* the browser asks. Say yes.
      3. From a second browser, send a visitor message to a conversation that is **not** the one on
         screen. A card appears naming the visitor and **not** quoting the message.
      4. Send to the conversation that **is** on screen, tab visible. Nothing appears, nothing sounds.
      5. Switch to another tab and repeat (4). A card **does** appear — this is the case that
         separates the rule this item implemented from "the tab is focused".
      6. Click the card: the tab focuses and that conversation opens.
      7. Turn notifications off, turn **Sound** on, repeat (3). A chime, no card.
      8. Type a sentence containing `j`, `k` and `c` into the composer. Nothing moves. Press `Esc` —
         the draft clears and the thread stays open. Click outside the composer, press `Esc` — the
         thread closes.

## What *already looking at* was decided to mean

The item's sentence is "nothing fires for a conversation the operator is already looking at", and the
whole of its ambiguity is in those three words. The decision: **this tab has that conversation open
*and* the document is visible.** Both. Neither obvious shorthand survives contact with an operator:

- **"The tab is focused"** is wrong because the tab can be focused with a *different* conversation
  open. An operator answering visitor A is not looking at visitor B, and swallowing B's message is
  the failure this item exists to prevent.
- **"The conversation is open"** is wrong because the right thread can be on screen while the
  operator is in another window entirely — which is the case desktop notifications are *for*.

Both cases are tests (`alerts.test.ts`), and each fails against the shorthand that gets it wrong.

One thing the rule deliberately is not: `document.visibilityState` is not "the window has focus". A
visible but unfocused window counts as looking, because a console on a second monitor is a screen the
operator can see, and a card drawn over it would be telling them something they are already reading.

## Two decisions this item made that its own Scope did not name

**Notifications fire for an incoming message too, not only for a new assignment.** Scope says
"desktop notifications for a newly assigned conversation"; the Goal says the operator "finds out that
a new one arrived without watching the tab". Notifying only on assignment would make the loudest
signal in the console fire for the *least* urgent event — a conversation nobody is waiting on yet —
and stay silent when a visitor who has already been answered replies. The suppression rule is
identical for both, so this adds a trigger rather than a second idea of what needs attention.

**A notification never contains the message text.** It says who, and that something arrived. A
notification is drawn over whatever is on screen, in a room that may have customers in it, and on
some platforms it persists in a notification centre nothing in this system can erase — which makes it
the wrong place for the free-text field `personal-data.md` treats as most likely to hold something
about a person. The words are one click away.

## What this item found, and did not fix

**`6-02` shipped `POST /api/v1/conversations/{id}/close` and `Permission.ConversationClose` in Stage
6, and no operator has ever been able to reach it.** There is no close action anywhere in
`ago-console` — no button, no menu item, no API client call. `6-09` then made closing release the
operator's capacity, which is the mechanism that keeps `4-02`'s assignment engine moving; that
mechanism has a caller in tests and in `curl` and nowhere an operator can click.

That is why this item's `Esc` **closes the open thread** (returns to `/`) rather than closing the
conversation. The Scope's word "close" admits both readings, and only one is buildable here: a
shortcut for a button that does not exist is not a shortcut, it is a new product action wearing a
keybinding — with a confirmation, a permission gate and `6-08`'s concurrency-conflict path attached,
none of which belongs in an item about keyboard shortcuts.

**The missing action deserves its own item**, and when it lands the shortcut set has room for it.

## Open questions

None. The one genuinely discretionary choice — what "already looking at" means — is decided and
written up above, following `11-06`'s own precedent of naming its discretionary decision in the item
rather than leaving it in a commit message.
