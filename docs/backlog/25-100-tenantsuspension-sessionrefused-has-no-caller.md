# 25-100 · `TenantSuspension.SessionRefused` has no caller anywhere

- **Stage**: 25
- **Status**: ready
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

- [ ] `TenantSuspension.SessionRefused` either has a real caller going through `ToProblem` with a
      recorded, deliberate status, or no longer exists in the codebase.
