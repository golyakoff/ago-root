# 25-39 · A tenant can accept an unverified phone, until a real gateway exists

- **Stage**: 25
- **Status**: done — `ago-calendar#56`, `ago-chat#247`, `ago-console#189`; `adr/0163`
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
  `ago-chat`'s `WidgetConfig`, surfaced from the console) that a tenant can turn on for their own site.
- **With it on, the flow does not stop to ask at all.** The point is not merely "accept an unverified
  phone if one is typed in" — it is that a visitor who already gave a phone number earlier in the same
  conversation (`25-38`'s own subject) sees the booking complete the moment they pick a slot.
  `ReplyToModuleTaskHandler.HandleSlotChosenAsync` currently always returns `ModuleStepFactory.PhoneForm()`
  next (`ReplyToModuleTaskHandler.cs:181`); with the setting on and a phone already known from the
  conversation, it should instead call straight through to what `HandlePhoneProvidedAsync` does today,
  passing that already-known number with `phoneVerifiedAt: null` — no form step rendered, no
  `VerifiedPhoneForm` shown, nothing for the visitor to type.
- **If no phone is known yet at all** (a visitor who reached booking without ever going through chat's
  own contact capture), the setting does not invent one — the phone step still has to be shown, just
  without the verification requirement (`RequiresVerifiedPhone: false` instead of skipped entirely).
  Name this second case explicitly in the implementation; it is the fallback, not the common path.
- **Off by default.** A tenant who never touches the setting keeps today's guarantee, and today's
  step-by-step flow, unchanged.
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

- [x] A tenant can turn the setting on for their own site, off by default.
- [x] With it on and a phone already known from earlier in the conversation, picking a slot completes
      the booking directly — no phone-form step is shown at all, proven by a test asserting the reply
      to `HandleSlotChosenAsync` is a completion/confirmation step, not `PhoneForm`.
- [x] With it on and no phone known yet, the phone step still appears, but without the verification
      requirement — proven by a test.
- [x] With it off (default), both of the above are unchanged from today's behaviour.
- [x] The booking/customer record distinguishes an unverified phone accepted this way from a genuinely
      verified one, proven by a test.
- [x] The console states plainly, next to the setting, why it exists and that it is temporary.
- [x] Explicitly decided and recorded whether `20-10`'s public widget path is covered by the same
      setting or left for a separate item.

## Outcome

`WidgetConfig.AcceptUnverifiedPhone` (renamed from the first-drafted `AcceptUnverifiedPhoneBooking`
after `Ago.Chat.Architecture.Tests`' own `MessageOpacityTests.NoProductAssembly_NamesAnotherProductsDomain`
caught "booking" naming Calendar's own domain from inside `Ago.Chat.*`) is the one migration this wave
carries, following `AttractAttention`'s established shape. `ReplyToModuleTaskHandler.HandleSlotChosenAsync`
(`ago-calendar`) is the setting's real core: with it on and a known phone, it calls straight into
`HandlePhoneProvidedAsync` with `phoneVerifiedAt: null`, no form step ever built; with it on and no
phone known, `ModuleStepFactory.PhoneForm` emits plain `ModuleStepKind.Form` instead of
`VerifiedPhoneForm` — the kind distinction is what actually turns off Chat's own gate
(`RouteConversationToModuleHandler.ContinueActiveTaskAsync` only demands `14-15` evidence ahead of a
`verified_phone_form` reply), not merely a hint Calendar could ignore. `BookEvent.RequiresVerifiedPhone`
is `!acceptUnverifiedPhone`, computed fresh on every reply; `PhoneVerifiedAt` stays exactly what the
caller passed (`null` on the skip path), so the record never lies about verification. `20-10`'s public
booking widget is explicitly **not** covered — recorded in `BookEvent.cs`'s own doc comment — it has
its own working verification mechanism and never had `14-15`'s missing-vendor problem. Console UI:
a "Booking (temporary)" panel on the widget-config screen, off by default, labelled as a workaround
for the missing gateway rather than a feature. Decision recorded as `adr/0163` (a genuine guarantee
relaxation, opt-in per tenant — the "why on earth" case the ADR skill flags).
