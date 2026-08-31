# ADR-0081: A reachable-but-unsure module escalates through a fifth primitive, not a new signal

- **Status**: Accepted
- **Date**: 2026-08-31
- **Stage**: 19 (and 20 - this extends the contract `20-07` built)

## Context

`adr/0065` gave `Ago.Chat.*` an escape to a human operator for exactly one failure mode: a module that
cannot be reached at all (timeout, connection refused, a malformed response) degrades to
`ModuleUnreachableException`, and `RouteConversationToModuleHandler` (`ago-chat`) closes the task and
tells the visitor a person will take over. `19-03` (the FAQ/knowledge-base module) needs a second,
different escape: a module that answers just fine over the wire, but has run out of confidence in its
own answer - the tenant's knowledge base does not cover the question, or the model itself signals
uncertainty. Neither `ModuleWireContract`/`ModuleTaskContracts` (Calendar's own two files, the
`19-03` backlog item's own words) nor `IModuleGateway` had a reason to carry this signal before, because
Calendar's booking flow never needs to say "I don't know" - every step it offers is a real, answerable
choice.

The constraint this decision has to fit inside is `adr/0065`'s own boundary, restated by `19-03`'s own
context section: `Ago.Chat.*` must recognise "hand this to an operator" **structurally**, never by
parsing what a module's payload means. A design that has Chat inspect payload content (a `confidence`
number, a magic string inside `payload.prompt`) to decide whether to escalate would put semantic
knowledge of a module's own reasoning inside Chat - exactly the mistake `adr/0065` decision 1 ("Chat
never opens the payload") already refused once, for a different failure mode.

## Decision

**A fifth member joins the closed primitive vocabulary Chat itself owns**: `PrimitiveKinds.Escalate`
(`"escalate"`), alongside `choice_list`/`form`/`confirmation_card`/`date_time_picker`. A module signals
low confidence by handing back an ordinary step of this kind - a prompt (optional; a generic apology is
substituted when absent) and no actions - through the *identical* wire shape `StepWireDto` already
carries for every other kind. Nothing about the wire contract's fields changes; only the vocabulary of
values one field (`kind`) may hold grows by one, the same way it would if a sixth or seventh primitive
were ever added.

`RouteConversationToModuleHandler` recognises this one value **by string comparison against its own
constant**, the same mechanism it already uses for `PrimitiveKinds.IsChoiceShaped`. This is knowledge of
*Chat's own fifth word*, not of the FAQ module's domain - the identical "shape, not meaning" split
`MessageContentKind`'s own remarks draw, and the same one `PrimitiveTextRenderer` already relies on to
render `form`/`choice_list` without knowing what either module's step is actually about. Recognising the
kind triggers two structural consequences, both applied regardless of the module's own `complete` flag:

1. The task force-closes. `adr/0065` decision 7 - "an escape to a human always exists and cannot be
   suppressed by the module" - was written for the case where Chat decides to close *unilaterally*
   (the module has no vote because it is unreachable). An escalate step is the *reachable* mirror: the
   module is answering, so in principle it could send `escalate` with `complete: false` and ask to keep
   the task open. Honouring that would let a module suppress its own escalation by omission, which is
   exactly what decision 7 already forbids for the unreachable case - so the force-close is unconditional
   here too, never conditional on the module's own flag.
2. The outcome is reported as `RouteConversationToModuleOutcome.Escalated` - the same enum member the
   unreachable-module path already produces, not a new one. A reachable-but-unsure module and an
   unreachable module both end a conversation's active task the same way from an operator's point of
   view: a human needs to pick this up. Giving them the same outcome value means a future report or
   dashboard already gets both cases by asking "was this conversation escalated", with no code that has
   to know there are two different roads into that state.

## Consequences

- `Ago.Chat.Domain.PrimitiveKinds`, `PrimitiveTextRenderer` and
  `Ago.Chat.Application.UseCases.RouteConversationToModule.RouteConversationToModuleHandler` each gain a
  small, additive change - a constant, a render branch, and a kind comparison plus a force-close. No
  existing kind's behaviour changes, and every existing test in `RouteConversationToModuleHandlerTests`/
  `PrimitiveTextRendererTests` passes unmodified (verified: `19-03`'s own report).
- The wire contract itself - `StepWireDto`/`StartTaskWireResponse`/`SubmitReplyWireResponse` in
  `Ago.Chat.Infrastructure.Modules.ModuleWireContract`, and the mirrored records any module's own API
  returns - needs **zero field changes**. A module that has never heard of escalation (Calendar, today)
  is unaffected; a module that wants to use it just starts returning `"kind": "escalate"` on a step, the
  same way it would start using any primitive it had not used before.
- A future module with a different reason to hand off (not "low confidence" but, say, "this requires a
  human decision by policy") reuses the identical kind - Chat does not need to learn a second escalation
  reason, because the wire signal is "hand off", not "why". A module wanting to explain why to the
  visitor puts that explanation in the step's own `prompt`, which Chat already renders opaquely.
- `KnownModuleKeys` (the architecture guard's hand-maintained allow-list, `ago-chat`) gains `"faq"`.
  `PrimitiveKinds.All` gains `"escalate"`. Neither addition is a literal of a *module's* key inside
  production code - `PrimitiveKinds.Escalate` is Chat's own vocabulary, exactly like the other four, and
  `"faq"` appears only in the guard's own test fixture and in `19-03`'s own repository, never inside
  `Ago.Chat.*` production code (verified by `ModuleKeyLiteralGuardTests`/the IL scan, unmodified, both
  still green against this change).

## Alternatives considered

**A boolean `escalate` flag alongside the existing four kinds**, e.g. `StepWireDto { Kind, Payload,
Actions, Escalate }`. Rejected: it is a second signal doing the same job the `kind` field already does
("what does Chat do with this step"), and it would need a rule for what `Kind` even means when
`Escalate` is `true` (must a module still supply a valid choice-shaped kind it does not want answered?).
One field, one closed vocabulary, stays truer to `adr/0065` decision 4's own "modules fill them in;
modules do not define kinds of their own" than two fields whose combination has to be reasoned about.

**A numeric confidence score Chat compares against a threshold.** Rejected outright: this is exactly the
"Chat opens the payload and decides based on content" design `adr/0065` decision 1 forbids. Where the
threshold lives, what scale it is on, and what "confident enough" means are FAQ's own domain, not Chat's
- the module already knows whether it is confident by the time it builds a step; asking Chat to
re-derive that from a number would duplicate the decision in the one place that must not make it.

**A distinct HTTP status code or response shape for "I don't know."** Rejected: `IModuleGateway`
already treats every non-2xx/malformed response as `ModuleUnreachableException` - reusing that channel
for "the module answered but doesn't know" would make an *expected, common* business outcome (a
question outside the knowledge base) indistinguishable from a *real* infrastructure failure, which is
precisely the distinction operators, alerting and any future retry policy need to keep.

**A new `RouteConversationToModuleOutcome.LowConfidenceEscalated` member, distinct from the existing
`Escalated`.** Considered for the finer-grained signal it would give a future report ("how often does a
module bail out versus go down"). Rejected for `19-03`'s own scope: nothing today reads
`RouteConversationToModuleOutcome` for reporting, and inventing a distinction with no consumer is the
premature generalisation `CLAUDE.md` already warns against. If a real reporting need for the distinction
appears, adding a second outcome value is a small, additive follow-up - the escalate *kind* on the wire
already carries enough information (it is present only on the reachable-but-unsure path) that a future
consumer could derive the finer split without changing this decision.
