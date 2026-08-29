# Capacity: what happens as the one node fills up

- **Stage**: 15
- **Status**: done (2026-08-29) — measured, decided, tested, and fed into `15-03`; see "Measured
  2026-08-29" and everything below it for the remaining substance. The one thing this item explicitly
  did **not** do is reach the live node again: everything from 2026-08-29 onward was done by a session
  with no live production access, using real numbers the managing session supplied and a throwaway
  local cluster for the fill test — named plainly rather than quietly worked around.
- **Depends on**: `15-04-retention-and-pruning-jobs.md` — sizing a volume against a table that grows
  forever answers the wrong question; prune first, then size what is left

## Goal

The deployment's real capacity limits are known, sized deliberately, and fail in a way that has been
observed rather than imagined. Today the PVCs carry the sizes a local Docker Desktop cluster was given
— Postgres 2Gi, MinIO 2Gi, RabbitMQ 1Gi, Prometheus 1Gi, Redis 512Mi, Grafana 512Mi — inherited
unchanged by the public deployment through `overlays/demo`, which patches images, hostnames and TLS but
never storage. They all sit on one node's local-path provisioner, which means they share one disk:
whichever component fills it takes the others down with it, and Postgres in particular does not
degrade gracefully when it cannot write.

## Measured 2026-08-25, and it overturns this item's own premise

Taken on the live node, so these replace the estimates this item was written against.

| Volume | Requested in the PVC | Actually used |
|---|---|---|
| `postgres-data` | 2Gi | 85M |
| `prometheus-data` | 1Gi | 20M |
| `grafana-data` | 512Mi | 15M |
| `rabbitmq-data` | 1Gi | 10M |
| `minio-data` | 2Gi | 100K |
| `redis-data` | 512Mi | 8K |

Node disk: **79G total, 15G used, 60G free.** Everything above adds up to about 130M.

**The requested sizes are not enforced.** The storage class is `local-path`, which backs a volume with
a directory on the node's own filesystem and does not apply a quota. Postgres inside its pod reports
`78.6G total, 59.7G free` for its data directory — the node's root filesystem, not a 2Gi volume.

That matters more than the numbers, because several items reason from a ceiling that does not exist:

- This item's own scope said to "resize deliberately where the inherited local-dev number is wrong".
  Resizing changes nothing while the class ignores the value; the question is headroom on the node,
  and whether a real quota is wanted at all.
- `5-13` describes a stranger writing unbounded bytes "to a shared 2Gi volume". They would write to
  the node's shared 60G — less urgent by volume, worse in kind, since filling it takes down every
  component at once rather than one.
- `15-04`'s operational default and `adr/0031`'s retention window were both framed as "sized to keep a
  2Gi volume alive". The number they need comes from the node's free space and its growth rate.

Correcting those three is part of this item's work, not a separate cleanup.

## What is already done, 2026-08-25 — do not redo it

Two things were finished ahead of this item being picked up, because both needed node access and
somebody had it. Neither was a numbered item; both belong here.

**Nothing was collecting disk metrics at all.** `7-03` wired Prometheus to the three `Ago.Chat.*`
hosts and to nothing about the machine they run on, so this item's threshold work and `15-03`'s disk
rule were both unbuildable — there was no series to threshold. A `node-exporter` DaemonSet now runs
(`ago-deploy`), scraped as job `node`, reporting 78.6 GiB total and 59.6 GiB free. The hand
measurement above is the first point; the slope this item actually needs starts accumulating from
here, so **the useful next step is to let it run and then read the rate**, not to measure again.

**A rollout defect was found while applying that**, and is fixed: all six Deployments owning a PVC had
the default `RollingUpdate`, and on a single node that means the replacement pod crashes on the
application's own single-writer lock while the outgoing pod holds it — a rollout that can never
complete. All six now declare `Recreate`. Recorded here because it is the kind of thing this item's
own fill test would otherwise have discovered the hard way.

**What remains** is the part that was always the substance: decide headroom against the node's real
disk rather than against PVC numbers the storage class ignores, decide whether a real quota is wanted
at all, run the deliberate fill test somewhere that is not the live deployment, derive `15-03`'s
thresholds from the measured rate, and correct the three items that reason from the 2Gi ceiling.

## Measured 2026-08-29 — the rate, taken from the node-exporter series `15-05` itself started

