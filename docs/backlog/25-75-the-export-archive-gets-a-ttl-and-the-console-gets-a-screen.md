# 25-75 · The export archive gets a TTL, and the console gets a screen

- **Stage**: 25
- **Status**: done — `ago-chat#270`(export status enum groundwork earlier)/`ago-chat#276`/`ago-console#215`
- **Depends on**: `16-03` (done, 2026-08-28) — this item closes two gaps that item's own Done-when
  never named: the export archive lived in object storage forever, and the console never had a screen
  for the feature `16-03`'s own Goal said would be console-triggered.
- **Found**: 2026-09-13, the author asking directly how the export queue's own durability/failover
  story worked, and separately asking to verify the archive's real S3 lifetime — landed on both gaps
  at once. Built under the working branch name `feat/16-03-export-ttl-and-console-ui` before this
  item existed as its own number; recorded here after the fact rather than silently left unlisted,
  per this project's own "a remainder gets a new number, not a link" rule.

## What shipped

- **A real 7-day TTL.** `SiteExportPruneJob`/`SiteExportPruneQuery` (`Ago.Chat.Worker`) sweep `Ready`
  export requests whose `CompletedAt` has aged past `SiteExportPruneJobOptions.RetentionWindow` — an
  atomic claim-and-resolve statement (`WITH candidates AS (...FOR UPDATE SKIP LOCKED)`) that flips a
  row to a new `ExportStatus.Expired` and nulls its `ObjectKey` in the same statement that reads the
  pre-update key, before the storage delete runs — a failed delete leaves the row already-`Expired`,
  never stuck.
- **One shared source for "how long," read by two host processes.** `SiteExportPruneJobOptions` lives
  in `Ago.Chat.Application` specifically so both `Ago.Chat.Worker` (the sweep) and `Ago.Chat.Api` (the
  console's own displayed expiry date) bind the identical config section through `ChatModule` — the
  two can never silently disagree about what "seven days" means.
- **A console screen** — "Скачать данные," in "Администрирование," immediately before "Удалить
  аккаунт": a table (дата запроса / ссылка / дата автоматического удаления) and a "Подготовить данные
  для скачивания" button. `GetSiteExportHistoryHandler`/`IExportRequestRepository.ListForSiteAsync`
  feed it; no polling — the list reloads once after a new request is triggered, matching the item's
  own console-only status decision (no email, no push).

## Found and fixed along the way

A pre-existing, unrelated test suite (`SiteExportModuleGateIntegrationTests`, from `22-31`) asserted an
exact `SiteExportJob.SweepAsync()` return count in three places — a global count over every `Pending`
row the shared Postgres container holds, with no per-test scoping (`SiteExportQuery.ListPendingAsync`
has none — the identical gap `25-72` names). Under real full-suite parallel load a concurrently-running
test's own export could land in the same sweep, making the count test-order-dependent. Found failing
against real CI, not by inspection; fixed by asserting each test's own export outcome directly rather
than the shared sweep's own incidental return value.

## Out of scope

- `25-72` (the underlying unscoped-claim gap the flaky test above symptomized) — still open, queued
  separately.
- `25-70` (a suspended tenant's own console banner) and `25-74` (unrelated booking bugs) — separate
  items, not touched here.

## Done when

- [x] A `Ready` export older than 7 days is pruned — object deleted, request `Expired` — proven against
      a real Postgres, not asserted.
- [x] The console's own displayed "auto-deletes on" date and the prune job's own sweep window read the
      identical config value.
- [x] An operator can trigger a new export and see its history — request date, download link once
      ready, auto-deletion date — from a real console screen, gated on `site:export`, placed
      immediately before "Удалить аккаунт."
