# 25-32 · The time-picker step offers zero slots despite real availability

- **Stage**: 25
- **Status**: ready
- **Depends on**: `25-31` (the widget-side send bug) is fixed and deployed — this is the next thing
  the booking flow hits once a reply can actually reach the server at all
- **Found**: 2026-09-09, live, continuing the author's own test of the calendar booking flow on
  `golyakov.net` right after `25-31` unblocked it

## What is actually true

Once `25-31` let a structured reply reach the server at all, the booking flow's next step
(`date_time_picker`, "Pick a time:") arrived with **zero slots** — `content` on the persisted message
is literally `{"prompt":"Pick a time:","slots":[]}`, `actions` is empty. This is not a rendering gap:
the calendar (`АГО тестовый календарь`, worker `Алёна Матерн`) has 36 real `Available` events in the
database, starting `2026-09-10 09:00 UTC`, materialized by `25-26`'s own fix earlier the same day.

**A second, unexplained thing happened in the same reproduction, worth recording precisely rather than
guessing at:** the calendar has exactly one bookable worker, and the visible flow went straight from
the service choice to "Pick a time:" — no "Who would you like to book with?" step ever appeared, in
either the widget or the database's own message history for that conversation. Read directly
(`ago-calendar/src/Ago.Calendar.Application/UseCases/ChatModuleTask/ReplyToModuleTaskHandler.cs`,
`ModuleStepFactory.cs`): `HandleServiceChosenAsync` unconditionally returns
`ModuleStepFactory.WorkerChoice(workers.Value)` — there is no single-worker auto-skip branch anywhere
in that handler, `ModuleStepFactory`, or `StartModuleTaskHandler` (checked by name and by pattern —
`grep` for `Count == 1`, `.Single()`, a `[var only]` pattern match, found nothing). What actually
shipped skips a step the code, read cold, does not appear to skip. **This is the open question to
resolve first** — whichever of the two explanations is true changes where the real defect lives:

- If `GetBookableWorkersHandler` itself resolves and silently auto-advances a single-worker case
  (rather than `ReplyToModuleTaskHandler` doing so, which this reading says it does not), the empty
  slots are very likely `GetOpenSlotsHandler` being called with the wrong argument somewhere in that
  path — check what worker/service/calendar id it is actually given.
- If nothing auto-skips and the worker-choice step genuinely never got created, the reply routing
  itself (how a structured reply reaches `ReplyToModuleTaskHandler` at all, from `ago-chat`'s own
  message pipeline) is worth verifying directly rather than assumed — this investigation did not trace
  that hop.

## Where this is likely to go wrong

- **Do not fix the empty-slots symptom without first explaining the skipped step.** They may be the
  same bug (a handler that resolves a single worker also forgets to actually query slots for it) or two
  separate ones — treating them as unrelated risks fixing only the visible half.
- **This conversation's own IDs are real, live evidence, not a hypothetical to reconstruct**: site
  `01a06262-d4f0-7fb6-94e0-9ff702db8a43`, calendar `01a084eb-16be-7865-bcc1-7109fda9c9d9`, worker
  `01a084ec-0c41-78c9-b959-04cb7c1bebf9`, conversation `01a0860e-1e98-77db-aab0-35629f96b442`, service
  reply value `01a0803f-45d1-7388-9d42-30fc53a260b5`. Query against these directly rather than building
  a fresh test fixture from scratch as the first move — the real data already shows the real failure.

## Done when

- [ ] The worker-choice-skip is explained with certainty — which code path actually produced the
      observed transition, named and read, not inferred.
- [ ] "Pick a time:" offers real slots for a calendar that genuinely has them, proven against the same
      live conversation/site this item names, not only a fresh test fixture.
- [ ] A regression test exists for whichever handler was actually at fault, with a fails-before proof.
