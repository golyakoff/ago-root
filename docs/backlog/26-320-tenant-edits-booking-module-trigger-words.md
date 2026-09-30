# 26-320 · [onboarding/channels] a tenant admin cannot edit the bookings module trigger words

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-30, onboarding the first real client. The booking start-trigger string(s)
  (`/записаться`, `/booking`) that route a chat message into the bookings module could only be set by
  the **platform owner** — done by hand for «Салон Топаз». A tenant admin has no way to set or edit them
  from the Записи (bookings module) settings.

## What is true today (verified)

`EnabledModule.TriggerWords` is per-module, per-site, returned in the visitor handshake (`25-131`) and
matched by `RouteConversationToModuleHandler`. It is **set only** via the platform-owner path
(`EnableModuleForSiteAsOwnerHandler` / `OwnerModuleEndpoints`) and, since `26-316`, seeded with a default
(`/записаться`) at tenant self-enable. There is **no tenant-facing endpoint to edit** the trigger words
afterward — the tenant `ModuleEndpoints` (`26-316`) only enable/disable. The domain already treats
`TriggerWords` as tenant-replaceable (`AuthEndpoints` remark), and the owner path already has the
validation (`ReservedChatCommands.IsReserved` → `Module.TriggerWordReserved`; cross-module collision →
`Module.TriggerWordAlreadyRegistered`).

## Fix (belongs with the 26-316 Записи settings)

- **Backend (ago-chat):** a tenant endpoint to replace an enabled module's trigger words for the
  caller's own site — `PUT /api/v1/sites/{siteId}/modules/{moduleKey}/trigger-words`, gated
  `site:configure` (same as 26-316, never `RequirePlatformOwner`). Reuse the owner path's validation
  (reserved-word + cross-module-collision, same typed errors) rather than re-deriving it. Non-owner
  modules only (an owner-granted module's triggers stay owner-managed, mirroring 26-316's disable
  refusal). Emits whatever the owner path emits for a trigger change (match it).
- **Console (ago-console):** in the Записи module settings (the `26-316` `BookingsModulePage`), a field
  to view/edit the booking trigger words, wired to the new endpoint, RU+EN, gated on the same permission.

## Done when

- [ ] A tenant admin sets/edits the bookings trigger words from Записи settings, no platform-owner action.
- [ ] Reserved-word and cross-module-collision validation applies (same typed errors as the owner path).
- [ ] Owner-granted modules keep owner-managed triggers.
- [ ] Backend + console gates green; feeds the onboarding wizard 26-318.
