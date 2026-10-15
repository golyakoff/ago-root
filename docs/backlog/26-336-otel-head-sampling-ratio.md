# 26-336 · [ago-platform/observability] a head-sampling fraction for new root traces

- **Stage**: 26
- **Status**: done - shipped in `ago-platform` `2f1f511` (PR #58), released as `Ago.Platform.*` `0.21.0`.
- **Numbering note**: the commit and the `ago-platform` changelog call this `26-332`. That number was
  already taken by `ago-root#1897` (the Android calendar-setup wizard), so the work is recorded here
  under its own number. The merged commit cannot be reworded; **this file is the authority for what
  the `26-332` in `ago-platform` means.**

## What changed

`Otel:Sampling:Ratio` (0..1, default `1`) - the fraction of new root traces recorded. The sampler is
`ParentBased(TraceIdRatioBased(ratio))`: a request that arrives with a `traceparent` keeps its parent's
decision. Out-of-range values fail host startup. Default `1` is exactly today's behaviour.

Head sampling only - the decision is made when the trace starts, so it cannot prefer errors or slow
requests (`adr/0194`). Deciding *after* the outcome is `adr/0193` (a tail-sampling collector, proposed);
with it in the path this ratio stays `1`.

## Done when

- [x] Option + sampler + validation + tests merged in `ago-platform` (`2f1f511`).
- [x] `ago-platform` `CHANGELOG.md` records it under `0.21.0`.
- [x] Decision recorded (`adr/0194`).
- [~] No host sets it yet, deliberately - default `1` is correct until a measured volume problem says
      otherwise (`CLAUDE.md`: no invented numbers). Adoption of the package is `26-337`.
