# 25-99 · A stray static Dapper type handler breaks a sibling test's `DateOnly` read

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: rebased onto
  current `main`, `dotnet format`/`build` clean, full `ago-chat` suite re-run at 3482/3482 (0 failed,
  0 skipped — the interim `25-99` skip added to unblock a deploy is also removed by this fix and the
  previously-skipped test now genuinely passes).
- **Depends on**: nothing
- **Found**: 2026-09-14, independently re-verifying `25-97` — the managing session's own full
  `dotnet test` run (post-rebase onto `25-84`) failed once, on a test `25-97`'s own diff never
  touches. Confirmed unrelated to `25-97`: the same test passes cleanly when filtered to run alone.

## What is actually true

`MessageRetentionArchiveEndToEndTests`'s own static constructor calls
`SqlMapper.AddTypeHandler(new DateOnlyTypeHandler())` — a **global, process-wide** Dapper
registration, per Dapper's own documented behaviour, not scoped to that test class or file. That
handler's own `Parse` does `DateOnly.FromDateTime((DateTime)value)`, on the assumption that Npgsql
hands Dapper a `System.DateTime` for a `date` column.

`DownloadOverageReadStore`'s own row mapper (`25-84`, `GetOutstandingAsync`) relies on the *opposite*
assumption, stated in its own doc comment and confirmed correct on its own: "a `date` column reads
back as a `DateOnly` (Npgsql maps it natively)" — i.e. Dapper's ordinary, un-overridden behaviour for
this column type already works, with no custom handler needed.

Both are right about their own corner, and that is exactly the problem: whichever test class's
static constructor runs first in the shared test process decides which behaviour is live for **every
other test in the assembly**, for the rest of that process's life. When
`MessageRetentionArchiveEndToEndTests` happens to load before `DownloadOverageReadStore`'s own tests
run, its handler is already registered, Dapper hands it a native `DateOnly` (not the `DateTime` it
was written for), and `(DateTime)value` throws `InvalidCastException` inside the handler's own
`Parse` — surfaced as `System.Data.DataException: Error parsing column 0 (PeriodMonth=... -
DateOnly)`.

**Confirmed order-dependent, not a logic bug in either file alone**: filtering the test run to just
`DownloadOverageReadStore_ComputesOutstandingPerMonth_NetOfSettledCharges` passes clean, every time -
`MessageRetentionArchiveEndToEndTests`'s own static constructor never runs, so Dapper's own native
`DateOnly` handling stays in effect. The full-assembly run is what exposes it, and only when xUnit's
own (undocumented, not guaranteed) class-discovery order happens to load the offending class first.

## Why this is worth its own item

This is the third instance tonight of the same *shape* of bug - shared, unscoped state a test
mutates and never isolates (`25-81`: a static Mono.Cecil resolver; `25-92`: a shared hardcoded
timestamp with no per-test id scoping; this one: a global Dapper type-handler registry) - but a
different mechanism each time, so each earned its own fix rather than a shared one. Folding this into
`25-92`'s own closed item would misrepresent what that item's fix actually covers.

## Scope

- Decide the fix shape: scope `DateOnlyTypeHandler`'s registration to only the tests that actually
  need it (if any genuinely do — check whether `MessageRetentionArchiveEndToEndTests` itself still
  needs a custom handler at all, or whether it was written before Npgsql's own native `DateOnly`
  mapping existed and is now redundant), or make the handler correctly accept *both* a `DateOnly` and
  a `DateTime` input so it stops assuming one shape.
- If the handler turns out to still be needed for a genuine reason, isolate its registration so it
  cannot leak into other test classes' own connections - Dapper's `AddTypeHandler` has no per-scope
  variant, so this may mean removing the static registration and passing the handler explicitly only
  where `MessageRetentionArchiveEndToEndTests` itself needs it, or another mechanism entirely; this
  item does not presuppose which.
- Check for other static `SqlMapper.AddTypeHandler`/similar global-registration calls across
  `Ago.Chat.Integration.Tests` while in the area — this may not be the only one, and the item's own
  Done-when should say plainly whether a broader check found more.

## Done when

- [x] The two behaviours (native `DateOnly` mapping, `MessageRetentionArchiveEndToEndTests`'s own
      custom handling if it is still needed at all) no longer collide regardless of test execution
      order - proven by running the full `Ago.Chat.Integration.Tests` assembly repeatedly (not once,
      since the failure is order-dependent) and confirming `DownloadOverageReadStore`'s own tests
      never hit it. Confirmed genuinely needed (removing the registration reproduces a
      `NotSupportedException` on the `periodStart` parameter Dapper cannot otherwise bind), so the fix
      reuses the already-hardened `DapperDateOnlyTypeHandler` (`23-07`) instead of the ad-hoc class -
      correct for every caller regardless of registration order, already designed for idempotent
      multi-site registration. `Ago.Chat.Integration.Tests` run 7 times in a row by the worker (6
      fully green at 1267/1267, one unrelated Docker port-binding flake), plus the managing session's
      own independent full-suite re-run at 3482/3482.
- [x] A scan for other global, unscoped Dapper type-handler registrations in this test project found
      none left unaddressed beyond the one fixed here.
