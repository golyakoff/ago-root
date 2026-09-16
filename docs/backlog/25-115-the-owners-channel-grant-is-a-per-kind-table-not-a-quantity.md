# 25-115 · The owner's channel-entitlement grant is a per-channel-kind table, not a bare quantity

- **Stage**: 25
- **Depends on**: `25-114` (built the "channel" quantity mechanism this item replaces), `25-113`
  (the deployment-config path this item extends to four more channel kinds)
- **Status**: ready
- **Found**: 2026-09-16, the author testing `25-114` live: the delivered "Право на канал" section
  asked for a numeric "quantity" for one hardcoded channel (Telegram), when the real request was a
  dropdown to add any of the platform's channel kinds, shown in a table with provenance (paid vs
  owner-granted) and an expiry date - a design the author had described before `25-114` was built and
  that its own delivered shape did not match.

## What is actually true today

`ChannelKind` (`Ago.Chat.Domain`) already has seven members: `Max`, `Sms`, `Telegram`, `WhatsApp`,
`Vk`, `Avito`, `Email`. `ChannelEntitlement.IsEntitledAsync`/`ChannelEntitlementOptionKeys.For` are
already generic across all of them - only the *deployment's* `BillingOptionEntitlements__channel-*`
configuration decides which are actually priced. Today only `channel-telegram` is configured
(`ago-deploy` `k8s/base/{api,worker}.yaml`), mapped to the single `ModuleKey("channel")`.

Of the seven, only `Max`, `Telegram`, `Vk` have a tenant-facing console connect page today
(`/channels/{max,telegram,vk}`). `WhatsApp` and `Avito` have real API endpoints
(`WhatsAppChannelEndpoints.cs`, `AvitoChannelEndpoints.cs`) but no console screen yet - granting them
is still useful (the entitlement is there the moment their screens ship), per the author's own
explicit choice to include all five now rather than wait.

`ModuleQuantityGrant` (`23-86`) already has an owner-driven path independent of `Quantity`:
`UnconditionallyGrantedByOwner`/`UnconditionalGrantSetBy`/`UnconditionalGrantReason`/
`UnconditionalGrantSetAt`, set via `IModuleQuantityGrantStore.SetUnconditionalGrantAsync` (requires a
non-blank reason). `EffectiveQuantity` is `Quantity` OR'd with this flag. This is the right mechanism
for an owner's manual channel grant - not the numeric `GrantAsync` path `25-114` wired up, which asked
the owner to type a meaningless "quantity" for something that is really yes/no.

No expiry concept exists anywhere on `ModuleQuantityGrant` today - a real gap against the author's own
request ("на срок... или бессрочно").

No live site has any `module_quantity_grants` row with `module_key = 'channel'` (confirmed live,
2026-09-16) - renaming that `ModuleKey`, or restructuring how it is granted, breaks nothing in
production.

## Scope

- **Domain (`ago-chat`)**: add `DateTimeOffset? UnconditionalGrantExpiresAt` to `ModuleQuantityGrant`,
  set only alongside the other `UnconditionalGrant*` fields via `SetUnconditionalGrant` (a new optional
  parameter). `EffectiveQuantity` (or its call sites) must treat an expired unconditional grant as if
  the flag were never set - a past `UnconditionalGrantExpiresAt` means the effective read falls back to
  `Quantity` alone, which needs a `DateTimeOffset now` input the property does not take today. This is
  a real signature change - find and update every call site, do not assume it is additive.
  - **A genuine EF migration.** This is the migration-lane item; no other migration is in flight
    (checked 2026-09-16, `git log`/`gh pr list` against `ago-chat`).
  - The identical field the author asked about extending to the calendar's own quantity grant too
    (same column, no second migration) is deliberately **out of this item's scope** - a UI-only
    follow-up once this ships, since the calendar's own grant form has its own established
    lowering-confirm/impact-preview flow this item does not touch.
