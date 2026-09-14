# 25-83 · A tenant that downloads too much is warned, then blocked

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging (`dotnet build`/
  `format --verify-no-changes` clean; full `dotnet test` — Domain 692/692, Application 1272/1272,
  FakeCrm 21/21, Architecture 46/46, Concurrency 88/88, Integration 1239/1240 with one confirmed
  pre-existing flake unrelated to this change — `MessageBatchWriterAutoGreetingTests`, last touched by
  `23-73`, untouched by this diff; ago-console `typecheck`/`lint`/`vitest run` — 1404/1404, 135/135
  files). All six Done-when boxes ticked and proven; the three found-and-fixed defects and the drafted
  ADR were each reviewed line-by-line. A fourth gap the worker found while fixing defect 1 — no route
  in this codebase exercises `GET /api/v1/attachments/{id}` over real HTTP at all — was filed as its
  own item rather than folded in here: `25-91`.
- **Depends on**: `23-82` (done, `ago-chat#288`/`ago-console#225`) — the egress counter this item
  enforces against already exists and is live.
- **Decision**: the author's, reached in dialogue with the managing session, 2026-09-14 — see below
  for the full shape. This item is the mechanism; `25-84` is the paid escape hatch from it.
- **Found**: `23-82`'s own third Done-when — "whether there is a ceiling, and what happens at it, is
  decided with the tier grid rather than here" — deliberately left open pending this conversation.

## The shape, decided 2026-09-14

**Two planks, per tier, stored in the database.** A soft warning threshold and a hard block
threshold, both configurable per tariff tier by the platform owner — the same "per-tier, not
universal" precedent `23-76`'s own storage quota already set. If no console screen exists yet for
editing them when this ships, the columns still exist and a runbook script edits them by hand — never
a hardcoded constant standing in for a real per-tier table.

**Crossing the soft threshold**: an active notification, not merely a number waiting to be noticed on
`23-80`'s own storage screen — an email, and a console banner that cannot be dismissed, in a warning
tone (yellow/orange) rather than a danger one. The distinction matters: this is "you are approaching
a limit," not "something is broken."

**Crossing the hard threshold**: every presigned GET refuses, for **everyone** — an operator in the
console and a visitor in the widget alike. This was a deliberate, explicit choice against this
codebase's own instinct ("refusing a download is worse than refusing an upload," `23-82`'s own
Scope): a tenant is responsible for their own visitors' experience, the same way they are responsible
for everything else about their own account, and carving out an exception for visitor downloads would
let a tenant's own inattention become a stranger's broken experience with no lever the tenant is ever
forced to notice. **A system message lands directly in the conversation where a visitor's download was
refused** — the one channel most likely to actually reach an operator who missed the console banner,
because they are already looking at that exact conversation when it happens.

**An owner-controlled per-tenant override**: a platform-owner-only toggle, off by default, that lets
a specific tenant's account bypass the hard threshold for free, indefinitely — a manual exception, not
a product feature a tenant can reach themselves. Reuses the same "the owner sees and can grant an
exception" shape `23-85`'s/`25-76`'s own owner-only routes already established.

**What happens at the hard threshold beyond the block itself — the paid path to lift it — is `25-84`'s
own scope, not this item's.** This item's own Done-when is satisfied by a blocked tenant with no way
to self-unblock except the owner's manual override above; `25-84` is what gives them a self-service
one.

## Where this is likely to go wrong

- **The egress counter this enforces against is a stated proxy, not an exact figure** (`23-82`'s own
  `IAttachmentEgressMeter` remarks: a cache hit inside a presigned URL's own TTL is never re-counted,
  so the count undercounts real egress). That was an acceptable proxy for "roughly gauge whether a
  ceiling makes sense" — it is a different question whether it is precise enough to gate a real
  refusal. Undercounting errs in the tenant's favor (they get blocked later than a perfectly accurate
  count would), which is the safe direction, but say so explicitly in this item's own report rather
  than silently inheriting `23-82`'s own caveat as if it were still just an observability footnote.
- **The in-conversation system message needs a locale.** `RouteConversationToModuleHandler`'s own
  four texts (`25-64`/`25-66`) are the precedent — Russian on a `Locale.Ru` site, English otherwise,
  not a fifth hardcoded-English string shipped the night after the last four were fixed.
- **The owner's override toggle and the hard block must not race.** A tenant crossing the threshold in
  the same window the owner flips the override needs a defined ordering (read-then-decide inside one
  transaction, not a stale in-memory read of the toggle from before the flip). **Answered**: read the
  exemption flag first, the egress figure only if it is not set, both live and uncached but not one
  shared transaction (`EnforceDownloadCapAsync`'s own remarks state the accepted trade in full — a
  false refusal costs one retry, the reverse would be a real bypass). Recorded as `adr/0171`.

**Three real defects this item's own real-Postgres/real-HTTP integration pass found and fixed, that no
mocked `Application.Tests` coverage could have caught:**