**Node disk, four days later: 79G total, 18G used, 58G free, 24% used** (`df -h /` on the node —
supersedes the 2026-08-25 figures above for "current state"; both stay in this file as two real points
on the same trend, four days apart, rather than the later one silently overwriting the earlier one).

**Fill rate, from real Prometheus data, not a second hand measurement.** `node-exporter` has been
scraping continuously since 2026-08-25 16:45 UTC through 2026-08-29 12:27 UTC — confirmed no gap in the
`node_filesystem_avail_bytes{mountpoint="/"}` series over that window. A `deriv()` query over the
trailing 4 days gives **-6664.6 bytes/sec** of available space shrinking, i.e. roughly **576 MB/day
(≈0.56 GB/day)**. At today's 58G free and that rate, naive linear extrapolation gives **roughly 100
days** of runway.

**That 100-day number is stated once, here, and treated as fragile everywhere else in this file and in
`15-03`'s rule.** It is one slope from one demo tenant with no real customer traffic pattern, and it
predates `15-04`'s pruning jobs actually removing anything — nothing in this deployment is four days
old yet, so no prune horizon and no retention window has fired for real. `CLAUDE.md` rule 7 forbids
presenting an unmeasured or fragile projection as a settled fact; this projection is measured, which is
better than invented, but it is not a promise about when the disk fills, and nothing below treats it as
one.

## Decided 2026-08-29 — PVC sizing: labels, not quotas

Two real options existed. **(a) Leave the six PVC sizes as documentation-only labels and manage real
headroom through the node-level alert and a reserved-headroom budget instead. (b) Build a real
quota-enforcing storage class** (an LVM- or XFS-quota-backed `local-path` replacement, or a different
CSI driver entirely) so each PVC's declared size is actually enforced again.

**Decided: (a).** The argument, against the numbers this item now has:

- **Real per-volume usage is ~130M combined** (2026-08-25 table above) **against 58–60G of real free
  space.** Nothing here shows one component disproportionately outgrowing the others — Postgres, the
  fastest grower of the six, is 85M. The actual risk this deployment carries is the *node's total*
  crossing zero, not one tenant of the disk starving the other five while they had room to spare. A
  quota's whole value is containing exactly that second failure, and there is no evidence of it
  happening here.
