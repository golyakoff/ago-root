# 25-135 · A relayed booking confirmation echoes the visitor's own message

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-17, while investigating the author's report of duplicated text and buttons in
  the booking flow (`25-133`) - not itself reported by the author, but a real defect on the same code
  path, filed per the standing rule that a found defect gets filed without waiting to be asked.
- **Depends on**: none. Touches `ago-chat` only. Shares files with `25-134` - land in the same lane,
  same worker, sequentially.

## The gap

`Ago.Chat.Domain.PrimitiveTextRenderer.Render` handles three of the four `adr/0065` primitives
explicitly (`choice_list`/`date_time_picker` get the numbered-list treatment; `form`/`escalate`/
`verified_phone_form` get the bare prompt) and falls through to `fallbackBody` for anything else -
which is exactly what happens for `confirmation_card`, since it has no `"prompt"` field for
`TryReadPrompt` to find (its own payload is a title and a list of lines, a different shape entirely -
see `PrimitiveKinds.cs`'s own remarks on why `confirmation_card` is excluded from the "every kind but
this one has a prompt" rule `PrimitiveTextRenderer`'s class doc states).

`fallbackBody`, at both call sites, is the trigger message's own body - in `RouteConversationToModule
Handler.FinishStepAsync` that's `trigger.Body.Value` (`ago-chat/src/Ago.Chat.Application/UseCases/
RouteConversationToModule/RouteConversationToModuleHandler.cs:439`), i.e. **the visitor's own last
reply** (the time slot they just picked, or a phone number they just typed). So the stored `Body` for
a completed booking's confirmation message is not a confirmation at all - it's an echo of whatever
the visitor sent to trigger it.

On the widget this is currently masked by the confirmation card rendering underneath it (visible only
as a stray extra line above the card - the same duplication `25-133` is about, and `25-133`'s own fix
makes it disappear from the widget entirely, coincidentally, without addressing the actual gap). On a
real text channel - Telegram or MAX, via `DeliverChannelMessageHandler`'s own independent re-render at
relay time (`ago-chat/src/Ago.Chat.Application/UseCases/DeliverChannelMessage/
DeliverChannelMessageHandler.cs:171-174`) - there is no card to mask it: **a completed booking on a
text channel currently relays as nothing but the visitor's own last message**, with no confirmation
content at all. `25-121` (which built exactly this relay path) did not cover this case.

## Scope

- Give `PrimitiveTextRenderer.Render` a branch for `PrimitiveKinds.ConfirmationCard` that reads the
  card's own `title` and `lines` out of the payload and renders them as text (title, then each
  `label: value` line) - the same two fields `ago-widget`'s own `render.ts` already reads for the
  identical payload shape (`ConfirmationCardContent`), so this is knowledge of Chat's own primitive
  vocabulary (`PrimitiveKinds.cs`'s own remarks: "a titled summary... payload lines to read"), not of
  Calendar's domain - the same justification the class's existing `"prompt"` read already rests on.

## Where this is likely to go wrong

- Don't special-case this by module or by kind name beyond what `Render`'s existing `if`/`switch`
  shape already does - one more branch in the same function, not a second function.
- Confirm `MessageOpacityTests` (or whatever test enforces "Chat reads only documented primitive
  shape fields, never a module's own field names") still passes - this item reads two more fields,
  and that test exists specifically to catch an undocumented field read.
- This item and `25-134` both touch `PrimitiveTextRenderer.cs` - sequence them, don't parallelize.

## Done when

- [ ] A Telegram/MAX booking confirmation shows the card's title and every line, not the visitor's
      own last message
- [ ] `MessageOpacityTests` (or equivalent) passes unchanged
- [ ] Widget rendering is unaffected by this item alone (the visible widget-side symptom is already
      fixed by `25-133`; this item is about what a text channel receives)