1. `Ago.Chat.Api.Http.ErrorExtensions.ToProblem` never mapped `Attachment.DownloadBlocked` — the hard
   block's own refusal code — to any HTTP status, so the actual enforcement answered a bare `500`
   instead of a `403` for every caller, the whole time. Fixed by adding it to the existing
   `TenantSuspension.CannotSend`-shaped 403 group (the identical "account-wide gate, not a permission
   check" reasoning that code already gives for itself).
2. The identical gap for `Site.DownloadBlockExemptionReasonRequired` — a blank reason on the owner's
   own exemption toggle answered `500` instead of `400`. Fixed the same way, joining the existing
   `*.ReasonRequired` 400 group.
3. `GetAttachmentDownloadUrlHandler.TryAddDownloadBlockedMessageAsync` called `Guid.NewGuid()` directly
   for the new system message's id — a CLAUDE.md rule 2 violation (`Ago.Chat.Architecture.Tests.TimeAndIdentityTests`
   catches this at build time; it was red until this pass). Fixed by threading `IIdGenerator` through
   the handler, `idGenerator.NewId(now)`, the identical `RouteConversationToModuleHandler`-established
   shape this handler's own class remarks already cite as its precedent for everything else about this
   system message.

All three were reachable only by exercising the real HTTP pipeline or the real architecture-test
suite — the mocked `Application.Tests` coverage the previous worker left behind exercised the handler
and the error *code*, never the HTTP status a caller actually receives, and never
`Ago.Chat.Architecture.Tests` at all. The managing session's own build check before this pass verified
`dotnet build` (compiles clean); none of these three is a compile error, so a clean build was never
evidence either way for them.

## Out of scope

- The paid overage entitlement, its price, its checkout flow, and the owner's "auto-bill vs. tenant
  must pay explicitly" toggle — all `25-84`.
- Any tenant-facing self-service control over either threshold or the override — both stay the
  platform owner's alone, per the decision above.

## Done when

- [x] Both thresholds exist per tariff tier in the database, editable by the platform owner (a
      console screen if one ships with this item, a runbook script otherwise) — never a single
      universal constant. `tier_download_thresholds` (migration `Stage25AddTierDownloadThresholds`,
      seeded `free`/`starter`), read by `IDownloadThresholdReadStore`. No console screen shipped with
      this item — the runbook script is `docs/runbooks/download-threshold-tuning.md`, written this
      pass to close the gap (none existed before it).
- [x] Crossing the soft threshold sends an email and shows a non-dismissable, warning-toned console
      banner, proven against a real tenant crossing it. Mail + once-per-crossing marker, real Postgres:
      `Ago.Chat.Integration.Tests.DownloadThresholdWatchdogJobTests` (6 tests, new this pass — the mail
      itself, the once-per-crossing guarantee proven by running the sweep twice, and the no-notify-twice
      case even as usage keeps growing). Banner rendering: `DownloadUsageBanner.test.tsx` (6 tests,
      already existed) plus the real `AppShell`/`OperatorShell` wiring (already existed, read and
      confirmed this pass, not modified).
- [x] Crossing the hard threshold refuses every presigned GET — operator and visitor alike — proven
      by fault injection for both callers. Real Postgres, both callers:
      `SiteAttachmentStorageHandlersTests.HandleAsVisitorAsync_WhenTheSiteIsAtItsHardThreshold_RefusesTheDownload_OverRealPostgres`/
      `HandleAsOperatorAsync_WhenTheSiteIsAtItsHardThreshold_RefusesTheDownload_OverRealPostgres` (new
      this pass), each seeding real `tier_download_thresholds`/`site_attachment_egress` rows through
      the real write paths, not mocks. Also found and fixed a real defect while proving this: the
      refusal answered HTTP `500`, not `403` — see "Where this is likely to go wrong" above.
- [x] A visitor's refused download drops a locale-aware system message into that exact conversation.
      English and Russian, both against a real, independently-re-read `Conversation` row (not the
      handler's own in-memory instance):
      `HandleAsVisitorAsync_WhenBlocked_PersistsTheSystemMessage_InRealPostgres`/
      `..._PersistsTheRussianSystemMessage_InRealPostgres` (new this pass, `SiteAttachmentStorageHandlersTests`),
      alongside the pre-existing mocked-store proof in `Application.Tests`
      (`GetAttachmentDownloadUrlHandlerTests`, 6 of its own tests cover this feature's locale/operator/
      exemption cases). Found and fixed a real defect while proving this: the message id was minted
      with `Guid.NewGuid()` directly, a CLAUDE.md rule 2 violation — see above.
- [x] The platform owner can grant a specific tenant a free, indefinite override, off by default,
      proven to actually bypass the hard block once granted. Through the real, owner-only HTTP route,
      both directions, checked against the real download gate rather than the write's own `200`:
      `OwnerDownloadBlockExemptionEndpointTests.OwnerToken_GrantsThenRevokesTheExemption_AndTheRealDownloadGateFollowsBothTimes`
      (new this pass, 6 tests in that file total — also proves the audit trail lands on the real row,
      the reason is required, and the route is owner-scoped: an ordinary operator, a site-wide admin,
      and no token are all refused). Tenant-scoping of the companion read route
      (`GET .../download-usage`) is proven the same way every other client-supplied-`siteId` group in
      this codebase is: `CrossTenantRouteIsolationTests.DownloadUsageRoute_RefusesAnotherTenantsSite`
      (new this pass).
- [x] The egress figure this enforces against is stated, in this item's own report and in
      `docs/architecture/file-storage.md` or `caching.md` (whichever already carries `23-82`'s own
      caveat), as a proxy that undercounts — not silently treated as exact now that real refusals (and
      `25-84`'s own real money) depend on it. **Correction**: the caveat actually lives in
      `docs/architecture/data-model.md` (the `attachments.download_count`/`site_attachment_egress`
      bullets), not `file-storage.md` or `caching.md` — this item's own text guessed wrong about which
      doc carries it. Restated there this pass, explicitly naming that a real refusal (not just a
      number on a screen) now depends on it.
