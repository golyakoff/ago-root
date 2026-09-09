# 25-37 · The booking module's own text is hardcoded English

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-09, live, reported by the author mid-booking on the real deployment — every
  step of the chat-driven booking flow renders in English regardless of the visitor's language.
- **Depends on**: none. Touches `ago-calendar` only.

## The gap

`ModuleStepFactory` (`ago-calendar/src/Ago.Calendar.Application/UseCases/ChatModuleTask/ModuleStepFactory.cs`)
is the single place that turns booking state into the `ModuleStep` prompts a visitor reads — and every
string in it is a hardcoded English literal: `"What would you like to book?"`, `"Who would you like to
book with?"`, `"Pick a time:"`, `"What's the best phone number to reach you on?"`, `"You're booked!"`,
the confirmation labels (`"Service"`, `"With"`, `"When"`), and the price suffix (`"from {amount} RUB"`).

None of it goes through any locale mechanism. A Russian-speaking visitor on a Russian tenant's site
gets an English booking flow end to end, even though the rest of the widget (`11-10`) and the tenant's
own console (`11-11`–`11-16`) are already localized.

## Scope

- Give `ModuleStepFactory` a locale input and Russian strings for all of the above, following whatever
  pattern `ago-chat`'s own module-reply text already uses for locale (check `23-56`'s machine-reply
  naming and how `RouteConversationToModuleHandler` threads locale/tenant context to a module, if it
  does yet — this may be new plumbing rather than a lookup).
- `DescribeRange`'s `"UTC"` labelling stays as-is (`docs/conventions/date-and-time.md` rule 1 — no
  visitor IANA zone is known in a chat channel); only the surrounding prose needs a language.

## Where this is likely to go wrong

- Calendar's module boundary may not currently carry a locale at all — resist the temptation to guess
  the visitor's language from the phone country code or similar; find the real source (site's own
  configured language, `11-15`) or say plainly that the plumbing doesn't exist yet and scope that
  instead.
- Don't localize the price's currency (`RUB` stays; only the surrounding words change).

## Done when

- [ ] Every `ModuleStepFactory` string renders in the tenant's configured language, proven by a test
      that asserts the Russian variant for at least one tenant.
- [ ] English remains available for a tenant configured that way — this is localization, not a
      hardcoded swap from one language to another.
