# 25-159 · A consent choice typed by a widget visitor is never resolved

- **Stage**: 25
- **Status**: ready — diagnosed 2026-09-19, root cause confirmed against `origin/main`
- **Found**: 2026-09-19, live-testing a calendar booking flow through the widget. After answering the
  consent step (`25-153`'s own gate) by clicking "Согласен(na)", nothing happened - no recap, no
  confirmation, no follow-up message of any kind.
- **Split from**: originally filed together with the consent step's plain-text-link bug as one item.
  Split 2026-09-19 per rule 15 - the two share no file and no cause; the other half is `25-158`
  (`ago-widget`, rendering). This item is `ago-chat` only (Application-layer reply resolution).

## Root cause, confirmed

`Ago.Chat.Application.UseCases.RouteConversationToModule.RouteConversationToModuleHandler.ContinueConsentGateAsync`
resolves the visitor's reply via:

```csharp
var resolved = ChoiceReplyTextResolver.Resolve(trigger.Body.Value, ConsentActions(locale));
```

`ChoiceReplyTextResolver.Resolve` (`Ago.Chat.Domain`) only accepts a **bare positive integer** string
("1", "2") - built for a text-channel visitor who typed a number. A **widget** reply never sends a
number as its body: `sendStructuredReply` (`ago-widget/src/ui/widget.ts`) sends `body` as the button's
own display text (for this step, the literal "Согласен(na)"/"Не согласен(na)") and puts the real answer
in structured `content.value` (`"consent-accept"`/`"consent-decline"`), `contentKind = "choice_list"`.

So for a widget click: `trigger.Body.Value` is `"Согласен(na)"`, `int.TryParse` fails inside `Resolve`,
`Resolve` returns `null`, and `ContinueConsentGateAsync` hits:

```csharp
if (resolved is null)
{
    return RouteConversationToModuleOutcome.ReplyNotResolved;
}
```

`ReplyNotResolved` means: no message is added, no domain event fires, nothing is saved, nothing is ever
pushed back over SignalR to the widget. This exactly matches the reported symptom, for either Accept or
Decline, since both go through the same call.

**Why the generic path handles this correctly but the consent gate doesn't**: every *ordinary* module
step resolves through `ResolveReplyValue`, which checks `trigger.Content` first (via the existing
private helper `TryReadReplyValue`) and only falls back to `ChoiceReplyTextResolver.Resolve` when
there's no matching structured content - and for an ordinary step, `active.LastStepKind` genuinely
equals the step's own wire kind (e.g. `ChoiceList`), so the structured-content branch fires. The consent
gate bypasses this generic resolver entirely, because `25-153`'s own `FinishStepAsync` deliberately
records the **real, hidden phone step** onto `active.LastStepKind` while showing the visitor a
**different** message - the consent `choice_list`. So `active.LastStepKind.Value` is
`Form`/`VerifiedPhoneForm`, never `ChoiceList`, and `ContinueConsentGateAsync` was written to sidestep
that mismatch rather than account for it.

**Confirmed by the test suite's own shape**: every existing consent-gate test
(`RouteConversationToModuleHandlerTests.cs`) simulates the reply with a plain `MessageBody("1")` /
`MessageBody("2")` - text-channel style, no structured `content` at all. The missing case already has a
template in the same file for *ordinary* steps
(`HandleAsync_WithAWidgetShapedReply_SubmitsTheResolvedActionValue`, paired with
`HandleAsync_WithATextChannelNumericReply_ResolvesToTheSameValueAsTheWidgetReply`) - that pattern was
never applied to the consent gate.

## Scope

In `ContinueConsentGateAsync`, resolve the reply structured-first, the same way `ResolveReplyValue` does
for ordinary steps, but keyed to the consent step's own actual wire kind (`PrimitiveKinds.ChoiceList`)
rather than `active.LastStepKind` (which the consent gate deliberately overwrites - see root cause
above):

```csharp
var resolved = trigger.Content is { } structured && structured.Kind.Value == PrimitiveKinds.ChoiceList
    ? TryReadReplyValue(structured.Payload)
    : ChoiceReplyTextResolver.Resolve(trigger.Body.Value, ConsentActions(locale));
```

Reuses the existing private `TryReadReplyValue` helper already in the same class - no new port, no
Domain or Infrastructure change, no widget change.

## Done when

- [ ] A widget-shaped Accept reply (structured `content.value = "consent-accept"`,
      `contentKind = "choice_list"`, arbitrary display text as `Body`) grants consent and reveals the
      real (phone) step - proven by a new test mirroring
      `HandleAsync_WithAWidgetShapedReply_SubmitsTheResolvedActionValue`'s own pattern, which fails on
      current code and passes after the fix
- [ ] The same holds for a widget-shaped Decline reply
- [ ] Every existing text-channel consent-gate test (`MessageBody("1")`/`MessageBody("2")`, no
      structured content) still passes unchanged
- [ ] The exact repro from this item - answering "Согласен(na)" through a real widget in a real booking
      flow - immediately shows the next (phone) prompt, proven live, not only by a unit test
