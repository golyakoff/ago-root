# 7-04: attachment presign throughput (reduced scale)

**Date**: 2026-08-24
**Commits**: `ago-chat` `f9c090dd41b353c16d9e2684874a1f6616676b5e` (`main`), `ago-root`
`04ecf0e974c0f9e0f519fb8ded952e2db1885226` (`main`, branch point for `docs/7-04-load-scenarios`)
**Hardware**: one Windows 11 development workstation - 11th Gen Intel Core i7-11800H, 8 cores / 16
logical processors, 63.8 GB RAM. **Not** the provisioned cluster `nfr.md` targets.

## Scale disclosure

**Deliberately, explicitly NOT `nfr.md`'s own target** - same reduced-scale, unsupervised-overnight
decision as every other report in this batch (full reasoning in `2026-08-24-steady-ingest.md`).

| | `nfr.md` target | This run | Scale factor |
|---|---|---|---|
| Attachment uploads (presign + verify path) | 50/s | 1.51/s achieved (1.54/s offered) | **~3%** |

Proves the scenario design and reporting method, one honest small-scale data point. **Does not claim
50/s presign throughput would be met at full scale** - MinIO/S3 presigned-URL issuance and
`GetMetadataAsync`'s own verification call have not been tested anywhere near their own limits at 3%
of target. A real run needs the provisioned cluster and enough concurrent presign+upload+verify
workers (spread across enough visitor/operator identities to avoid `AttachmentRateLimitOptions`
becoming the measured bottleneck instead of the storage path) to actually offer 50/s.

## Topology and tooling deviations

Same base topology as the rest of this batch: compose loop, `Api` on `5110` (visitor-node - this
scenario used only the visitor path), one `Worker` (not exercised by this scenario at all - no
message send, no assignment), real `.NET SignalR client` driver for the one hub call this scenario
needs (`JoinAsync`, to get a conversation to attach files to) plus plain `HttpClient` for the REST
presign/confirm calls themselves.

- **`AttachmentRateLimitOptions` raised via environment variables for this session**, the same
  reasoning as the message/session rate limits in the other reports:
  `AttachmentRateLimit__PerVisitorCapacity=1000`, `PerVisitorRefillPerSecond=50`,
  `PerOperatorCapacity=1000`, `PerOperatorRefillPerSecond=50`, `PerSiteCapacity=1000`,
  `PerSiteRefillPerSecond=50`. **Found live, not anticipated**: the default
  `PerVisitorCapacity=5`/`PerVisitorRefillPerSecond≈0.083/s` immediately produced `429 Too Many
  Requests` after the first burst of 5 calls from this scenario's single visitor identity - correct,
  expected abuse-prevention behaviour for a real visitor, but exactly the kind of default-limiter-
  becomes-the-bottleneck effect this run's other rate-limit overrides already exist to avoid.
