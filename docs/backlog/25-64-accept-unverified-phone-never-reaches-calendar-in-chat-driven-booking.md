# 25-64 · `AcceptUnverifiedPhone` never reaches Calendar in a chat-driven booking

- **Stage**: 25
- **Status**: ready
- **Verified**: 2026-09-12 — reproduced live end-to-end against current `main` in both `ago-chat` and
  `ago-calendar` (a from-scratch local stack, not the stale demo deployment): drove a real chat-driven
  booking through the widget with `sites.widget_accept_unverified_phone = true`, an unverified
  `+79991234567` typed at the `verified_phone_form` step. The module task
  (`01a09638-02ac-770f-9fa8-b29f3bb7b8fa`) stayed open at `verified_phone_form`, `closed_at` null, and
  the targeted calendar event (`01a095ea-3517-766e-b102-28b593525a92`, 2026-09-12 15:30 UTC) stayed
  `status = 'Available'` — the booking never happened. The visitor instead saw
  `RouteConversationToModuleHandler.PhoneVerificationRequiredText`: "Before I can book that, please
  verify this phone number - we'll send you a code by SMS or call."
- **Depends on**: nothing — `adr/0163` is already accepted and `ago-chat`/`ago-calendar` both build; this
  is a gap in how the accepted decision was carried out, not unfinished dependent work
- **Found**: 2026-09-12, while running the E2E test the author asked for specifically to exercise this
  setting ("проведи e2e тестирование всего флоу записи в календарь с использованием непроверенных
  данных")

## What is actually true

`adr/0163` decided: with `WidgetConfig.AcceptUnverifiedPhone` on, "the phone step still renders, but
without demanding proof of control over the number" — the relaxation was meant to move the
verified-vs-unverified decision onto `Ago.Calendar`'s own `BookEvent` (`RequiresVerifiedPhone =
!acceptUnverifiedPhone`, "computed fresh on every reply").

`Ago.Chat.Application.UseCases.RouteConversationToModule.RouteConversationToModuleHandler.ContinueActiveTaskAsync`
(`RouteConversationToModuleHandler.cs:227-263`) still enforces the pre-`0163` guarantee unconditionally.
When the active step's kind is `PrimitiveKinds.VerifiedPhoneForm`, it looks up an actual
`ChannelIdentity` (`channelIdentities.FindAsync(site, Sms, address)`) for the visitor and, if none
exists, returns `RouteConversationToModuleOutcome.PhoneVerificationRequired` **immediately** — the
method returns before it ever reaches `ResolveModuleContextAsync` (the call that reads
`site.WidgetConfig.AcceptUnverifiedPhone`) or `gateway.SubmitReplyAsync` (the call that would carry
`acceptUnverifiedPhone` to Calendar). The block's own comment states the design as written: "before the
module is ever called... Calendar never sees this decision; it only ever sees its result (a timestamp,
or no reply at all)." That comment predates `0163` and was never updated when `0163` landed — Calendar
is built to honor `acceptUnverifiedPhone` (`docs/adr/0163`'s own text, and `BookEventHandler`'s
`RequiresVerifiedPhone = !acceptUnverifiedPhone`), but Chat never lets an unverified reply reach it in
the first place, so that half of Calendar's own logic is currently unreachable from the chat-driven
surface.

The standalone public booking widget (`20-10`) is unaffected — `adr/0163`'s own text says it was never
in scope, and it has its own already-working verification mechanism.

## Scope

- `RouteConversationToModuleHandler.ContinueActiveTaskAsync`: when `LastStepKind == VerifiedPhoneForm`
  and no verified `ChannelIdentity` is found for the visitor, consult the site's
  `AcceptUnverifiedPhone` setting (a call to `ResolveModuleContextAsync`, or the relevant part of it,
  moved earlier) before deciding. Refuse with `PhoneVerificationRequiredText` only when the setting is
  off; when it is on, fall through and forward the reply to Calendar exactly as `0163` describes —
  `phoneVerifiedAt` stays `null` (the identity genuinely was never proven), and Calendar's own
  `RequiresVerifiedPhone = !acceptUnverifiedPhone` is what actually decides whether the booking
  completes.
- Update this method's own doc comment (`RouteConversationToModuleHandler.cs:213-225`), which currently
  describes the pre-`0163` guarantee as absolute ("Calendar never sees this decision") — false once this
  item lands, and confusing to the next reader if left as is.
- Confirm (or add, if missing) a chat-side integration test that drives a `VerifiedPhoneForm` reply with
  `AcceptUnverifiedPhone` on and no `ChannelIdentity`, and asserts the reply **does** reach the gateway
  (i.e. `gateway.SubmitReplyAsync` is called, not short-circuited) — the exact case this item's own
  live reproduction exercised and the existing suite apparently does not cover, since this shipped and
  merged without it being caught.

## Where this is likely to go wrong

- **Do not weaken the verified-identity check when the setting is off.** The default (`false`) must
  keep demanding proof of control exactly as today — this item only stops the check from running ahead
  of the setting, it does not relax the check itself.
- **`phoneVerifiedAt` must still be computed honestly.** When a verified identity *does* exist, keep
  setting `phoneVerifiedAt = identity.FirstSeenAt` regardless of `AcceptUnverifiedPhone` — a verified
  number stays verified; this item only changes what happens when one is *not* found.
- **This is a `Ago.Chat` fix only.** `Ago.Calendar`'s own `RequiresVerifiedPhone = !acceptUnverifiedPhone`
  (`0163`'s Decision) already does the right thing once it actually receives the reply — confirmed live
  during this item's own reproduction (a hand-signed `X-Ago-Module-Credential` call straight to
  `Ago.Calendar.Api`'s `/api/v1/module-tasks` returned the real `choice_list` for "Haircut" correctly);
  nothing in `ago-calendar` needs to change.

## Done when

- [ ] With `AcceptUnverifiedPhone` on and no verified `ChannelIdentity` for the visitor, a reply to a
      `VerifiedPhoneForm` step reaches `gateway.SubmitReplyAsync` (Calendar decides, not Chat) instead of
      short-circuiting to `PhoneVerificationRequiredText`.
- [ ] With `AcceptUnverifiedPhone` off (the default), behavior is byte-for-byte unchanged from today —
      an unverified reply still gets `PhoneVerificationRequiredText`, the task stays open.
- [ ] A verified `ChannelIdentity`'s `phoneVerifiedAt` is still forwarded correctly regardless of the
      setting.
- [ ] A live, end-to-end, chat-driven booking with `AcceptUnverifiedPhone` on completes for real — the
      targeted calendar event moves out of `Available` and the module task closes — proven the same way
      this item's own investigation proved the bug (a real conversation, not a mock).
