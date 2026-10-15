# 26-338 · [ago-deploy/observability] a tail-sampling OTel Collector in front of Jaeger

- **Stage**: 26
- **Status**: proposed - waits on the author accepting `adr/0193`.
- **Numbering note**: the first commit of this branch was made as `26-333`, which `ago-root#1898` already
  held. This item is `26-338`; that commit's subject keeps the old number because it cannot be reworded.
- **Follows**: `26-331` (probes not traced) and `26-336` (`Otel:Sampling:Ratio`), both `adr/0194`.

## Why

Head sampling decides before the outcome is known, so lowering the ratio lowers the chance of keeping
the failing or slow trace someone will open. `adr/0193` puts one single-replica Collector between the
hosts and Jaeger and keeps errors, traces over 500 ms and a 10 % baseline.

## Done when

- [ ] `adr/0193` accepted by the author (status line changes; `adr/0025` marked superseded).
- [ ] Collector manifest + `otel-collector-config.yml` in `ago-deploy`, used by both the compose loop and
      the cluster; hosts export OTLP to it, `Otel:Sampling:Ratio` stays `1`.
- [ ] A `load/` run puts numbers on the 500 ms threshold, the 10 % baseline and `decision_wait`, and on
      how many traces a late span splits. Until then they are labelled unmeasured (`CLAUDE.md` rule 7).
- [ ] Verified on the stand: an injected failing request and a slow one are in Jaeger, and a probe is not.
- [ ] `architecture/nfr.md` and `personal-data.md` (Traces row) state the collector as current behaviour.