- **Content type**: `AttachmentOptions.AllowedContentTypes` is a fixed server-side allow-list
  (`image/png`, `image/jpeg`, `image/gif`, `image/webp`, `application/pdf` - `text/plain` is rejected
  with `400`, found live during this scenario's own smoke test before the real run). This run declares
  `image/png` and PUTs a small, deliberately-not-a-real-PNG byte payload - `ConfirmAttachmentHandler`
  and MinIO only care that an object of the declared size exists at the object key, never that its
  bytes decode as the declared type, so this is a legitimate presign+upload+verify cycle for this
  scenario's own purpose (throughput of the three API/storage calls), not a claim about image-decoding
  correctness.
- **Bytes bypass the API, per `file-storage.md`**: the PUT goes straight from this driver process to
  MinIO's presigned URL, never through `Ago.Chat.Api`. The "verify" step (`POST .../confirm`) is real
  and necessary, not a stub - it calls `IFileStorage.GetMetadataAsync` and genuinely fails if nothing
  was PUT to the presigned URL first, so this run is a real presign-upload-verify cycle end to end.

## What this scenario answers

Can the presign (`POST /api/v1/conversations/{id}/attachments`) and verify
(`POST /api/v1/attachments/{id}/confirm`) API calls sustain a steady rate without latency drift, and
does the actual object write land in MinIO reliably enough that verify never fails against a
just-uploaded object?

## Load shape

One visitor, one conversation (reused for every attachment in this run - the scenario is about
presign+verify throughput, not conversation-creation overhead). 2 concurrent workers, each issuing
one presign+PUT+confirm cycle every 1 300 ms (offered aggregate ~1.54/s). 15 s warm-up (discarded),
90 s measured plateau. Total wall clock 105 s.

## Results

Source: `RunAttachmentPresignAsync`, `tests/Ago.Chat.LoadDriver/Program.cs` (this branch, `ago-chat`).
Raw CSV: `load/output/raw/attachment-presign.csv` (gitignored).

| Call | n | p50 | p95 | p99 | max |
|---|---|---|---|---|---|
| Presign (`POST .../attachments`) | 136 | 10.7 ms | 15.4 ms | 21.3 ms | 22.9 ms |
| Confirm/verify (`POST .../confirm`) | 136 | 9.9 ms | 20.2 ms | 36.2 ms | 36.9 ms |
| Full cycle (presign + real MinIO PUT + verify), wall clock | 136 | 29.8 ms | 45.1 ms | 125.8 ms | 171.2 ms |

**Throughput**: 136 completed presign+verify cycles over the 90 s measured window = **1.51 ops/s**,
against 1.54/s offered (~98% - **zero errors** across the whole run, every presign, every PUT, every
confirm succeeded).

## Interpretation

Both API calls (presign, confirm) stayed fast and stable (p50 under 11 ms for both, p99 under 40 ms)
with no visible drift across the 90 s plateau - at this rate, neither the database write behind
`CreateAttachmentHandler` nor the MinIO `HeadObject`-equivalent behind `ConfirmAttachmentHandler.
GetMetadataAsync` showed any sign of struggling. The gap between the two API calls' own latency
(~11-20 ms each) and the full-cycle wall clock (p50 29.8 ms, p99 125.8 ms) is the real MinIO PUT in
between plus this driver's own sequential `await` chain - not hidden, and the p99 jump (125.8 ms vs
p95's 45.1 ms) suggests occasional MinIO PUT variance worth watching at higher concurrency, though 136
samples is not enough to characterize that tail with confidence.

`nfr.md` states this target as a throughput number (50/s), not a latency table row, so there is no
p50/p95/p99 target to compare against directly - only the rate. **This run does not claim 50/s is
reachable** at 3% of that offered rate with zero contention on the object store; the honest statement
is that the *path itself* (presign -> real upload -> verify) works correctly and fast at this scale
with zero errors, which is a necessary but not sufficient condition for the full target.

## Server-side observations

No live dashboard for this run's own instances (same gap as the rest of this batch - see
`2026-08-24-steady-ingest.md`). No dedicated resource sampling for this scenario (it shares the same
long-lived visitor-node `Api` process already sampled during `connection-storm`; this scenario's own
load is light enough - 2 concurrent workers, ~1.5 ops/s - that it is very unlikely to have moved that
process's memory footprint meaningfully, but this is not independently confirmed).

## What was tuned

`AttachmentRateLimit` per-visitor/operator/site budgets raised via environment variables for this
session only (see above) - without this, the default per-visitor cap (5 capacity, ~0.083/s refill)
would have been the measured bottleneck within the first few seconds, not the presign/storage path.

## What a real, full-scale run still needs

The provisioned cluster, enough distinct visitor/operator identities that
`AttachmentRateLimitOptions`' per-visitor/per-operator buckets (even generously raised ones) cannot
become the ceiling before the storage path does, and a genuine attempt at 50 concurrent
presign+upload+verify cycles per second to see whether MinIO's own presigned-URL issuance or the
verify call's `GetMetadataAsync` round trip becomes the bottleneck first.
