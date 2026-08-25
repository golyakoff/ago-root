# Fix: one failed send in the widget desynchronises every optimistic bubble after it

- **Stage**: 5
- **Status**: ready
- **Depends on**: nothing — `ago-widget` only.

## Goal

A visitor whose message fails to send keeps seeing that it failed, and every message they send
afterwards renders exactly once. Today the first failure silently corrupts the pairing between
optimistic bubbles and their echoes, and it stays corrupted for the life of the panel.

## How this was found

While writing `11-08`'s widget behaviour tests (2026-08-25). Not reasoned from the source — reproduced:
after an ordinary drop → send → reconnect sequence the panel ends holding `["second", "second"]`, with
the *first* message's failure notice gone.

That is worth noting on its own. `11-08` was scoped as four behaviours to cover, not as a bug hunt, and
this fell out of building the reconnect-and-resume test. A defect that survived every manual pass of the
widget was found the first time somebody wrote down what the widget is supposed to do.

## What is actually wrong

Three lines, in `ago-widget/src/ui/widget.ts`:

- `dispatchSend` pushes onto `pendingSends` **before** invoking (`push` at ~line 339).
- The `.catch` marks the bubble failed — and **never removes the entry it pushed**.
- `handleIncoming` reconciles by **queue position**: `pendingSends.shift()` (~line 435).

The entry carries a `clientMessageId`. **Nothing ever compares it to anything.** It is written and then
only ever discarded.

So the queue is a positional pairing that assumes every push is eventually matched by exactly one echo,
and a failed send breaks that assumption permanently. After one failure, every subsequent echo removes
the bubble *before* the one it belongs to:

- the visitor loses the only sign their message never went — the "Not sent — reconnecting" bubble is
  removed by an unrelated message's echo;
- the message that did send renders **twice**: its own optimistic bubble is never removed, and the echo
  appends a second one.

Both halves are visible to the visitor, and the first one is the serious half: **a message the visitor
believes was delivered, was not.**

## Context to read first

`ago-widget/src/ui/widget.ts` — `dispatchSend`, `handleIncoming`, and the `PendingSend` type.
`docs/backlog/5-12-fix-widget-visitor-send-missing-client-message-id.md` — where `clientMessageId` came
from and what it is *for* on the wire. It exists precisely so a send and its echo can be matched; the
widget threads it through the protocol correctly and then does not use it locally.
`docs/backlog/11-08-frontend-behaviour-tests.md` — the tests this fell out of, and the ones that will
have to cover the fix.
`ago-console/src/pages/ConversationPage.tsx` — the operator side solves the same problem, and `11-08`'s
tests cover its retry rule (same `clientMessageId` when the outcome is unknown, a fresh one when nothing
was sent). Read how it pairs before inventing a second scheme here.

## Scope

- **Pair by `clientMessageId`, not by position.** The identifier is already on the wire in both
  directions; this is a local lookup, not a protocol change. Match the echo to its own entry and remove
  that one.
- **Decide what a failed send leaves behind, and say so.** Two defensible answers and they are not the
  same product decision: drop the entry on failure (the failed bubble stays until the visitor does
  something about it, and a late echo for it is treated as a new message), or keep it and let a late
  echo reconcile it (a send that failed with `SendOutcomeUnknownError` may still have landed — `5-12`
  and the console's retry rule both take that case seriously). State which and why.
- **The `SendOutcomeUnknownError` case is the one to get right.** It exists exactly because the
  connection dropped mid-request and nobody knows whether the message arrived. Whatever the pairing
  does, it must not turn "we are not sure" into a silently removed warning.
- Tests at `11-08`'s level, in the same style: drive the real widget against the fake hub, and make each
  one fail against the current code before it passes. The reproduction above is the first test.

## Out of scope

- Automatic retry of a failed send. The widget deliberately does not retry (`dispatchSend`'s own
  message says so), and changing that is a product decision with its own dedup and ordering questions.
- The operator side. `ago-console` pairs differently and `11-08` covers it; if this fix turns up a
  matching defect there, file it separately rather than widening this one.
- Any change to the wire protocol. `clientMessageId` is already carried both ways.

## Done when

- [ ] A failed send followed by a successful one leaves the failure notice visible and renders the
      successful message exactly once — proven by a test that fails against the current code.
- [ ] Echoes are paired by `clientMessageId`, and a test proves position no longer matters — e.g. two
      sends whose echoes arrive out of order still resolve their own bubbles.
- [ ] The `SendOutcomeUnknownError` decision is stated in the code with its reasoning, and covered.
- [ ] `npm run typecheck`/`lint`/`test`/`build` green, and the gzipped bundle stays inside its 45 KB
      budget (21.0 KB today).

## Open questions

Only the one named in Scope — whether a failed entry is dropped or left to be reconciled by a late
echo. It is this item's own to decide and record; both answers are defensible and the difference is
visible to a visitor.
