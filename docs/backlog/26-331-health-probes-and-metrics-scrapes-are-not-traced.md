# 26-331 · [ago-platform/observability] health probes and metrics scrapes are not traced

- **Stage**: 26
- **Status**: done — shipped in `ago-platform` `bc312ac` (PR #58), released as `Ago.Platform.*` `0.21.0`.
  The record arrived after the code: the commit was made under this number without an issue or a
  backlog file, which is the failure `finish-an-item` describes. Written 2026-10-15.
- **Found**: `adr/0057` measured Jaeger's 10000-trace ring turning over in about an hour, almost
  entirely on `/healthz*` probes and `/metrics` scrapes.

## What changed

`AddPlatformObservability` drops inbound `/healthz*` and `/metrics` requests in the ASP.NET Core
tracing instrumentation's filter (`Ago.Platform.Observability.TracePathFilter`). Matching is by path
**segment**, so `/healthzone` is still traced. Request **metrics are unchanged** - probes and scrapes
are still counted there. There is no configuration key (`adr/0193`).

## Done when

- [x] `TracePathFilter` + unit tests merged in `ago-platform` (`bc312ac`, `tests/Ago.Platform.Tests/TracePathFilterTests.cs`).
- [x] `ago-platform` `CHANGELOG.md` records it under `0.21.0`.
- [x] Decision recorded (`adr/0193`).
- [~] Not yet taken by a host - carried out to `26-337`, because adopting a package version is a
      different promise from shipping the feature.
