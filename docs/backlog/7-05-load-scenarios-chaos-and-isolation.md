# k6: cold-cache stampede, pod-kill mid-load, hanging webhook endpoint

- **Stage**: 7
- **Status**: ready
- **Depends on**: `7-01`, `7-02`, `7-03` (same observability prerequisite as `7-04`), `6-04` (fake CRM
  harness — the `hangs` personality this item's third scenario points at), `6-05` (a real webhook
  dispatcher with a real per-endpoint breaker and per-tenant bulkhead to prove holds under full load,
  not `6-06`'s own smaller rehearsal)

## Goal

After this, three more k6 scenarios prove the system's correctness-under-stress and degradation-path
claims from `nfr.md`, at the real scale `6-06` deliberately did not attempt: a cold-cache thundering
herd stays flat (stampede protection actually holds, not just configured), killing an Api pod and a
Worker pod mid-load loses zero acknowledged messages, and a CRM hanging on every call for the whole run
leaves chat message latency inside its `nfr.md` targets while the breaker and bulkhead visibly do their
job — `6-06`'s own claim, re-proven at the scale that actually stresses a bulkhead rather than a
scaled-down rehearsal of one.

## Context to read first

`nfr.md`'s Correctness under stress section verbatim (each bullet is one scenario's pass/fail bar) and
its Availability behaviour section. `caching.md`'s stampede-protection mechanism — what "cold cache" is
actually testing (the single-flight/lock behaviour, not just a cache-miss counter). `concurrency.md`'s
Graceful shutdown section and `3-06`'s own drain proof — this scenario is that proof at real load, not
a new mechanism. `resilience.md`'s "How this is proven" section, which names this exact rehearsal ("a
fake CRM that hangs... Stage 7 tests each one... the assertion is always about the rest of the system
staying within its latency targets"), and `6-06` itself — read it in full, since this item is
explicitly `6-06`'s own claim re-proven at real scale, not a new design. `6-04`'s fake CRM harness for
exactly what `hangs` does.

## Scope

- **Cold-cache stampede**: flush the relevant Redis keys (site-config, per `caching.md`'s namespace)
  under sustained traffic, assert request latency does not spike proportionally to concurrent
  cache-miss count (stampede protection holding) and that Postgres load stays bounded (single-flight
  actually collapsing the herd, not every concurrent miss hitting the DB).
- **Pod-kill mid-load**: sustained ingest traffic, kill one `Ago.Chat.Api` pod and one
  `Ago.Chat.Worker` pod mid-run (`kubectl delete pod`, matching `nfr.md`'s exact wording), assert zero
  acknowledged-but-lost messages and measure recovery time — the same proof `3-06` did once at small
  scale, now at `nfr.md`'s full scale target.
- **Hanging webhook endpoint**: every registered webhook endpoint set to `6-04`'s `hangs` (30 s)
  personality, sustained chat message traffic for the run's duration, measuring send → ack and
  send → delivered latency against `nfr.md`'s table — `6-06`'s own scenario, rerun at real scale with
  `7-02`'s real per-endpoint breaker-state and bulkhead-rejection metrics now available to confirm the
  mechanism rather than infer it from config.
- Three `load/reports/<date>-<scenario>.md`, same template and bar as `7-04`'s.

## Out of scope

- Redis-down and broker-down-under-load scenarios — already proven once, without full load-test scale,
  in `3-04` (`FLUSHALL` degrades without corrupting anything) and Stage 2's own Done-when (broker
  stopped/started under load, zero acknowledged-but-lost messages). `resilience.md` names both as
  things "Stage 7 tests," but `roadmap.md`'s own Stage 7 scenario list does not include them, and
  re-running an already-proven mechanism at scale without a stated new question would be scope invented
  past what this item was asked to convert — a candidate follow-up item if the author wants it, not
  silently added here.
- Fixing whatever this item finds broken — if the bulkhead does not hold, or a stampede-protection gap
  surfaces, that is a bug for a new backlog item (or `6-05`/`3-04` reopened), not a repair folded into
  this item's own scope, matching `6-06`'s own precedent exactly.
- Any new resilience mechanism — this item measures what `6-01`/`6-05`/`3-04`/`3-06` already built.

## Done when

- [ ] All three scenarios run against the real Kubernetes local cluster at `nfr.md`'s stated topology
      and scale (not `6-06`'s smaller, cheaper rehearsal rate).
- [ ] Three reports in `load/reports/`, each with a plain met/missed verdict against the specific
      `nfr.md` bullet it targets, and — for the webhook scenario specifically — direct evidence (a
      `7-03` dashboard screenshot or a Prometheus query result, not a config read) that the per-endpoint
      breaker opened and the per-tenant bulkhead's cap was actually hit.
- [ ] Any correctness bullet that fails (an acknowledged message lost, a duplicate persisted, an
      operator over capacity) is reported as a real failure with a linked follow-up backlog item, never
      silently retried until it passes.

## Open questions

None.