- **Application (`ago-chat`)**: `ChannelEntitlement.IsEntitledAsync` needs no logic change of its own
  (it already reads whatever `EffectiveQuantity`/`GetQuantityAsync` return - correct automatically once
  Domain accounts for expiry). `GetSiteForOwnerHandler` replaces the single `ChannelQuantity: int?`
  field with a list, one row per `ChannelKind` this deployment has actually priced (i.e.
  `entitlements.TryGet(ChannelEntitlementOptionKeys.For(kind))` resolves), each carrying: the kind, the
  deployment's own `ModuleKey` for it (opaque, echoed back by the console on grant/revoke - the
  identical "the wire carries values" shape `OwnerSiteModuleDto.ModuleKey` already uses), whether it is
  currently granted, whether by owner or by (future) billing, and its expiry. A new owner-facing write
  use case for "set/lift this channel's unconditional grant, with a reason and an optional expiry" - do
  not reuse `GrantModuleQuantityAsOwnerHandler` (`23-66`) for this; that handler's whole contract is the
  numeric path, wrong for this fundamentally boolean case.
- **`ago-deploy`**: `BillingOptionEntitlements__channel-{max,telegram,vk,whatsapp,avito}` in both
  `api.yaml`/`worker.yaml`, each its own distinct `ModuleKey` (`"channel-" + kind`, replacing the
  legacy shared `"channel"` value Telegram used alone - safe, no live grant references it). The
  managing session's own task once the backend and console land, not the worker's - small, config-only,
  the identical shape `25-113` already used.
- **`ago-console`**: replace the "Право на канал" quantity form with: a table of the site's currently
  entitled channels (kind, "оплачено"/"выдано владельцем", expiry or "бессрочно"), a dropdown of the
  remaining (not-yet-entitled) channels among the five named above, a date-or-"бессрочно" choice (the
  identical radio-plus-date-input shape the existing "Grant a module" form already uses for
  `ExpiresAt`), a short required reason field (matching `forceReason`'s own established pattern), and
  Add/Revoke actions.

## Where this is likely to go wrong

- **Do not give a channel entitlement its own `enabled_modules` row.** `ChannelEntitlement.cs`'s own
  remarks on why a channel deliberately has none still apply; this item only changes how the *quantity
  grant* is shaped, not the module registry.
- **`EffectiveQuantity`'s signature change touches every caller.** It is read today as a pure property
  with no clock - find every call site before assuming the expiry check is a small addition.
- **`SetUnconditionalGrantAsync` already requires a non-blank reason.** The new console form must
  supply a real one; do not silently pass a placeholder string to route around the domain's own
  validation.
- **The five channel kinds are not equally real.** `Max`/`Telegram`/`Vk` have a tenant screen today;
  `WhatsApp`/`Avito` do not. Granting the latter two is still useful (ready the moment their screens
  ship) but say so plainly in the UI copy so a support agent does not expect a tenant to see a
  WhatsApp connect screen that does not exist yet.
- **Renaming Telegram's `ModuleKey` from `"channel"` to `"channel-telegram"` is safe only because no
  live grant references the old key** (confirmed 2026-09-16) - state that check's own evidence in the
  PR; do not assume it still holds from this item's own text alone if real time has passed since.

## Done when

- [ ] `ModuleQuantityGrant` carries `UnconditionalGrantExpiresAt`; a migration applies it; an expired
      unconditional grant reads as not-entitled.
- [ ] The owner can grant and revoke each of the five named channel kinds independently, with a
      required reason and an optional expiry, from a dedicated `/owner/sites/{siteId}` section - not
      the numeric quantity form `25-114` shipped.
- [ ] The table shows, per currently entitled channel: kind, provenance (owner-granted today - the
      "paid" case is real but unreachable until a self-service channel purchase exists; do not fake
      data to populate it), and expiry (or "бессрочно").
- [ ] `ago-deploy` configures all five channel kinds' `BillingOptionEntitlements` on both
      `api.yaml`/`worker.yaml`.
- [ ] A real end-to-end walk: grant MAX (or VK) through the new UI, confirm the tenant's own existing
      connect screen (`/channels/max`, `/channels/vk`) now accepts a real credential where it was
      refused before.
