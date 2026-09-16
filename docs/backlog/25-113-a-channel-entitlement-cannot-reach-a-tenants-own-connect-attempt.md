# 25-113 · A channel entitlement cannot reach a tenant's own connect attempt

- **Stage**: 25
- **Depends on**: nothing
- **Status**: done (config), UI gap carried to `25-114` — `ago-deploy#220`, applied live to the demo
  deployment, smoke 46/46. The config fix is real and confirmed live (the env var reaches the API
  pod), but full end-to-end proof (an actual owner grant, an actual tenant connect) needs the owner
  console UI this item's own investigation found does not exist yet - see `25-114`. Not this item's
  own scope to build; filed separately rather than expanding this one, per "one ticket, one thing."
- **Found**: 2026-09-16, the author (as platform owner) trying to walk the real flow end to end: grant
  a tenant a Telegram channel entitlement from `/owner/sites/{siteId}`, then have the tenant paste
  their own bot token at `/channels/telegram` and have it actually work. It never could, regardless of
  what was granted.

## What was actually true

`23-85` gave `RegisterChannelCredentialHandler`/`RevokeChannelCredentialHandler`/
`GetChannelCredentialStatusHandler` (all three live in `Ago.Chat.Api`, reached through
`Channels/TelegramChannelEndpoints.cs` and its siblings) a real entitlement check -
`ChannelEntitlement.IsEntitledAsync`, which calls `IBillingOptionEntitlementProvider.TryGet
(BillingOptionKey "channel-telegram")` to resolve which `ModuleKey`'s quantity grant actually answers
"may this account use Telegram".

That mapping is deployment configuration (`23-86`/`adr/0159`, `ConfiguredBillingOptionEntitlementProvider`
reading `BillingOptionEntitlements__channel-telegram` from `IConfiguration`) - and `ago-deploy`'s own
`k8s/base/worker.yaml` carried the only copy of that line, with a comment explicitly justifying why:
*"only `Ago.Chat.Worker` needs this variable... this mapping is consulted from nowhere else"*, true
when `23-86` wrote it, because `SubscriptionRenewalApplier` (Worker-only) was the only real caller at
the time. `23-85` added the second real caller, in `Ago.Chat.Api`, three days later - and nothing
updated `api.yaml` to match. Confirmed live on the real demo deployment: `ago-chat-worker`'s own env
carries `BillingOptionEntitlements__channel-telegram`; `ago-chat-api`'s does not, at all.

**The consequence**: `ChannelEntitlement.IsEntitledAsync`, running inside `Ago.Chat.Api` (the only
process a tenant's own connect attempt ever reaches), always resolved `TryGet("channel-telegram")` to
`null` - "this deployment has not declared what channel-telegram turns on," the port's own documented
meaning for an absent mapping - regardless of what quantity the owner had actually granted through
`GrantModuleQuantityAsOwnerHandler` (also `Ago.Chat.Api`, and the one owner-facing tool that already
exists for this - no new grant mechanism was needed, only the config gap closing).

## Fix

`k8s/base/api.yaml` gains the identical `BillingOptionEntitlements__channel-telegram: "channel"` line
`worker.yaml` already carried. `worker.yaml`'s own comment is corrected - the claim that this mapping
"is consulted from nowhere else" was already false the moment `23-85` shipped.

## Where this is likely to go wrong

- **The next priced channel option needs this in both files from day one.** The failure mode here was
  specifically "a second real caller arrived and the deployment wasn't told" - a reviewer adding
  `channel-whatsapp` or similar should grep both `api.yaml` and `worker.yaml` for the existing
  `channel-telegram` line as a template, not copy `worker.yaml` alone the way this one originally was.
- **This was never caught by `smoke.sh` or any existing test** - both are functional/config-presence
  checks that never actually walk the owner-grants-then-tenant-connects flow end to end against the
  real deployment. Worth naming as a real gap in this deployment's own testing rather than assuming
  the next such miswiring would be caught either.

## Done when

- [x] `api.yaml` carries the same `BillingOptionEntitlements__channel-telegram` mapping `worker.yaml`
      does.
- [x] `worker.yaml`'s own comment no longer claims the mapping has one caller.
- [~] Applied to the live demo deployment and confirmed: the platform owner grants a tenant's Telegram
      entitlement, the tenant's own `/channels/telegram` connect attempt succeeds where it was
      unconditionally refused before. **Config confirmed live** (the env var reaches `ago-chat-api`,
      smoke 46/46) - the real grant-then-connect walk needs `25-114`'s own owner-console UI first,
      since nothing today lets an owner make this grant without a hand-built HTTP call.
