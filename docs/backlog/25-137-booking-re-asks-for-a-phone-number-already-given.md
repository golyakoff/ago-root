# 25-137 · Booking re-asks for a phone number already given

- **Stage**: 25
- **Status**: done — configuration only, no code
- **Found**: 2026-09-17, live, reported by the author: after already providing a phone number, the
  booking flow asks for it again at the phone step, which the author called out as actively
  off-putting to a real customer.
- **Depends on**: `25-136` - only once the contact-capture form is genuinely required upfront does a
  known phone number reliably exist for this item's fix to act on.

## The gap - and why this may need no code at all

This exact complaint was investigated once already, in `25-38` (done, 2026-09-09): booking's phone
step deliberately asks again because it requires a *verified* number (proof of control,
`RequiresVerifiedPhone: true`) while the widget's own contact-capture form collects a
*self-reported, unverified* one - `25-38` kept the second ask but reworded it to explain why.

Since then, `25-39`/`ADR-0163` (2026-09-09) shipped exactly the escape hatch this complaint is asking
for: a per-site `WidgetConfig.AcceptUnverifiedPhone` flag. With it `true` **and** a known phone number
already on the conversation, `Ago.Calendar.Application.UseCases.ChatModuleTask.
ReplyToModuleTaskHandler` (around lines 373-378) skips the verified-phone step entirely and books the
slot directly. **Confirmed live**, 2026-09-17: on the author's own test tenant ("АГО тест теннант"),
`widget_accept_unverified_phone = false` - the flag exists and is simply off for this site, and the
reported repeat-question is `25-38`'s existing prompt for the case where the flag is off.

`ADR-0163` frames this flag as a **temporary** relaxation, off by default, because `14-15` has no live
SMS/voice verification vendor yet - "a tenant cannot consent on their visitor's behalf by staying
silent" (`WidgetConfig.cs`'s own doc comment on `AcceptUnverifiedPhone`). The author's own decision,
2026-09-17: turn this on, accepting the no-show/fraud risk `ADR-0163` names, in order to launch
without the re-ask. **This is an operational per-site configuration change, not a code change** - the
setting already exists and is exposed in the console (`ago-console`'s `WidgetConfigPage`).

## Scope

- Turn `AcceptUnverifiedPhone` on for the site(s) this needs to be true for, through the console's own
  `UpdateWidgetConfig` write path - not a direct database write, so the change goes through the same
  outbox/cache-invalidation path every other widget-config change does.
- Do **not** change `WidgetConfig.Default`'s own coded default (`false`, `WidgetConfig.cs:284`) as
  part of this item. That default, and `ADR-0163`'s "off unless a tenant explicitly asks" framing, is
  a separate, larger decision (whether every *future* tenant should launch with unverified phone
  accepted, superseding `ADR-0163`'s own "temporary" language) that the author's 2026-09-17 decision
  did not clearly reach - it was scoped to fixing the author's own test tenant's flow. If the answer
  turns out to be "yes, change the default too," that's this item's own natural follow-up once
  confirmed explicitly, not an assumption to fold in here.
- Verify live, end-to-end, once `25-136` has also landed: a widget visitor with a contact-capture
  phone on file reaches slot selection and gets a confirmation with no second phone question.

## Where this is likely to go wrong

- Don't weaken `RequiresVerifiedPhone` in code, and don't touch `ReplyToModuleTaskHandler` - the
  mechanism this item relies on already exists and already works exactly as designed; this item is
  configuration, not implementation.
- Until `25-136` lands, a visitor who skips the contact form still has no known phone, so this flag
  alone does not eliminate the re-ask for that visitor - it only eliminates it for one who already
  gave a number. Don't report this item done based on a test that skipped the contact form.

## Done when

- [x] The relevant site's `AcceptUnverifiedPhone` is on, set through the console's own settings page -
      confirmed live against the database (`widget_accept_unverified_phone = true` for the author's own
      test tenant)
- [x] With `25-136` also landed, a live widget booking (service → worker → date → time) with the
      contact form completed goes straight to confirmation with no phone question at all - verified
      live: the author completed a real booking end to end with no repeated phone question
- [x] Whether `WidgetConfig.Default` itself should change, and whether `ADR-0163` needs a superseding
      ADR to stop calling this "temporary," is recorded as an open question for the author rather than
      decided here - left open; the per-site toggle is what the author actually used, not a default
      change

## Outcome

Pure configuration, no code: the author turned `AcceptUnverifiedPhone` on for their own test tenant
through the console (`Каналы → Виджет на сайте → Бронирование (временно)`). Confirmed live, both
against the database and by the author's own successful end-to-end booking with no repeated phone
question. The question of whether this should become the platform-wide default, and whether `ADR-0163`
needs superseding to stop calling the mechanism "temporary," remains open and undecided.
