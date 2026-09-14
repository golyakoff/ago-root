# 25-97 · The internal-TLS handshake test flakes in CI

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-14, the author directly challenging a CI-failure count during tonight's landing
  work — pulling the actual GitHub Actions run history to check the claim surfaced this: a *second*,
  previously untracked flaky test, distinct from `25-92`'s (already found and fixed the same evening).

## What is actually true

`Ago.Chat.Integration.Tests.ModuleRegistrationGatewayInternalTlsTests.RegisterAsync_OverHttps_WhenTheCallerDoesNotTrustTheInternalCa_IsRefused`
(`23-93`/`adr/0164`) failed once, on a real `push`-triggered CI run against `main`
(`ago-chat` run `34853766370`, commit `20bda1f`). The identical commit's content, rebuilt and rerun
minutes later on a branch carrying no further changes to this file (`ago-chat` run `34853813603`,
commit `f988bd6` — `20bda1f` plus an unrelated diff), passed clean. Same code, two outcomes — the
same signature `25-92`'s own flake had, but this is not that test, and not the same failure shape:
`25-92` was a logic bug (an assertion scoped by a shared timestamp instead of an owned id, genuinely
order-dependent and now fixed for real). This test builds a real in-process Kestrel HTTPS host,
generates a real self-signed leaf certificate, and performs a real TLS handshake against it
(`BuildHttpsModuleHostAsync`) — the kind of test whose nondeterminism is plausibly environmental
(port binding, cert generation timing, handshake latency under CI's own resource contention
alongside dozens of other Integration.Tests in the same collection) rather than a logic error in the
test's own assertions.

**Not yet root-caused.** Unlike `25-92`, this item is filed at the "found and reproduced" stage, not
the "understood and fixed" stage — the mechanism connecting a shared-database order dependency to a
wrong count does not obviously apply here, and guessing at the real cause without evidence would be
exactly the kind of unverified claim this codebase's own conventions warn against.

## Why this is worth its own item

Two independently-caused CI flakes surfacing in the same evening is worth tracking as two items, not
folding the second into `25-92`'s own closed one — `25-92`'s fix and proof are specific to the bug it
actually found (a shared-timestamp-scoped assertion), and reopening that item to also cover an
unrelated TLS-timing question would misrepresent what its own fix actually closes.

## Scope

- Reproduce deliberately (repeated local runs, possibly under artificial CPU/resource pressure to
  simulate CI contention) rather than waiting for another CI accident to supply another data point.
- Identify the actual mechanism — a port bind race, a certificate-generation timing window, a
  handshake timeout too tight for a loaded CI runner, or something else — before deciding a fix.
- Decide the fix shape once the cause is known: a longer timeout, a retry at the test level, an
  isolation change (its own xUnit collection, matching `25-81`'s own precedent if the cause turns out
  to be a resource-sharing issue), or something else entirely — this item does not pre-commit to a
  shape it does not yet have evidence for.

## Done when

- [ ] The failure is reproduced deliberately, not only inferred from one accidental CI run, and its
      actual mechanism is understood and stated.
- [ ] A fix is in place and demonstrated to reduce or eliminate the failure under the same conditions
      that reproduced it — not merely re-run a few times and declared fixed by absence of a repeat.
