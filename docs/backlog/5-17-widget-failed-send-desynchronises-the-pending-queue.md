# Fix: one failed send in the widget desynchronises every optimistic bubble after it

- **Stage**: 5
- **Status**: done
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

## The decision this item owed: what a failed send leaves behind

**It depends on whether the server could have seen it, and the split is exactly the two error types
`connection.ts` already distinguishes.** Neither of the two answers in Scope on its own — the right
line runs between the errors, not across all failures.

**A send that never left drops its entry.** `NotConnectedError` is thrown before `invoke` is called
at all, and any other rejection came back while the socket was still up, i.e. the hub refused it. No
delivery can ever carry that `clientMessageId`, so keeping the entry would only park a dead key in
the map for the life of the panel. The failed bubble stays until the visitor does something about it,
and a visitor message arriving with that id anyway would be a genuinely new message — which is how it
would render.

**A send whose outcome is unknown keeps its entry.** `SendOutcomeUnknownError` means the invoke was
in flight when the socket went: the message may well have landed. If it did, the server's own copy
carries the same `clientMessageId` and will arrive — over the live connection, or in the history a
resuming `JoinAsync` replays — and resolves that bubble into the real message, rendered once.
Dropping the entry would make that arrival look like a brand-new message and render the visitor's one
message **twice**, under a warning saying it might never have been sent at all.

**This does not turn "we are not sure" into a silently removed warning**, which was the constraint.
The warning is removed by one thing only: the server's own copy of *that* message showing up, which
is evidence rather than a guess. Nothing else can clear it — not a later message's echo, not the
reconnect itself, not time passing — and if the message really never landed, it stays on screen for
good. The old positional pairing did the opposite: it removed the warning on the *next* message's
echo, with no evidence about the message the warning was about, which is the defect.

It is the same rule `ago-console` applies from the other end (`ConversationPage.tsx`: retry an
unknown-outcome send with the *same* `clientMessageId` because server-side dedup makes it safe, a
fresh one when nothing was sent). Both sides treat that id as still live in exactly the case where
the server may already hold it. Not a second scheme — the console's rule read from the receiving
side. Automatic retry stays out of scope, as written.

Recorded in `ago-widget`'s `ui/widget.ts` (the `SendOutcomeUnknownError` branch carries the reasoning
in full), in its README, and here. **No ADR**: this is one client's local reconciliation policy, it
changes no guarantee anything else depends on, and the wire contract it rests on was already decided
by `5-07`/`5-12`.

## What the item had slightly wrong

"The identifier is already on the wire in both directions; this is a local lookup, not a protocol
change" — correct about the wire (`Ago.Chat.Contracts.MessageDto.ClientMessageId` rides on every
delivery, and `VisitorHub`'s single `ToDto` means the local echo, the fan-out copy and the resume
history all carry it), but `ago-widget/src/protocol/types.ts` did not **declare** the field, so
nothing on this side could read it even in principle. `ago-console`'s copy of that file had declared
it since `5-07`. Adding it is still not a protocol change, only this repository's mirror of the
contract catching up.

One of `11-08`'s own tests had to change with the fix, which is worth naming rather than burying:
`widget.test.ts`'s "does not re-render the visitor's own message when the server echoes it back"
pushed a visitor echo carrying **no** `clientMessageId` — a message the real `VisitorHub` cannot
produce for a send that supplied one. It passed under positional pairing precisely because nothing
read the id. Its fixture now carries the id the widget sent the message under; the test still asserts
the same thing and is stronger for it. It is not a fails-before test — it passed both before and
after — it is a fixture that was quietly wrong being made real.

## Done when

- [x] A failed send followed by a successful one leaves the failure notice visible and renders the
      successful message exactly once — proven by a test that fails against the current code
      (`ui/reconciliation.test.ts`; against the pre-fix code it produced `["second", "second"]`,
      the exact symptom `11-08` reported).
- [x] Echoes are paired by `clientMessageId`, and a test proves position no longer matters — two
      sends whose echoes arrive out of order each resolve their own bubble, and a visitor message
      this panel never sent renders as a new message instead of consuming somebody's entry.
- [x] The `SendOutcomeUnknownError` decision is stated in the code with its reasoning, and covered by
      a test that fails against the current code: the warning survives an unrelated message's echo
      and is cleared by an echo carrying its own id.
- [x] `npm run typecheck`/`lint`/`test`/`build` green — 72 tests, up from 68 — and the gzipped bundle
      is **21.0 KB**, unchanged, against the 45 KB budget. A `Map` costs nothing an array did not.

## Open questions

None. The one this item owned is answered above.
