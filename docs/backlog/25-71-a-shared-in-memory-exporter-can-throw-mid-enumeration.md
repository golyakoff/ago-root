# 25-71 · A shared in-memory exporter can throw mid-enumeration

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-13, landing `23-76`. Not caused by that item — `git diff origin/main` shows zero
  changes to the affected test or anything it depends on — but that item's own new tests
  (`AttachmentDeduplicatorTests`, a real download over `HttpClient`) added enough concurrent
  HTTP-instrumented traffic to the process that a pre-existing, already-partially-mitigated race
  surfaced during independent verification: `TelegramTraceUrlRedactionTests
  .ARealTelegramCall_NeverPutsTheTokenIntoAnyExportedSpan` failed once out of three full-suite runs with
  `System.InvalidOperationException: Collection was modified; enumeration operation may not execute`.
  Passed clean on both immediate re-runs.

## What is actually true

`OpenTelemetry.Instrumentation.Http`'s `AddHttpClientInstrumentation()` hooks `System.Net.Http`'s own
`DiagnosticSource`, which is **process-wide**, not scoped to whichever `TracerProvider` registered it.
`TelegramTraceUrlRedactionTests` builds its own `TracerProvider` with `AddInMemoryExporter(exported)`
backed by a plain `List<Activity>` — and because the instrumentation observes the whole process, *any*
concurrent `HttpClient` call anywhere in the same test run (xUnit's default parallel test classes) can
append to that same list while this test enumerates it.

The test's own comment already documents one earlier fix for a related symptom (filtering by the fake
Telegram host's own origin, after "a stray POST span from a neighbouring test made it fail on a bare
`Assert.Single`") — but that filter only changes *which* span the test picks once enumeration succeeds.
It does nothing for a concurrent `Add` racing the enumeration itself, which throws before any predicate
ever runs.

## Where this is likely to go wrong

- **This gets more likely to surface as the suite grows**, not less — every new integration test that
  makes a real outbound `HttpClient` call while `AddHttpClientInstrumentation()` is registered anywhere
  in the process is a new source of concurrent writes to this same shared, process-wide diagnostic
  stream. `23-76`'s own dedup consumer test is one instance; it will not be the last.
- **A flaky CI failure that "passes on retry" trains people to re-run rather than investigate** — which
  is exactly how a real regression hides behind this one, later.

## Scope

- Make the exported-spans collection this test reads thread-safe against concurrent appends during
  enumeration — a `ConcurrentBag<Activity>`, or a snapshot (`exported.ToArray()`) taken once before
  filtering, rather than enumerating the live list directly.
- Check whether any other test in this codebase uses `AddInMemoryExporter` the same unguarded way and
  fix it too, rather than patching this one call site alone.

## Done when

- [ ] The same test run under an artificially heavy concurrent `HttpClient` load (or just several
      repeated full-suite runs) does not throw `InvalidOperationException` from this path.
