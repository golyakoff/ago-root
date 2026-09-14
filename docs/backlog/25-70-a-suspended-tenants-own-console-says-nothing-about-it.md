# 25-70 · A suspended tenant's own console says nothing about it

- **Stage**: 25
- **Status**: done — `ago-chat#289`, `ago-console#226`. Independently re-verified by the managing
  session before merging — `ago-chat`'s full suite re-run twice for a clean baseline (3313/3313)
  after one unrelated flaky failure in `Ago.Chat.Architecture.Tests`, a pre-existing Mono.Cecil
  thread-safety race in shared test infrastructure, filed separately as `25-81`; `ago-console`
  1384/1384. No new ADR — this item is additive to `22-08`'s own already-decided mechanism, not a new
  architectural choice.
- **Depends on**: `22-08` (done, `ago-chat#271`/`ago-calendar#62`/`ago-console#214`) - the mechanism
  this item's own missing half sits on top of.
- **Found**: 2026-09-13, landing `22-08`. That item's own Scope prose names this explicitly - *"What
  the tenant sees. The console says the account is suspended, since when, until when, and what to do
  about it. That is the entire visible effect, and it is deliberately the only one."* - but no Done-when
  box named it, and the implementing worker built only the platform-owner-facing screens (suspend an
  account, list, extend, unblock). A real, described piece of scope shipped as unbuilt rather than
  silently dropped or silently added.

## What is actually true today

A suspended account's own operators can still sign into their console - nothing about `22-08` blocks
that - and see nothing telling them why the calendar stopped taking bookings or why sending stopped
working. They would discover the effect (a refused booking, a refused send) with no stated cause.

## Scope

- The tenant's own console reads its own account's suspension state (`GET` whatever endpoint already
  backs the owner's list, scoped to the caller's own site rather than every site) and shows: suspended,
  since when, until when, and a short line on what to do (contact support, or whatever the actual
  process is - a real question this item should answer, not invent silently).
- This is read-only for the tenant - they cannot lift or extend their own suspension, only see it.

## Out of scope

- Anything that lets a tenant act on their own suspension. `22-08`'s own design keeps that the
  platform owner's act alone, and this item does not reopen it.

## What was built

- `Ago.Chat.Application.Abstractions.ISiteSuspensionReadStore` gained one more method
  (`GetForTenantAsync`) rather than a new port - `22-08`'s own mechanism (the interface, its Postgres
  adapter, the `site_suspensions` table) is reused wholesale, no new migration. "Since when" is read as
  the most recent `'Suspended'` row for the site, not the most recent row of any kind - an `'Extended'`
  act pushes the deadline out without restarting the suspension, proven directly by a real-Postgres
  test that suspends, extends, and asserts `Since` stays put while `Until` moves.
- `GET /api/v1/sites/{siteId}/suspension` (`Ago.Chat.Api.Sites.SiteSuspensionEndpoints`, new handler
  `GetSuspensionStatusForSiteHandler`), gated on `Permission.SiteConfigure` through
  `IPermissionChecker` - the identical shape and the identical permission the sibling tenant-facing read
  on this route group (`ListEnabledModulesForSiteHandler`) already uses, so it inherits
  `TenantScopeTests`' own automatic cross-tenant guard rather than needing a new one argued from
  scratch.
- The console's own `SuspensionBanner` (`src/shell/SuspensionBanner.tsx`), fetched once per site by
  `useSiteSuspensionStatus.ts` and rendered by `OperatorShell` in the same full-bleed band
  `PublicDemoNotice` already occupies - a standing fact about the whole session, visible on every
  tenant screen, not one page's content.
- **"What to do about it"**: no real support-contact channel (email, phone, ticketing) exists anywhere
  in this codebase or in `ago-business` - confirmed by search, not assumed. The banner reuses the
  existing, already-reasoned-through "contact AGO", no address idiom this codebase already commits to
  twice (`productsContactNote`, `installOriginPanelDescription`), rather than inventing a new channel
  this item cannot verify is real or monitored.

## Done when

- [x] An operator signed into a suspended tenant's own console sees the suspension, since when, until
      when, and what to do about it - proven by suspending a real account and loading its console.
      Proven at two levels, not by manually clicking through a live browser session: an integration
      test suspends a real account through the real `SuspendTenantAsOwnerHandler` (never a hand-seeded
      row) against real Postgres, then reads it back through the exact handler the console's own
      `GET` route resolves; a component test renders `SuspensionBanner` against that same shape and
      asserts the suspended/since/until/contact text appears, with no interactive control. What this
      does *not* include is a live, Keycloak-authenticated browser session loading the running console
      - flagged here rather than silently assumed, for the managing session to decide whether that
      manual pass is still wanted before merge.
