# Per-site widget configuration: data model and API

- **Stage**: 11
- **Status**: done
- **Depends on**: nothing new architecturally — reuses `adr/0016`'s RBAC (`site:configure`, already
  seeded onto the `"Admin"` role by `5-08`), `3-04`'s cache-aside/stampede/invalidation machinery
  unchanged, and the outbox/integration-event pattern every write handler in this codebase already
  follows. The new pieces are two columns, one aggregate method, one handler pair, and one real
  producer for an event that has existed on paper since `3-04` — not a new mechanism.

## Goal

A `Site` gains two persisted, editable fields — a primary color and a launcher position — reachable
through an authenticated, `site:configure`-gated API, and the widget's own handshake response
(`POST /api/v1/visitor-sessions`) carries their current values. This is the backend half of Stage 11's
own done-when bar: it makes "a site owner changes color/position" possible at all. It does not build
the console screen that calls this API (`11-02`) or the widget code that applies the values it returns
(`11-03`) — those are separate items, in separate repositories, following the same split `5-01` (CORS
mechanism) and `5-09`/`5-10` (the widget that used it) already established.

This item is also, concretely, the first real producer of `SiteSettingsChanged` — an integration event
that has existed in `Ago.Chat.Contracts` and been fully wired on the consumer side since `3-04`
("`SiteCacheInvalidationConsumer` is written and tested against the contract directly so invalidation
already works the day a real producer exists") with nothing ever calling it, because nothing has ever
changed a site's settings after creation. `Site` itself has been create-only since `1-04`; this is the
first update path it gets.

## Context to read first

`docs/architecture/caching.md` in full — the "Site config" cache row (`5 min + jitter`, invalidated by
`SiteSettingsChanged`), and the Event-driven invalidation section's exact wiring
(`SiteCacheInvalidationConsumer` maps `SiteSettingsChanged` to the generic `CacheInvalidated` broadcast,
both bypassing the outbox for the *invalidation signal itself* per `adr/0020` — that reasoning covers
`CacheInvalidated`, not `SiteSettingsChanged`; `SiteSettingsChanged` is a real domain-originated event
and goes through the outbox like every other one, per `CLAUDE.md` rule 4). `docs/backlog/3-04-caching-layer.md`'s
own "Note for a future session" — states explicitly that this gap exists and has been waiting.
`docs/architecture/data-model.md`'s `sites` row — the `settings` column named there was never actually
built (confirmed against `1-01`/`1-04`: the Stage 1 migration shipped `id`/`public_key`/`allowed_origins`
only; `settings` was aspirational schema notation, not a real column) — this item is where a concrete
shape finally lands, replacing that placeholder. `docs/backlog/5-01-per-site-cors.md` — the precedent for
"a per-site setting read on the widget's hot path," specifically `GetSiteConfigByPublicKeyHandler`'s
existing cache-aside shape this item's read side extends rather than duplicates, and the note that CORS's
own origin-cache key was left without event-driven invalidation *because* `SiteSettingsChanged` had no
producer yet — still true after this item, since this item does not touch `allowed_origins` and has no
reason to invalidate that separate cache key. `docs/backlog/5-09-widget-bootstrap-and-messaging.md` —
confirms what the widget bootstrap already does at handshake time (`data-site` → `POST
/api/v1/visitor-sessions`), the exact call this item's response payload rides along on.
`.claude/skills/embeddable-widget/SKILL.md`'s Bootstrap section — already states the intended shape:
"The handshake returns the site's widget settings (cached server-side per `caching.md`) and the
visitor's history cursor." This item is what finally makes that sentence true. `docs/architecture/authorization.md`'s
`5-08` section — `Permission.SiteConfigure` (`"site:configure"`) already exists, held by `"Admin"`, and
until now has only gated one read (`GetAllConversationsForSiteHandler`'s site-wide conversation list);
this is the first thing that uses it for what its name literally says. `docs/conventions/api-design.md`
(RFC 7807, `POST`/`PUT` conventions, additive-only compatibility for the handshake response DTO).
`docs/conventions/testing.md` for test-level placement.

## Scope

- **A short ADR** recording two judgment calls, both with a clear default, stated rather than surveyed
  at length (`6-03`'s own precedent for a well-understood default):
  - **Fixed, validated fields — not arbitrary CSS or a free-text theme blob.** The widget's Shadow DOM
    isolation (`embeddable-widget` skill) exists specifically to protect the widget *from* the host
    page; a config field that injects arbitrary style rules the other direction — into a shadow tree
    that the widget's own script controls, sourced from a value a tenant operator supplies — is a real
    security-surface question (CSS can exfiltrate via attribute selectors, redress content, or abuse
    `:has()`/animation timing even confined to a shadow root) that this item deliberately does not open.
    Two named, typed, validated fields instead: a primary color and a launcher position. State this
    explicitly as the reason, not just the choice.
  - **Config is read once, at bootstrap (page load) — not pushed live to an already-open widget.**
    Stage 11's own done-when text ("a site owner changes color/position from the console and sees it
    reflected in the embedded widget on their own page") reads as page-load-time application, matching
    how the widget already fetches its site config exactly once, in `POST /api/v1/visitor-sessions`, with
    no existing channel that re-delivers config into a connection that is already open (the realtime
    protocol's `reconnect`/resume mechanism resumes the same session and never re-runs the handshake).
    Building a live-push channel for a value that changes rarely (`caching.md`'s own "changed rarely"
    framing for site config) would be new realtime infrastructure this item has no stated need for.
    State plainly, in the ADR, that an already-open widget on a visitor's page will not pick up a
    changed color/position until that page is reloaded — a real, named limitation, not silently
    redefined away.
- **Domain** (`Ago.Chat.Domain`): a `WidgetConfig` value object on `Site` — a validated primary-color
  value (hex `#RRGGBB`, nullable — `null` means "use the widget's own built-in default," matching how a
  freshly self-registered or pre-existing site should not suddenly render broken) and a `Position` enum
  (`BottomRight` | `BottomLeft`, non-nullable, defaulting to `BottomRight`). `Site.UpdateWidgetConfig(...)`
  raises an in-memory domain event mapped to the `SiteSettingsChanged` integration event, the same
  domain-event → integration-event mapping shape every other write path already uses
  (`Ago.Chat.Application/Mapping`).
- **Migration** `Stage11AddSiteWidgetConfig` (`data-model.md`'s `<Stage><Verb><Subject>` naming):
  additive, reversible, two new columns on `sites` — `widget_primary_color_hex text NULL`,
  `widget_position text NOT NULL DEFAULT 'bottom-right'` with a `CHECK` constraint restricting it to the
  two known values (cheap storage-level backstop, matching this project's habit of not trusting
  application validation alone where a constraint is nearly free). `docs/architecture/data-model.md`'s
  `sites` bullet gets a concrete replacement for its current placeholder `settings` mention.
- **Application**: `UseCases/UpdateWidgetConfig/UpdateWidgetConfigHandler` (validates the hex format and
  enum value, loads the `Site` via a new `ISiteRepository.GetByIdAsync`, calls
  `Site.UpdateWidgetConfig`, saves in one transaction with the `SiteSettingsChanged` outbox row — an
  ordinary single-aggregate write, not the wider multi-row transaction `10-02`'s registration handler
  needed) and `UseCases/GetWidgetConfig/GetWidgetConfigHandler` (plain repository read — this is an
  operator-authenticated, low-frequency admin read, not the widget's own high-frequency handshake path,
  so it is **not** wrapped in `ICache.GetOrCreateAsync`; state this explicitly so a later session does
  not assume every site-scoped read needs the same caching treatment). Both gated by `site:configure`
  via `IPermissionChecker`, the same mechanism every existing permission check already uses.
- **HTTP** (`Ago.Chat.Api`): `GET /api/v1/sites/{siteId}/widget-config` and
  `PUT /api/v1/sites/{siteId}/widget-config`, `RequireOperatorIdentity` plus `site:configure`, RFC 7807
  errors via the existing `ErrorExtensions.ToProblem` mapping (`5-03`'s precedent). State the final
  endpoint-file name once written (matching `AttachmentEndpoints`/`ConversationsEndpoints`'s naming
  precedent).
- **Widget handshake extension**: `POST /api/v1/visitor-sessions`'s response DTO gains the current
  widget config (primary color, position) as an additive field — never a new endpoint, never a second
  round trip. This is the one piece `GetSiteConfigByPublicKeyHandler`'s existing cache-aside read
  (`3-04`, 5 min TTL + jitter, already the cached DTO the handshake serves from) needs to actually carry
  the new columns; extend the cached DTO, not add a second cached object next to it.
- **Cache invalidation, finally wired for real**: `UpdateWidgetConfigHandler` is the first real caller
  that makes `SiteSettingsChanged` fire. No new invalidation code is needed — `SiteCacheInvalidationConsumer`
  already consumes exactly this event and already broadcasts `CacheInvalidated` for the site config cache
  key (`3-04`). This item's own job is proving that already-built path now does something real: a
  config write followed shortly by a fresh handshake sees the new values well before the 5-minute TTL
  would otherwise expire it, on every node, not just the one that handled the write.

## Out of scope

- Any console UI for editing this — `11-02`.
- The widget bundle actually reading and applying the returned fields — `11-03`.
- Editing `sites.allowed_origins` — untouched by this item, still the deferred surface `5-01`/`10-04`
  already named (Stage 12's likely home), and this item's own `SiteSettingsChanged` producer has no
  reason to also invalidate the separate CORS origin-cache key (`CheckCorsOriginHandler`'s cache),
  which nothing in this item's scope changes.
- Any field beyond primary color and position — logo/avatar, a light/dark toggle, secondary colors,
  fonts. A real, named open question, not silently dropped — see `11-04`.
- A live-push channel that updates an already-open widget without a page reload — the ADR states why,
  above; a real deferral, not an oversight.
- Rate limiting this endpoint — it is operator-authenticated, low-frequency, and gated by the same RBAC
  check every other console-only write already relies on for abuse resistance (matching `attachment:delete`'s
  own precedent of having no dedicated rate limit); `3-05`'s `IRateLimiter` exists for the
  visitor-facing/unauthenticated surface this is not.

## Done when

- [x] `adr/0029` written and accepted: fixed fields over arbitrary CSS/theme injection, and
      read-at-bootstrap over live-push, both with the reasoning above. Renumbered twice before landing
      — `0027` was already claimed by both the not-yet-merged `long-term/stage-10` branch's own ADR and
      (independently) `main`'s `operator-identity-across-products`; `0028` was then also claimed when
      `long-term/stage-10`'s ADR was itself renumbered to `0028` while reconciling that stage's own
      numbering collision. `0029` is the number that actually landed, confirmed against `main`'s real
      ADR index at merge time, not assumed from an earlier check.
- [x] `Stage11AddSiteWidgetConfig` migration applies cleanly to a real Postgres from scratch
      (`db-migration` skill's own bar), additive and reversible, `CHECK` constraint proven to reject an
      invalid `widget_position` value — verified by hand against a real local Postgres (`\d sites`
      showed the expected columns/default/constraint; inserting `widget_position='diagonal'` was
      rejected with the expected error) as well as by every integration test in this item applying
      migrations from scratch via Testcontainers.
- [x] `Ago.Chat.Domain.Tests`: `Site.UpdateWidgetConfig` rejects a malformed hex color, accepts a valid
      one, accepts both position values, and raises the mapped domain event exactly once per call.
- [x] `Ago.Chat.Integration.Tests`: `PUT /api/v1/sites/{siteId}/widget-config` persists the change and
      writes a `SiteSettingsChanged` outbox row in the same transaction (asserted directly, matching
      `2-02`'s own "outbox row in the same transaction" proof shape); `GET` returns the current values;
      an operator without `site:configure` gets a clean `403` on both (`UpdateWidgetConfigOutboxTests`,
      exercising the handlers directly against real Postgres — this codebase's own established shape
      for an HTTP-adjacent integration test, matching `CloseConversationOutboxTests`; no
      `WebApplicationFactory` is used anywhere in this suite).
- [x] `Ago.Chat.Integration.Tests`: a config write, followed by a fresh `POST /api/v1/visitor-sessions`
      handshake for that site, returns the new values — proving the cache was actually invalidated
      end-to-end (real Postgres + real Redis + real RabbitMQ, not asserted from the handler's logic
      alone), not merely eventually correct once a 5-minute TTL expires
      (`WidgetConfigCacheInvalidationEndToEndTests`, wiring the real `OutboxDispatcher` ->
      `SiteCacheInvalidationConsumer` -> `Ago.Platform.Caching.Redis.CacheInvalidationConsumer` chain
      by hand, the same way `TracingEndToEndTests` wires its own pipeline stages).
- [x] `docs/architecture/caching.md`'s Site config row gets a "shipped" note for the invalidation half,
      matching the pattern every other now-real row in that table already follows.
- [x] `docs/architecture/data-model.md`'s `sites` bullet is updated to the real column shape, replacing
      the placeholder `settings` mention.
- [x] `docs/architecture/authorization.md` gets a short note that `site:configure` now gates a second,
      distinct thing (widget config, alongside `5-08`'s site-wide conversation view) — same pattern
      every other authorization change to that file already follows once shipped.

**Handoff note**: the Domain layer (`Site.WidgetConfig`, `Site.UpdateWidgetConfig`,
`SiteWidgetConfigUpdated`) and most of the Application layer (`ISiteRepository.SaveAsync`, the
`GetWidgetConfig`/`UpdateWidgetConfig` use cases, the `SiteConfigDto` extension, the EF mapping) were
built by an earlier session on this same branch that died mid-task (network error, not a logic
failure) before committing; that work was reviewed, found sound, and built on rather than redone. One
real gap from that partial state: three `ISiteRepository` implementers (`FakeSiteRepository` and two
test-local `CountingSiteRepository` decorators) did not yet implement the newly-added `SaveAsync`
member, leaving the whole solution unbuildable — fixed as the first step of this session before
anything else. Everything from the EF Core migration onward (HTTP endpoints, DI wiring, the handshake
extension, the full test suite, and this ADR/doc pass) is new in this session.

## Open questions

None for the scope actually shipped here — both real judgment calls (fixed fields vs. arbitrary styling,
bootstrap-time vs. live-push) have a stated, defensible default recorded in the ADR above. The one
genuine product-shape question this item's own scope surfaced — whether "styles/theme" extends beyond
color and position — is real and unresolved, and is deliberately not guessed at here; it is `11-04`,
blocked, and does not gate this item's own done-when.
