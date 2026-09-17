# 25-121 · A module task's own prompt never reaches a text channel

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: 2026-09-17, the author testing `/записаться` for real over Telegram: the operator console
  showed the booking module's own system message ("Что вы хотите забронировать? 1) Консультация...
  Reply with the number.") but the same conversation's Telegram chat stayed empty.

## What is actually true today

`RouteConversationToModuleHandler` (`20-07`) adds every module-task prompt as a
`MessageAuthorKind.System` message (`AddSystemMessage`) - this is what the console and the widget
both render live, through their own existing read paths.

`DeliverChannelMessageHandler` (`14-02`) is the only mechanism that relays an outbound message back
through a visitor's linked channel (Telegram/MAX/WhatsApp/Avito), and its own loop guard
(`DeliverChannelMessageHandler.cs:94`, restated at `:123`) relays **only**
`MessageAuthorKind.Operator`. Its own doc comment says why a `System` message is excluded - `14-04`'s
offline auto-reply loop guard - and flags this explicitly as "a scope line rather than a safety one",
naming `14-03` as the item expected to widen it. `20-07`'s booking flow (and everything built on top
of it since - `25-33`'s picker, `25-37`'s locale support, `25-38`/`25-39`'s phone step) shipped
without ever widening this check.

**Net effect**: a module task's own prompts (the service list, the date/time picker, the phone
form, the confirmation) are structurally invisible on every channel except the widget and the
console's own live view. A visitor triggering `/записаться` from Telegram (or MAX, WhatsApp, Avito)
sees their own trigger message accepted and then nothing - `PrimitiveTextRenderer` (`20-07`) exists
specifically to give every one of these steps a plain-text rendering for exactly this case, and it is
never actually invoked for delivery to a real channel today - only for the fallback body a caller
already has to hand a text-only step.

## Where this is likely to go wrong

- **Not simply "relay every System message".** `14-04`'s offline auto-reply is also `System`-authored
  and its own interaction with a real channel is out of scope here too (unchanged) - widen the check
  to name what should now be relayed (a module task's own prompt, specifically), not blanket-remove
  the guard.
- **`PrimitiveTextRenderer.Render` is the existing, already-correct rendering** - reuse it for the
  outbound text, do not build a second rendering path.
- **The loop guard still has to hold**: a module-task prompt relayed out to Telegram must not itself
  be treated as a fresh trigger by `ReceiveChannelMessageHandler` when the reply comes back in - that
  inbound half is unaffected by this item (a visitor's reply is `MessageAuthorKind.Visitor` either
  way), but confirm it explicitly rather than assume.
- **Every channel-kind adapter, not just Telegram** - MAX/WhatsApp/Avito hit the identical gap;
  the author's own report happened to be Telegram, but the fix belongs in the shared handler.

## Done when

- [ ] A `/записаться` (or any other module trigger) conversation over a real text channel (Telegram at
      minimum, ideally verified against MAX too) shows the module's own prompt in that channel, not
      only in the console/widget.
- [ ] `14-04`'s offline auto-reply is confirmed still not relayed to a channel (unrelated scope,
      protect it explicitly with a test).
- [ ] A widget conversation's own module-task rendering is unchanged (structured payload, not the
      primitive-text fallback).
