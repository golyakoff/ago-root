# 25-106 · A site's attachment-upload default does not take effect for new conversations

- **Stage**: 25
- **Status**: ready — found live, not yet diagnosed. This is a reproducible observation with the
  obvious explanations already ruled out, not a root cause.
- **Depends on**: nothing
- **Found**: 2026-09-15, verifying `25-103` end to end on the live public demo. Not a network or
  storage problem - it surfaced while trying to prove a *permission-gated* presigned upload succeeds,
  using `demo_site` (the live deployment's real fallback site, `sites.public_key = 'demo_site'`,
  `sites.id = 00000000-0000-0000-0000-000000000001`).

## What was actually observed

1. `sites.widget_allow_attachment_uploads_by_default` for `demo_site` confirmed `false` before any
   change (`select ... from sites where public_key = 'demo_site'`).
2. A conversation created against the live public API at that point correctly got no grant - `POST
   .../attachments` returned `403`, and the conversation's own `attachment_upload_granted_at` is
   `NULL` in the database. Expected; this is the control.
3. The column was set to `true` directly (`UPDATE sites SET widget_allow_attachment_uploads_by_default
   = true WHERE public_key = 'demo_site'`), confirmed by re-reading it back afterward - `true`,
   unambiguously.
4. A **new** conversation, created after that update, against the same live API, for the same site -
   confirmed via the database to be a genuinely new row (`created_at` matching the request's own
   timestamp, a fresh `visitor_id`) - still got no grant: `attachment_upload_granted_at` is `NULL`,
   and `POST .../attachments` against it still returned `403`.
5. This was tried twice, the second time after also clearing the `ICache` entry the widget-handshake
   path is known to populate (`site-config:demo_site`, `GetSiteConfigByPublicKeyHandler`'s key) - no
   change.

## What has already been ruled out, by reading the code and checking live state directly

- **Not the obvious cache key.** `StartConversationHandler` does not read the config through
  `GetSiteConfigByPublicKeyHandler` (the handshake path, keyed `site-config:{publicKey}`) at all - it
  reads through `GetSiteConfigByIdHandler`, keyed `site-config:id:{siteId}`
  (`StartConversationHandler.cs:156`, `SiteCacheKeys.ForSiteId`). Checked live with
  `redis-cli keys "site-config:*"` immediately after a failing attempt: **no `site-config:id:*` key
  existed at all** - so this was not a stale cache entry either; the id-keyed cache was never even
  populated by the failing calls.
- **Not two different site rows.** `select id, public_key, widget_allow_attachment_uploads_by_default
  from sites where public_key = 'demo_site'` returns exactly one row, and the failing conversation's
  own `site_id` column matches that row's `id` exactly.
- **Not EF reading something other than this table.** `SiteRepository.GetByIdAsync` (`ago-chat`'s
  `src/Ago.Chat.Infrastructure.Postgres/SiteRepository.cs`) is a plain
  `db.Sites.FirstOrDefaultAsync(s => s.Id == id, ...)` against the same `AgoChatDbContext` - no
  separate read model, no Dapper projection, for this particular read.
- **Not a column-mapping mismatch.** Every EF Core migration back to `20260909194420` maps this
  property to exactly the column that was updated (`HasColumnName("widget_allow_attachment_uploads_by_
  default")`, `SiteConfiguration.cs:179`).

## What this item is, and is not

This is **not** a claim about what is broken - none of the above points at a specific cause, and the
obvious suspects (wrong key, wrong row, wrong column, stale read model) are all checked and eliminated.
Two directions worth checking first, neither confirmed:

- Whether `AgoChatDbContext` (or `SiteRepository`) is registered with a lifetime longer than
  `Scoped` in `ago-chat-api`'s DI container - would explain a tracked, stale `Site` entity surviving
  across requests within one pod's lifetime, independent of Redis.
- Whether `Conversation.Start`'s own handling of the `attachmentUploadGrantedByDefault` parameter
  (`Conversation.cs`) does what `StartConversationHandler`'s call site assumes, end to end - not
  re-checked past the call site itself in this investigation.

**Correction made and confirmed before this file was written**: the live `demo_site` row was reverted
to `false` immediately after the investigation (`UPDATE ... SET widget_allow_attachment_uploads_by_
default = false ...`, re-read back to confirm), so the live deployment is not left in an
inconsistent, hand-patched state. `attachment_bytes_reserved`/other columns were not touched.

## Out of scope

- `25-103`'s own concern (network reachability of a presigned URL) - fully and separately verified: a
  real signed PUT/GET against `https://files.reserve-me.ru`, issued with the exact credentials the
  application itself uses, succeeded from a genuine external network path. That proof does not depend
  on this item at all, which is why `25-103` is not blocked by this one.
- The console-side toggle for this same setting (`25-104`) - already shipped, and this item's finding
  says nothing about whether the console's own save path works; it was never exercised here (the
  database was patched directly, precisely to isolate this question from `25-104`'s own code path).

## Done when

- [ ] A root cause is identified - not just a location that works around the symptom.
- [ ] A regression test exists that fails against the code before the fix and passes after
      (fails-before, this project's own standing rule) - through the real handler path, not a
      database-level assertion, since the database was never the layer in question.
- [ ] Confirmed, once fixed, that `UpdateWidgetConfigHandler`'s own normal write path (console →
      API, not a hand-rolled `UPDATE`) takes effect for a genuinely new conversation without a pod
      restart.
