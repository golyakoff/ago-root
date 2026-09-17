# 25-132 · The booking module's Russian copy reads wrong

- **Stage**: 25
- **Status**: done — `ago-calendar#68`
- **Found**: 2026-09-17, live, reported by the author mid-booking on the real deployment.
- **Depends on**: none. Touches `ago-calendar` only.

## The gap

`ModuleStepFactory`'s Russian `Strings` table (`ago-calendar/src/Ago.Calendar.Application/UseCases/
ChatModuleTask/ModuleStepFactory.cs:270-292`, built by `25-37`) has three lines the author wants
reworded, having now actually read them mid-flow rather than only checked that they render:

- `WhichService`: "Что вы хотите забронировать?" → **"Выберите услугу для записи:"**
- `WhichWorker`: "С кем вы хотите записаться?" → **"К кому вы хотите записаться?"** (grammar)
- `Booked`: "Вы записаны!" → **"✅ Готово!"** — the author wants a clear, upbeat, unambiguous success
  message once a slot is actually booked, an emoji included.

## Scope

- Change exactly these three Russian strings. The English table is untouched — this is a wording
  pass on copy already scoped as localized, not a new localization decision.
- Update every test that asserts the old Russian text verbatim (found by reading, not re-derived by
  the worker): `ago-calendar/tests/Ago.Calendar.Application.Tests/ChatModuleTaskHandlerTests.cs`
  (around lines 231, 243, 248) and `ago-calendar/tests/Ago.Calendar.Integration.Tests/
  ChatModuleTaskEndpointTests.cs` (around lines 161, 166) — grep for the old strings to find every
  occurrence rather than trusting these line numbers, which will have drifted.

## Where this is likely to go wrong

- Don't touch `PickADate`/`PickATimeOnDate`/the phone prompts/the confirmation labels — only the
  three strings named above are in scope. A wording pass that also rewrites six other lines nobody
  asked about makes the diff harder to review for exactly the sentence that mattered.
- `Booked` is the confirmation card's *title* (`ModuleStepFactory.Confirmation`). Adding an emoji
  there is plain text, not markup - confirm it round-trips through the JSON payload/EF/Postgres
  storage without escaping issues (it should - existing Cyrillic text in the same table already
  proves UTF-8 storage works) but actually render it once rather than assuming.

## Done when

- [x] A Russian-locale site's service step reads "Выберите услугу для записи:"
- [x] The worker step reads "К кому вы хотите записаться?"
- [x] The confirmation card's title reads "✅ Готово!"
- [x] Every existing test asserting the old Russian strings is updated to the new ones, and the full
      `ago-calendar` suite is green

## Outcome

Landed exactly as scoped - three strings in `ModuleStepFactory`'s Russian table, six test assertions
across two test files updated to match. Full `ago-calendar` suite green: Application 209, Domain 235,
Architecture 28, Concurrency 26, Integration 334 - 832 tests, 0 failed. `ago-calendar#68`.
