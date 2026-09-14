# 25-100 · `TenantSuspension.SessionRefused` has no caller anywhere

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: `dotnet
  format`/`build` clean, full `ago-chat` suite re-run at 3488/3488, `Ago.Chat.Architecture.Tests`
  specifically at 49/49 (confirms the code catalog and exemption list stay in sync after deletion).
- **Depends on**: nothing
- **Found**: 2026-09-14, `25-98`'s own reflection-based audit of every `*Errors`-shaped factory
  method — the one code, of 165, with no caller at all, not even a test.

## What is actually true

`TenantSuspensionErrors.SessionRefused`'s own doc comment claims it is the error
`AuthEndpoints.HandleVisitorSessionAsync` returns when a visitor session is refused for a suspended
tenant. That is not what the code does: `HandleVisitorSessionAsync` hand-builds `Results.Problem`
directly for that refusal and never calls `TenantSuspensionErrors.SessionRefused` at all. Nothing
else in the codebase calls it either — confirmed by `25-98`'s own audit, which found no caller and
no test exercising it.

`25-98` deliberately left this code unmapped in `ErrorExtensions.cs` rather than assigning it a
guessed status: a status for a call nothing makes cannot be shown right or wrong, and giving it one
would be indistinguishable from every other genuinely-reachable code in that file, silently
misrepresenting which lines are load-bearing.

## Why this is worth its own number

`25-98`'s own scope was the audit and the enforcing test, not fixing what the audit found beyond the
33 real HTTP-reachable gaps — CLAUDE.md rule 15, the same reasoning that item's own text already
gives for leaving `Operator.AlreadyRemoved`/`Operator.SeatLimitReached` untouched. This is a second,
unrelated promise: either wire `AuthEndpoints` onto the shared error vocabulary, or delete a method
nothing calls.

## Scope

- Decide which: make `HandleVisitorSessionAsync`'s existing refusal go through
  `TenantSuspensionErrors.SessionRefused` and `ErrorExtensions.ToProblem` like every other refusal in
  this codebase (consistency with the rest of the vocabulary), or delete the unused factory method
  and its doc comment (nothing calls it, so nothing breaks). Either is fine; state which and why.
- If wired in, `25-98`'s own enforcing test (`ErrorCodeMappingTests`) will require it to be given a
  real status line or a reasoned exemption — that test does not need to change for this item.

## Done when

- [x] `TenantSuspension.SessionRefused` either has a real caller going through `ToProblem` with a
      recorded, deliberate status, or no longer exists in the codebase. **Deleted**, not wired in —
      `AuthEndpoints` never went through `Result<T>`/`Error` at all (`3-05`), so wiring this one
      refusal onto `ToProblem` would have made it the sole inconsistent line in a file that
      deliberately hand-builds every one of its own `Results.Problem` calls. The one real fact the
      deleted doc comment carried (why the refusal message is deliberately generic, not
      distinguishing) moved onto the actual live code path in `AuthEndpoints.cs` rather than being
      lost.
