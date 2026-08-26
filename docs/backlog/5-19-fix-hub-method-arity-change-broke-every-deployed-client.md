# Fix: `14-06` grew a hub method's parameter list and took visitor messaging down

- **Stage**: 5
- **Status**: done
- **Depends on**: `14-06` (the change being corrected) — `ago-chat` only, no client-side prerequisite

## Goal

Visitor message sending is broken on the live deployment right now: every send fails with a generic
`Failed to invoke 'SendMessageAsync' due to an error on the server`, nothing is logged server-side,
and no message row is ever written. After this item, the deployed widget's sends work again with **no
widget change and no redeploy of any client**, `14-06`'s structured content still has somewhere to
live, and the mistake that caused this is caught by a test on every build instead of by a person
using the product.

## How this was found

Reported from the live deployment after `14-06` merged and shipped. The symptom was diagnostically
distinctive and matched `5-12`'s exactly: the conversation and visitor rows are created fine (so the
connection, the token and `JoinAsync` are all healthy), the send is refused with the *generic*
server-error completion, `SendVisitorMessageHandler` is never reached, and the API logs are silent —
there is no exception to log, because nothing on the server ever ran.

Root cause: `14-06` appended three optional parameters (`contentKind`, `content`, `actions`) to
`SendMessageAsync` on both hubs, taking it from 4 parameters to 7, and justified it in that item's
report with

> SignalR binds hub arguments positionally and fills the rest with their defaults

which is not true. SignalR's `JsonHubProtocol` asks the dispatcher's `IInvocationBinder` for the
target's parameter types and requires **exactly one argument per declared parameter**. A mismatch
produces an `InvocationBindingFailureMessage` during *parsing* — the dispatcher answers it with the
generic completion before it constructs a hub instance, which is why there is no log and no handler
call. A C# `= null` default is optional to a C# caller and mandatory to a caller on the wire. The
deployed widget sends exactly 4 (`ago-widget`'s `VisitorConnection`), so every send in the field
began failing the moment the new API rolled out.

**This is the third time the same fact has been established and the second time it caused an
outage.** `5-07` reasoned about it and got it half-right — it correctly refused to *insert*
`clientMessageId` between existing parameters, and then wrote in `docs/architecture/realtime.md` that
appending it last meant "every caller built before this shipped keeps binding correctly with it
simply omitted." Appending is safe only for a caller that ends up sending *more* arguments than the
method used to declare, which is never the caller already in the field. `5-12` then hit exactly that,
live, and wrote the correction down — as a comment in `ago-widget/src/connection.ts`, a different
repository, which nobody editing a C# hub method has any reason to open. `realtime.md`'s wrong
sentence was never touched, and it is the one an author of a hub change actually reads.

**Blast radius**: the core interaction of the entire product, on every embedded widget, for the whole
window between `14-06`'s deployment and this fix. `ago-console`'s operator sends were broken
identically at the hub layer; they were less visible only because the console is redeployed with the
API and had not yet been rebuilt against a 7-argument call either.

## Scope

- `Ago.Chat.Api/Hubs/VisitorHub.cs`, `OperatorHub.cs`: `SendMessageAsync` restored to its 4-parameter
  form. `14-06`'s structured envelope moves to a **new** 7-parameter `SendStructuredMessageAsync`.
  Both delegate to one private `SendAsync` holding the original body, so there is no second copy of
  the logic and the private method's parameter list is free to grow — it is not a wire contract.
- `Ago.Chat.Integration.Tests/HubMethodArityTests.cs` (new): the regression test. Feeds the deployed
  widget's and console's **exact** 4-argument wire messages through the real `JsonHubProtocol` against
  a binder built by reflection over the real hub types, and fails with the true error text when a
  parameter list has moved. Plus a theory asserting the arity of each method a deployed client calls.
- `Ago.Chat.Architecture.Tests/HubContractTests.cs`, `HubContractManifest.cs`,
  `Fixtures/ArityFixtureHub.cs` (new): the standing guard. Cecil scans every `Hub` subclass and
  compares each invokable method's client-supplied arity against a checked-in manifest — grown,
  shrunk, unlisted, and deleted are four separate assertions with four separate messages. The
  manifest also records *who already calls* each method, which is the fact that decides whether a
  change is free or breaking.
- `docs/architecture/realtime.md`: the rule stated where a hub author reads it, and `5-07`'s wrong
  sentence corrected in place rather than quietly deleted — it is load-bearing evidence for why the
  rule needs a test and not a fourth comment.

## Out of scope

- **Any `ago-widget` change.** Restoring the 4-parameter method fixes the deployed client exactly as
  it stands; a widget on somebody else's site cannot be redeployed on our schedule, which is the
  whole reason the server is the side that has to move. Making the widget send four extra nulls would
  also have worked and is strictly worse: it fixes the one client we can reach and leaves the trap
  armed for every copied embed.
- Giving `SendStructuredMessageAsync` a caller. Nothing sends structured content yet — `20-06` is the
  expected first — so the method ships used only by its own tests. That is the honest cost of not
  putting it on the existing method, and it is much cheaper than the alternative.
- Hub method *versioning* as a general mechanism (`SendMessageV2Async`, a negotiated protocol
  version). Not needed while the answer is "add a method with a name that says what it does", and
  inventing it now would be designing for a second occurrence that has not happened.
- `MessageDto` and every other pushed payload: a DTO's wire shape is bound by name, not position, so
  adding a field to one is additive and safe. Only *hub method parameters* are positional.

## Done when

- [x] The reproduction fails before the fix with the real error — *"Invocation provides 4 argument(s)
      but target expects 7"* on both hubs — and passes after it.
- [x] Every new test demonstrated red by mutation: re-growing `SendMessageAsync` to 7, shrinking
      `GetHistoryAsync`, adding an unlisted method, leaving a deleted one in the manifest, and
      breaking the arity rule into ignoring optional parameters (`14-06`'s exact misunderstanding),
      each turning its intended assertion red and each restored afterwards.
- [x] `dotnet format --verify-no-changes` clean, `dotnet build -c Release` with zero warnings,
      `dotnet test -c Release` with zero failures: 705 tests, up from a 697 baseline.
- [x] The rule is recorded in `docs/architecture/realtime.md`, in this repository, and the wrong
      sentence that survived two outages is corrected rather than removed.

## Open questions

None. The failure was reproduced at the exact layer it occurs, the fix is verified by a test that
fails without it, and the guard is verified by mutation rather than by having been observed to pass —
which matters unusually much here, since the thing that failed last time was trusting a green suite.