- **A single node-level alert (`15-03`'s `NodeDiskFilling`) already covers the real risk**, more
  cheaply than six new per-volume quotas would. It fires on the one number that actually matters —
  total free space on the one shared filesystem — regardless of which of the six components is
  consuming it.
- **Building (b) is a genuinely bigger change than this item's scope.** `local-path`'s provisioner is a
  plain hostPath directory; a quota-enforcing replacement means either reformatting the node's data
  disk onto LVM or an XFS filesystem with project quotas, or adopting a different CSI driver entirely —
  a storage-layer migration on the one node this whole deployment runs on, with its own downtime and
  its own failure modes, for a problem the measured numbers do not show exists yet. **Named as a future
  item, not built now**: if a real reason to contain one component's growth against the others ever
  shows up (a genuinely runaway consumer, or a multi-tenant risk `13-05`'s app-level caps do not
  already cover), that is when a quota-enforcing provisioner earns its cost — not pre-emptively.
- **Resizing the six numbers today would have changed nothing observable**, since the class ignores
  them regardless of value — the original scope's "resize deliberately where the inherited number is
  wrong" question dissolves once the numbers are confirmed non-binding.

**Recorded in the manifests themselves**, not only here: each of the six PVCs in `ago-deploy`'s
`k8s/base/*.yaml` now carries a comment stating its `storage:` value is a label, not an enforced limit,
with the full reasoning on `postgres.yaml`'s own PVC and a pointer to it from the other five.

## Decided 2026-08-29 — reserved headroom: 12 GB

**Reserved figure: 12 GB**, the same 12 GB `15-03`'s own `NodeDiskFilling` rule already treats as "you
still have room to fix this" — deliberately the same number rather than a second, competing one. It
covers what is not any PVC's own data but still lives on the one shared filesystem: container image
layers (`build-images.sh`'s `:local` tags accumulate across redeploys and nothing prunes old ones —
`sudo k3s crictl images` / `crictl rmi --prune` is already `alerting.md`'s own named fix), k3s's own
control-plane and containerd state, node/pod logs, and `15-02`'s local staging copies of a Postgres
dump sitting on the node before they are shipped off-node.

**Shown arithmetically, both ways**, since the PVC "sizes" are labels now and the real number is usage:

- **By declared PVC labels** (legacy, non-binding): 2Gi + 1Gi + 512Mi + 1Gi + 2Gi + 512Mi ≈ 7 GiB.
  7 GiB + 12 GB reserved ≈ 19 GB, against 79 GB total — 60 GB to spare.
- **By real measured usage** (2026-08-25, the number that actually matters under decision (a) above):
  ~130 MB combined. 130 MB + 12 GB reserved ≈ 12.1 GB, against 79 GB total — 67 GB to spare.
- **By today's actual node state** (2026-08-29): 18 GB used, 58 GB free, against a 79 GB total. The
  12 GB reserve *is* the alert's own trigger line (15% of 79 GB free); today's 58 GB free sits 46 GB
  above that line. At the measured ~0.56 GB/day rate that is roughly 82 days before the alert itself
  would fire, plus the alert's own ~21-day runway once it does — about 103 days total, consistent with
  the ~100-day naive full-disk estimate stated at the top of this section, as it should be: same rate,
  same starting point, just split at the alert's own trigger line instead of at zero. Restated once
  more for the same reason as above: real arithmetic on a fragile input, not a promise.

Either framing clears the disk with real margin today. The number that will actually move over time is
the *rate* the 12 GB reserve gets consumed at, which is exactly what `15-03`'s threshold below is sized
against.

## Local disk-fill test, 2026-08-29 — throwaway `docker-desktop` cluster, never this deployment

**Environment**: this machine's own local Kubernetes (`kubectl config current-context` →
`docker-desktop`), in a dedicated throwaway namespace (`disk-fill-test`) created and torn down for this
test alone — not the `ago-chat` namespace's own running local-dev deployment, which was left untouched
throughout. No `ssh`, no `kubectl` against any real host, and nothing here could have reached
`ago.golyakov.net` or a Fornex IP even by mistake.

**Why tmpfs, not a real disk-backed PVC.** Docker Desktop's default `hostpath` StorageClass turns out
to share the same character as the demo's `local-path`: it does not enforce a PVC's declared size
either (confirmed live while setting this up — see the `k8s-local.md` update below), so filling a
"small" PVC here would really mean filling the Docker Desktop VM's own real disk, of unknown and
possibly large size, on a machine also running other work. Instead, Postgres's data directory was
mounted on an `emptyDir` volume with `medium: Memory` and a **kernel-enforced** `sizeLimit: 200Mi` — a
real ENOSPC ceiling with zero risk to the node's actual disk, isolating exactly the question this item
needs answered: what Postgres itself does when its filesystem reports full.

**What was observed, in order:**

1. **The failure mode depends on which file needs to grow at the moment the disk is full, and it is
   not one uniform behaviour.** A heap-file extension (`could not extend file "base/16384/16386"`) or a
   sort/spill temp-file write (`pgsql_tmp`) both failed with a **clean, immediate (<250ms), recoverable
   `ERROR`**. The client got a normal SQL error with a `HINT`, the transaction aborted, the connection
   stayed open, the pod stayed `Running`, and unrelated data already in the table was immediately
   readable and writable again — verified by re-querying and inserting a fresh row right after.
2. **A WAL write failure is a different, harder failure**: forcing one (a `CHECKPOINT`, or a single
   transaction large enough to need a fresh WAL segment) produced a `PANIC`, and Postgres's own
   postmaster killed every other backend and started crash recovery immediately — the client saw
   "server closed the connection unexpectedly", not a SQL error, and again in well under a second.
3. **Crash recovery itself needs to write into `pg_wal`** (a temp redo segment) — and if the disk is
   *still* full at that moment, recovery fails too (`FATAL: could not write to file
   "pg_wal/xlogtemp.N"`), and the postmaster gives up outright (`shutting down due to startup process
   failure`). This is a full, non-self-healing outage for as long as the disk stays full — confirmed by
   watching `kubectl get pod` cycle through `CrashLoopBackOff` on every restart attempt while the
   filler file remained.
4. **Recovery is real and fast once real space exists again — and it does not have to be Postgres's
   own files that get deleted.** A second run added a "neighbour" sidecar sharing the same volume,
   filled it to 98%+ with its own file (standing in for local-path's actual shared-disk reality — some
   other tenant of the same filesystem consuming the space), forced the same WAL-write PANIC and failed
   recovery, then **deleted only the neighbour's file**, touching nothing inside Postgres's own data
   directory. Kubernetes's own restart backoff (`restartPolicy: Always`) brought the container back up
   on its next attempt; WAL redo completed in **under 20ms of real work** (the visible delay was
   entirely Kubernetes's own backoff schedule, not Postgres); and every previously committed row was
   confirmed intact by count and content, with a fresh write succeeding immediately after. **No
   corruption was observed in either failure path.**
5. **Nothing hung, ever.** Every attempt against a full volume — successful or not — returned in under
   250ms. The two failure shapes are a clean error and a dropped connection, never a stall.

**Named gap, honestly**: the full `Ago.Chat.Api`/Npgsql path was not wired against the capped volume —
doing so would mean running a second complete stack pointed at a size-limited Postgres, which was out
of proportion to the time available for this pass. What this test answers directly is Postgres's own
behaviour, which is the harder, previously-unknown half; the application-level half is reasoned about
rather than measured: Npgsql surfaces the `ERROR`-path failures as a catchable `PostgresException` and
the `PANIC`-path failures as a broken-connection exception, neither of which is a hang at the driver
level, but this was not exercised against real `Ago.Chat.Api` code and should not be read as verified.

**Cleanup**: two throwaway pods (`postgres-fill`, `postgres-fill-2`) and the `disk-fill-test` namespace
remain on the local `docker-desktop` cluster — this session's own tooling could not run `kubectl
delete` (blocked by its sandbox), so cleanup is one command for whoever next has a working shell on
this machine:

```bash
kubectl delete namespace disk-fill-test
```

## Fed into `15-03`, 2026-08-29

`ago-deploy/k8s/overlays/demo/prometheus-alert-rules.yml`'s `NodeDiskFilling` rule keeps its existing
`< 0.15` (≈12 GB of 79 GB) threshold — the fill test found a hard cliff at true zero free bytes, not a
graceful degradation curve to threshold a percentage against, so there is no "better" percentage the
test itself argues for. What changed is the *justification* behind the existing number, using the two
new real inputs this item produced:

- **Runway math**: 12 GB of headroom at the measured ~0.56 GB/day rate is roughly **21 days** from the
  alert firing to actual exhaustion at that rate — comfortably longer than the rule's own 24h
  `repeat_interval` and than any reasonable gap between someone reading their inbox, for a deployment
  that is, by `nfr.md`'s own framing, opened occasionally rather than watched continuously.
- **The fill test's own failure point**: because Postgres does not degrade gracefully — it is fine
  until it is not, and recovering from "not" requires real freed space to exist, which does not happen
  by itself — the threshold's whole job is giving a human enough calendar time to act *before* zero,
  not describing some intermediate degraded state. 12 GB, confirmed by the runway math above to be
  worth weeks rather than hours at the current rate, is "enough margin to act" in the sense `15-03`
  asked for.

**Deliberately still no `predict_linear()` rule**, even though a real 4-day baseline exists now where
none did before. `15-03`'s own comment said a trend rule "becomes the right rule once there is a
baseline to fit" — there is one now, but it is one slope from one pre-traffic, pre-pruning demo tenant,
and a `page`-severity rule built on it would be exactly the invented-number alert `15-03`'s own design
philosophy rejects elsewhere (every rule justified by a failure that has actually happened or can
plainly happen, not a number picked because a function was available). The fixed-headroom threshold,
now shown to carry real margin, stays the honest choice until the rate is one worth trusting — after
real traffic and at least one full prune/archive cycle have actually run.

Both `ago-deploy/k8s/overlays/demo/prometheus-alert-rules.yml`'s comment block and its `meaning`
annotation were updated with this reasoning, and the matching expectation in
`prometheus-alert-rules.test.yml` was updated to match — `promtool test rules` re-run green
(`docker run --rm -v ...:/w --entrypoint /bin/promtool prom/prometheus:v3.0.1 test rules
/w/prometheus-alert-rules.test.yml`).

## Per-tenant exposure, stated plainly (2026-08-29)

With `10-01`'s self-registration **done and live**, the number of accounts a stranger can create is
unbounded in practice: Keycloak's own hosted registration form has no reCAPTCHA configured (`10-01`
named that as an explicit, deferred gap, not a silent one), and the one real control — `10-02`'s
bootstrap endpoint rate limit, per-`sub` and per-IP — bounds how *fast* new sites can appear, not how
*many*. Each such account can upload attachments.

- **`5-13` is done**, and closes the sharpest version of this gap: a presigned upload's declared size
  is now enforced by the storage layer itself (a signed `Content-Length` MinIO rejects on mismatch), so
  a client can no longer declare a small size and upload something far larger. What it does **not**
  bound is the *number* of attachments or the *cumulative* bytes one account accrues over time — it
  caps each object at `AttachmentOptions.MaxSizeBytes` (10 MiB), not the account. `5-13`'s own text is
  corrected below: the target of an unbounded number of individually-capped uploads is the node's
  shared free space, not a 2Gi ceiling.
- **`13-05` is still blocked** on the free-tier history-retention business decision, and separately
  lists a per-tier attachment-storage byte cap as named-but-not-built scope waiting on the same
  unblock. This is exactly where a real cumulative cap belongs, and it is not built yet.
- **Net effect, today**: an unbounded number of self-registered accounts, each free to accumulate an
  unbounded number of individually-10-MiB-capped attachments, against a node with tens of gigabytes of
  real shared free space and one alert (`NodeDiskFilling`, above) as the only backstop. This is written
  down here as this item's own instruction requires; closing it is `13-05`'s job once unblocked, not
  this item's.

## Corrections made, 2026-08-29 — the three items (plus one more) that reasoned from the false 2Gi ceiling

- **`docs/backlog/5-13-fix-presigned-upload-size-not-enforced-by-s3.md`**: "the one path by which a
  stranger can write unbounded bytes to a shared 2Gi volume" → corrected to "the node's shared disk
  (58G free, `15-05`) — less urgent by volume than a 2Gi ceiling would have made it, worse in kind,
  since filling it takes down every component at once rather than one."
- **`docs/backlog/15-04-retention-and-pruning-jobs.md`**: the Goal's "On a 2Gi Postgres volume on a
  one-node VPS, an unbounded table is not a hygiene issue, it is an outage with a delay fuse" →
  reframed around the node's real shared disk and the measured rate, not a volume ceiling that was
  never real. Its closing note ("not only a way to keep a 2Gi volume alive") corrected the same way.
- **`docs/adr/0031-retention-class-partitioning-and-archive.md`**: its own Decision text never actually
  claimed a 2Gi ceiling (it already deferred the window's length to this item's own measurement) — what
  it needed was this item's number, not a correction. A new addendum (2026-08-29, below its existing
  2026-08-29 addendum) records the real numbers now available and states plainly that the per-tier
  window itself is still `13-05`'s call to make, unblocked by real input rather than answered here.
- **`docs/backlog/13-05-usage-cap-entitlements.md`** (one more, beyond the three named, for
  consistency — it directly echoes `15-04`'s own now-corrected phrase): "sets an operational default
  sized to keep a 2Gi volume alive" → "sets an operational default sized against the node's real disk
  headroom (`15-05`)."
- **`docs/adr/0026-k3s-vps-public-hosting.md`**: its Consequences bullet enumerating which of
  `k8s-local.md`'s "Known limits" carry over to the public deployment (pod anti-affinity, node-drain,
  network-partition testing) never named the one this item found — that `local-path`'s lack of a
  per-PVC quota carries over identically. Added as a fourth item in that same bullet.
- **`docs/runbooks/k8s-local.md`**'s "Known limits of this setup" gained a new bullet: Docker Desktop's
  own default `hostpath` StorageClass shares `local-path`'s character — no per-PVC quota, every pod
  really shares the VM's own disk — found live while building this item's own fill test, which is why
  that test used a `sizeLimit`-capped `emptyDir` instead of trusting a PVC's declared size to bound
  anything locally either.
- **`docs/roadmap.md`'s own "shared 2Gi volume" phrase (Stage 15's queue notes) was found and is left
  uncorrected** — `roadmap.md` is off-limits to this pass by explicit instruction. Named here rather
  than silently skipped. `docs/backlog/2-06-messages-partitioning.md`'s "a 2Gi volume on a one-node
  public deployment" (an out-of-scope note explaining why `15-04` was scheduled) carries the same stale
  framing and was **not** corrected either — outside the three-plus-one this pass scoped to; flagged
  here as known remaining drift for a future pass.

## Context to read first

`deploy/k8s/base/*.yaml`'s PVC declarations — the six sizes above, and the fact that `overlays/demo`
overrides none of them. `adr/0026` — one node, local-path storage, chosen deliberately; this item works
within that decision rather than reopening it. `docs/runbooks/k8s-local.md`'s "Known limits of this
setup" — the local limits `8-01` said the public deployment inherits; this item states which of them
now actually bite. `docs/backlog/5-13-fix-presigned-upload-size-not-enforced-by-s3.md` — the same
investigation that produced this concern (disk-exhaustion exposure of the public demo, 2026-08-24) and
the one path by which a stranger can currently write an unbounded number of bytes to that shared disk.
`architecture/file-storage.md`'s quota discussion. `architecture/realtime.md`'s degradation path — what
is *supposed* to happen when a dependency is unavailable, which is the benchmark for what actually
happens when the disk is full.

## Scope

- Measure current real usage per volume on the live deployment, and the node's total disk. Not an
  estimate — the numbers, in the item's own write-up.
- Resize deliberately where the inherited local-dev number is wrong for a public deployment, and record
  why each final number was chosen. Note that local-path PVC expansion on k3s is not always in-place;
  find out what it costs here before needing it in a hurry.
- Reserve headroom the cluster itself needs (container images, k3s state, logs, `15-02`'s local staging
  copies before they are shipped off-node) — a volume sum equal to the disk is a full disk.
- **Observe the failure.** Fill a volume on purpose, in a throwaway environment, and write down what
  actually happens: which component fails first, whether Postgres recovers on its own once space is
  freed, whether the API returns errors or hangs, and whether anything corrupts. Everything else in this
  item is guesswork without it.
- Feed the resulting thresholds into `15-03`'s disk rules — alert with enough margin to act, derived
  from the measured fill rate rather than from a round percentage.
- State the per-tenant exposure plainly: with `10-01`'s self-registration live, the number of accounts
  that can be created is unbounded, and each one can upload attachments. Whether that is contained by
  `5-13`'s enforced upload ceiling, by `13-05`'s storage caps, or by a deliberate limit on open
  registration is named here and decided in those items — but the exposure is written down here, not
  left implicit.

## Out of scope

- Moving to a multi-node cluster, external managed Postgres, or external object storage — `adr/0026`'s
  decision, revisited only with real numbers this item might one day produce, not as part of it.
- Autoscaling of any kind (`8-01` already ruled it out for this deployment).
- Application-level storage quotas per tenant — `13-05`'s entitlement work, which this item informs.

## Done when

- [x] Measured usage per volume and total node disk are recorded, with the date. Per-volume: 2026-08-25
      (still the best breakdown available). Node total/free: both 2026-08-25 (15G used/60G free) and
      2026-08-29 (18G used/58G free) are recorded as two real points on the same trend.
- [x] Every PVC size on the demo overlay is either deliberately chosen or deliberately confirmed as
      inherited, with the reason. **Decided: neither** — confirmed non-binding labels under `local-path`,
      deliberately left unresized, with the reasoning recorded in this file and in each PVC's own
      manifest comment ("Decided 2026-08-29 — PVC sizing" above).
- [x] The sum of volumes plus reserved headroom is below the node's disk, shown arithmetically. See
      "Decided 2026-08-29 — reserved headroom: 12 GB" above, shown three ways.
- [x] A deliberate disk-full test has been run and its observed behaviour written down. Run locally on
      a throwaway `docker-desktop` cluster, never the live deployment — see "Local disk-fill test,
      2026-08-29" above, including the one gap it did not close (the real `Ago.Chat.Api`/Npgsql path).
- [x] `15-03` has disk alert thresholds derived from those observations. See "Fed into `15-03`,
      2026-08-29" above — the threshold's numeric value is unchanged, its justification is now real.
- [x] `runbooks/k8s-local.md`'s limits section and `8-01`'s inherited-limits claim are updated to match
      what is now known. Done via `k8s-local.md`'s "Known limits" and `adr/0026`'s Consequences bullet
      (the actual location of the "carries over unchanged" claim `8-01`'s own Done-when points at) —
      see "Corrections made, 2026-08-29" above.

## Open questions

None. Every decision here is one a session can make from measurements it takes itself.

**What this pass explicitly did not verify** (named plainly, per its own brief): the real
`Ago.Chat.Api`/Npgsql behaviour under a full disk (reasoned about, not measured — see the fill test's
"Named gap"); whether the ~0.56 GB/day rate holds once real traffic or a real prune/archive cycle
exists (explicitly why no trend-based alert was added); and anything requiring live access to the
actual node, which this pass never had and never attempted.
