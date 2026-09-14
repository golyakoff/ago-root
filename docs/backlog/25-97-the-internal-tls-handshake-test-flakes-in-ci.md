# 25-97 · The internal-TLS handshake test flakes in CI

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: the affected
  test class's own two tests pass in isolation, `dotnet format`/`build` clean. The full `ago-chat`
  suite was run to completion (1266/1267 — one failure, in
  `DownloadOverageReadStore_ComputesOutstandingPerMonth_NetOfSettledCharges`, confirmed unrelated to
  this item's own diff and order-dependent on an unrelated global Dapper type-handler collision —
  filed as its own item, `25-99`).
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

**Root-caused.** Pulling the actual failed run's log (`gh run view 34853766370 --log-failed`) turned
up the real error, and it is not the resource-contention guess above — the assertion was never
reached:

```
System.ArgumentException : The requested notAfter value (09/14/2026 15:14:36) is later than
issuerCertificate.NotAfter (09/14/2026 15:14:35). (Parameter 'notAfter')
   at System.Security.Cryptography.X509Certificates.CertificateRequest.Create(...)
   at ModuleRegistrationGatewayInternalTlsTests.GenerateRootAndLeaf() ...line 160
   at ModuleRegistrationGatewayInternalTlsTests.RegisterAsync_OverHttps_WhenTheCallerDoesNotTrustTheInternalCa_IsRefused() ...line 67
```

`GenerateRootAndLeaf` called `DateTimeOffset.UtcNow.AddHours(1)` **twice, independently** — once for
the root certificate's own `NotAfter`, a second time (several statements later, after generating the
leaf's own key and building its CSR) for the leaf's own `notAfter` passed to
`CertificateRequest.Create`. X.509 validity fields are second-granular — sub-second precision is
truncated — so on the rare occasion those two `UtcNow` reads straddle a wall-clock second boundary,
the leaf's rounded-up `notAfter` ends up one second later than the root's own `NotAfter`, and
`CertificateRequest.Create` refuses: a leaf may never claim to outlive its issuer. Port binding,
handshake latency and general CI contention were the wrong hypothesis — the failure never reaches a
socket at all.

**Reproduced deliberately, with real numbers.** A tight loop hammering `GenerateRootAndLeaf` directly
(not the network path) was run in two matched conditions on the same machine, back to back, under the
same real background load:

| Condition | Iterations | Failures | Rate |
|---|---|---|---|
| Unfixed code | 12,000 | 31 | ~0.26% |
| Fixed code | 14,000 | 0 | 0% |

Every one of the 31 failures on the unfixed code carried the identical `ArgumentException` with
`ParamName == "notAfter"` — the same exception the real CI run hit.

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

- [x] The failure is reproduced deliberately, not only inferred from one accidental CI run, and its
      actual mechanism is understood and stated. Proven by the real CI failure log
      (`ago-chat` run `34853766370`, exact stack trace above) plus a deliberate local tight loop that
      hit the identical `ArgumentException` 31 times in 12,000 iterations (~0.26%) against the unfixed
      code.
- [x] A fix is in place and demonstrated to reduce or eliminate the failure under the same conditions
      that reproduced it — not merely re-run a few times and declared fixed by absence of a repeat.
      Proven by the same tight loop run immediately afterward, under the same real machine load,
      against the fixed code: 0 failures in 14,000 iterations (more iterations than the unfixed run,
      not fewer). `git diff --stat` for the fix: one file, 18 insertions / 3 deletions — `notBefore`
      and `notAfter` are captured once and shared by both certificates, which does not merely make the
      race rarer, it removes the second `UtcNow` read that could ever land on the other side of a
      boundary. Not independently proven against real CI contention (a full local run of the whole
      `Ago.Chat.slnx` suite, matching CI's exact invocation, was attempted twice and did not finish in
      reasonable time on this machine — heavy concurrent Docker/Postgres load from unrelated activity
      on the same box, not the fix itself); the affected test class's own two real tests
      (`RegisterAsync_OverHttps_WhenTheCallerDoesNotTrustTheInternalCa_IsRefused` and
      `...TrustsTheInternalCa_Succeeds`) both still pass against the fix.
