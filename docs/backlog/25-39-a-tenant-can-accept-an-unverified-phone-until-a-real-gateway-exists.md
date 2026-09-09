# 25-39 · A tenant can accept an unverified phone, until a real gateway exists

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing to build against — the gap it works around (`14-15`, no live SMS/voice
  gateway account) is itself undecided on vendor, and this item does not wait for that decision.
- **Found**: 2026-09-09, live — the author testing the calendar end to end today reached the
  verified-phone booking step and could not complete a booking, because `14-15`'s own mechanism has no
  live gateway account in this environment (`UnconfiguredPhoneVerificationSender`) and cannot deliver
  a real code to a real phone at all. Every booking through the chat-driven flow is uncompletable today,
  not just untested.

## Why this isn't "just turn verification off"

`20-09`/`20-10` require a verified phone before a booking is held, deliberately — a booking is a
real-world commitment against a worker's calendar, and a self-reported string is not proof of anything.
That guarantee is correct and this item does not remove it as a default. The problem is narrower and
temporary: **there is currently no way to satisfy it at all**, because no vendor account has been
provisioned (`14-15`'s own recorded "undecided, needs a cost quote" — Open questions). Until that
changes, `RequiresVerifiedPhone: true` doesn't protect anything — it just makes every booking fail.

## Scope

- A tenant-level setting (alongside `Site.WidgetConfig.RequireContactConsent`'s own pattern —
  `ago-chat`'s `WidgetConfig`, surfaced from the console) that a tenant can turn on for their own site:
  bookings through the chat-driven module proceed with a self-reported, unverified phone number,
  instead of refusing at `ReplyToModuleTaskHandler.HandlePhoneProvidedAsync`'s `RequiresVerifiedPhone:
  true`.
- **Off by default.** A tenant who never touches the setting keeps today's guarantee unchanged.
- **The booking record itself must say the phone was never verified** — not silently treated as
  equivalent to a verified one. Whatever reads `customers.phone_verified_at` downstream (operator
  console, any future no-show/reminder logic) must be able to tell the two cases apart.
- **Labelled honestly in the console** as a temporary relaxation, not a feature — e.g. naming that it
  exists because phone verification has no live provider yet, so a tenant understands what they're
  giving up and why, and so nobody mistakes it for a permanent choice.

## Where this is likely to go wrong

- **Do not silently mark an unverified phone as verified** to satisfy `RequiresVerifiedPhone` — that
  would corrupt the one signal `14-15`/`20-09` exist to produce, for every consumer of
  `phone_verified_at`, forever, not just for this tenant's bookings today. The bypass must be its own
  explicit path, not a fake verification.
- **The public booking widget (`20-10`) has the identical requirement, in a different codebase's own
  mirrored mechanism.** Decide explicitly whether this item's setting also covers that surface or is
  chat-module-only for now — don't discover the mismatch after shipping one and assuming the other is
  covered.
- This is a workaround for a missing vendor account, not a reason to deprioritize `14-15`'s own open
  gateway decision — a real tenant taking real money needs real verification eventually.

## Done when

- [ ] A tenant can turn the setting on for their own site, off by default.
- [ ] With it on, a booking through the chat-driven flow completes with a self-reported phone and no
      verification code sent or required.
- [ ] The booking/customer record distinguishes an unverified phone accepted this way from a genuinely
      verified one, proven by a test.
- [ ] The console states plainly, next to the setting, why it exists and that it is temporary.
- [ ] Explicitly decided and recorded whether `20-10`'s public widget path is covered by the same
      setting or left for a separate item.
