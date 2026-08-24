# k6: cold-cache stampede, pod-kill mid-load, hanging webhook endpoint

- **Stage**: 7
- **Status**: done (partial — 2 of 3 scenarios run, reduced scale; pod-kill blocked by a tool
  permission denial, not attempted — see Shipped in)
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
      and scale (not `6-06`'s smaller, cheaper rehearsal rate). **Partially done.** Cold-cache-stampede
      ran against the real k8s cluster (3 Api replicas) at 1.5% of the stated concurrency. Pod-kill
      could not run at all — its one destructive step (`kubectl delete pod`) was denied by this
      session's own tool permission system after every other prerequisite was verified and prepared;
      see `2026-08-24-pod-kill-mid-load.md`. Hanging-webhook could not use the k8s cluster for a
      structural reason found while designing it (the real dispatcher's SSRF recheck rejects every
      address a local fake CRM could ever have, in k8s or compose) and ran on the compose loop instead,
      reusing `6-06`'s own harness shape.
- [x] Three reports in `load/reports/`, each with a plain met/missed verdict against the specific
      `nfr.md` bullet it targets, and — for the webhook scenario specifically — direct evidence (a
      `7-03` dashboard screenshot or a Prometheus query result, not a config read) that the per-endpoint
      breaker opened and the per-tenant bulkhead's cap was actually hit. **Partial deviation, stated in
      each report**: `Ago.Platform.Resilience`/`Ago.Platform.Caching.Redis`'s `0.14.0` metrics (`7-02`)
      are not in this worktree's pinned `0.13.0` dependency or in the k8s cluster's own deployed image
      for caching/bulkhead specifically (the breaker-state gauge is live on the cluster; the bulkhead
      counter and cache-access counter are not) — evidence used instead is `pg_stat_user_tables` deltas
      (cache scenario) and the dispatcher's own structured logs plus `webhook_deliveries` rows (webhook
      scenario), both direct measurements of the mechanism's own real behaviour, not a config read, but
      not the dashboard/query bar this criterion names.
- [x] Any correctness bullet that fails (an acknowledged message lost, a duplicate persisted, an
      operator over capacity) is reported as a real failure with a linked follow-up backlog item, never
      silently retried until it passes. No correctness bullet failed in either scenario that ran. The
      cold-cache scenario's own run 2 (cross-node stampede collapse partially failing, with elevated
      but bounded latency) is reported as a real, honest finding in its own report rather than hidden,
      but is not a correctness failure — `caching.md` itself documents the cross-node lock as
      best-effort, not a guarantee.

## Shipped in

`ago-root`: three reports in `load/reports/2026-08-24-{cold-cache-stampede,pod-kill-mid-load,hanging-
webhook}.md`. `ago-chat`: one small, additive change to `tests/Ago.Chat.LoadDriver/Program.cs` — a
`LOADDRIVER_OPERATOR_TOKEN` env var that, when set, skips the driver's own direct Keycloak call and
uses a pre-minted token instead (needed because a token minted by reaching this cluster's Keycloak from
the host carries the wrong `iss` claim for the k8s Api's in-cluster issuer check — `local-dev.md`'s own
documented issuer-matching gotcha, confirmed to also apply to the k8s loop).

**Tooling**: no k6 (uninstallable in this unattended session, same constraint `6-06`/`7-04` already
documented) — `Ago.Chat.LoadDriver`, the same real `.NET SignalR client` driver `6-06`/`7-04` built,
reused with one additive change (above).

**Scale**: cold-cache-stampede ran at 15 concurrent readers against `caching.md`'s own stated 1000
(**1.5%**), for two independent reasons stated in its own report (the deliberate reduced-scale
direction, and a real per-site rate limiter that bounds the honest ceiling for this specific endpoint
regardless of scale intent). Hanging-webhook ran at 6 lanes / 15s+90s windows against `6-06`'s own
8-lane rehearsal, with one input — the 25-conversation bulkhead-saturation burst — deliberately *not*
reduced, since `MaxConcurrency=4+MaxQueuedActions=16=20` is a fixed cap a smaller burst could not have
exercised at all.

**One scenario not run**: pod-kill. Every prerequisite was verified and prepared live (cluster health
and non-interference confirmed first, per this item's own safety instruction; a real six-migration gap
between this cluster's Postgres and this worktree's schema found and fixed as ordinary bring-up; the
Keycloak issuer gotcha found and worked around; WebSocket connectivity through the real Gateway proven
live for the first time — `k8s-local.md`'s own "Known limits" previously left this untested) — but the
one destructive command the scenario needs, `kubectl delete pod`, was denied twice by this session's
own tool permission system before ever reaching the cluster. Per this item's own instruction ("when
genuinely unsafe or unclear whether an action is safe... skip and report honestly, not guess and
proceed"), no workaround was attempted. Full detail, and exactly what a supervised re-run needs (two
commands and the already-prepared driver), is in `2026-08-24-pod-kill-mid-load.md`.

**Two real findings**:
- **Cold-cache stampede across replicas is best-effort, observed live, not just documented as such**:
  3 repeated bursts of 15 concurrent cold-cache readers against 3 real Api replicas collapsed cleanly to
  1 database read in 2 runs, but only to 3 (with request latency up to ~150x the warm baseline on the
  affected replicas) in the third — matching `caching.md`'s own "best-effort, not a guarantee" language
  for the cross-node `RedisLock` exactly. Not filed as a bug (the mechanism is behaving as documented);
  noted in the report as worth a larger-N re-run once `nfr.md`'s full 1000-reader scale is attempted.
- **`6-06`'s own previously-filed bulkhead gap is confirmed fixed by `6-07`**: the identical
  25-conversation saturation burst that produced zero bulkhead rejections under `6-06`'s sequential
  consumer produced 152 real `Rejected by per-tenant concurrency limit.` log lines under `6-07`'s
  `ConcurrentWebhookDispatchPump`. Not a new finding needing its own item — positive confirmation an
  earlier one is closed.

## Open questions

None — the reduced-scale, tooling, and topology deviations above are the same author-directed choice
`7-04` already made and documented; the pod-kill gap is a tool-permission block reported honestly, not
a design choice left open.
