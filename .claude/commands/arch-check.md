---
description: Audit the working tree for Clean Architecture and project-rule violations
---

Audit the current working tree against the project's architectural rules. Scope: $ARGUMENTS
(if empty, audit everything that differs from `main`).

Check, in this order:

1. Dependency rule — Domain, Application, Infrastructure, Hosts (`clean-architecture-guard` skill).
2. Platform never references a product.
3. Ports declared by their consumer, shaped by the use case, returning no provider types.
4. Async rules: `CancellationToken` everywhere, no sync-over-async, no fire-and-forget
   (`concurrency-review` skill).
5. Time rules: no `DateTime`, no `DateTime.UtcNow` outside Infrastructure, UTC storage
   (`docs/conventions/date-and-time.md`).
6. Writes: state change and integration event in one transaction; consumers idempotent.
7. Docs and ADRs still true after the change.

Report each finding as: file:line, the rule broken, why it matters here, and the smallest compliant
fix. Do not fix anything unless asked. If nothing is wrong, say so plainly rather than inventing
findings.
