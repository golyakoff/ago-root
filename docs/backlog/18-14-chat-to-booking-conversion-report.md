# Chat-to-booking conversion report — an honest proxy, not a confirmed-booking count

- **Stage**: 18
- **Status**: done (`ago-chat#132`, `ago-console#66`, merged 2026-08-30)
- **Depends on**: `20-07-calendar-becomes-a-chat-module.md` (done) — the `module_tasks` table this
  item reads; `18-10-conversation-outcome-and-conversion-report.md` (ready — build in either order,
  this item does not touch any file `18-10` scopes) — the same "operator-reported outcome" honesty
  discipline this item's own limitation echoes, for a structural rather than a self-reporting reason

## Goal

A site owner can see how many conversations actually started a booking flow through `20-07`'s calendar
module, and what fraction of those flows finished — the other half of
`ago-business/docs/decisions/0009`'s named "воронка продаж" (sales funnel) gap, specifically for the
one conversion path this system can observe structurally rather than rely on an operator to self-report
(`18-10`'s own path). This is the literal question the author asked for by name: "конвертировалось ли в
запись" (did it convert into a booking).

## Read this before scoping anything else: what this item can honestly claim, and what it cannot

`ModuleTask` (`Ago.Chat.Domain/ModuleTask.cs`) has exactly one state transition, `Open` → `Closed`
(`ModuleTaskState.cs` has two members, nothing else). Chat cannot and structurally must not know more
than that: `adr/0065` decision 1 is that Chat holds a task's id and whether it is open, nothing about
what the module is doing inside it, and `adr/0077` confirmed no cross-repo query is possible at all —
`Ago.Chat`'s own Postgres and `Ago.Calendar`'s own Postgres are different databases on the same node,
never joined. **A closed `calendar` module task is not the same fact as a confirmed booking.** A
visitor can open the booking flow and abandon it, an operator can close the conversation with the flow
still mid-step, or the flow can finish with the visitor declining every offered slot — every one of
these closes the `ModuleTask` identically to a real confirmed booking, because closing is the only
signal Chat's own schema is capable of holding today.

`docs/roadmap.md`'s own parked-items table already names the deeper version of this exact tension as
`20-08` ("who confirms a chat-originated booking") — unstarted, and this item does not wait for it or
attempt to resolve it. The two are related but distinct: `20-08` is about *authority* (who is allowed to
confirm a booking that originated in chat); this item is about *reporting* (what can honestly be said
about how many conversations reached a closed booking flow). Building this item now, honestly labelled,
is the same call `18-10` already made for a different reason — ship a real, useful, clearly-bounded
number now rather than block reporting on an unresolved architectural question elsewhere. **If `20-08`
or a future Calendar-side change ever publishes a real distinguishing outcome back over the module
contract, this report's own query gets more precise without changing its shape — the same "improves
without changing" relationship `18-11` already has with `19-02`.**

## Scope

- A new read-store query (own file, does not touch `OperatorAnalyticsReadStore.cs` — a different
  question over a different table, `module_tasks` rather than `conversations`/`messages`) counting, per
  site and date range: conversations whose `in_window` set has at least one `module_tasks` row with
  `module_key = 'calendar'` (a runtime string comparison against the opaque `ModuleKey` value, never a
  compile-time reference to anything calendar-shaped — the same boundary `ChatModule`'s own module
  registration already respects), split by that task's own `state` (`Open` vs `Closed`).
- **The report's own label is the load-bearing part of this item.** Whatever the console renders must
  say "started a booking flow" and "flow closed" — never "booked," "converted," or "confirmed." This is
  not a wording nitpick; it is the actual scope boundary between what this item builds and the
  cross-repo signal it explicitly does not have.
- A single-conversation edge case to get right: a conversation can only start one `calendar` task in
  the current module design (confirm this against `Conversation.StartModuleTask`'s own invariant before
  assuming it — if it turns out a conversation can hold more than one, decide and record whether this
  report counts conversations or tasks, they are not the same denominator once that's possible).
- Console: its own small block, not folded into `18-10`'s outcome buttons or `18-08`'s existing table —
  a different data source and a materially different honesty caveat deserves to stay visually distinct,
  not collapse into a shared table where a reader would apply one caveat to both numbers.

## Out of scope

- Any join, query, or API call against AGO Calendar's own database or service — forbidden by `adr/0027`/
  `adr/0077` regardless of how useful it would be; this item's own ceiling is what `Ago.Chat`'s own
  schema already knows.
- Resolving `20-08`'s own open question — named above as related context, not reopened or answered
  here.
- A real confirmed-booking count — the thing this item is explicitly not claiming to be. If a future
  item wants that number, it needs Calendar's own outbox (`BookingConfirmed`, already named in
  `personal-data.md`) to publish something Chat can honestly attribute back to a conversation, which is
  new cross-product wiring, not a variation of this report.

## Done when

- [x] The report correctly counts started-vs-closed `calendar` module tasks per site and date range
      against real seeded data, proven by a test that includes a conversation with no module task at
      all (must not appear as a zero-row false positive) and one still `Open` at report time.
- [x] The console's own copy states the "flow closed, not confirmed booked" distinction in the text a
      site owner actually reads, not only in this document. Independently re-proven by the managing
      session: removing the `Alert` rendering the caveat made the dedicated test fail on the expected
      copy.
- [x] Cross-site isolation is proven by a test. Independently re-proven by the managing session:
      loosening the read-store's `site_id` filter made all 8 `ModuleFlowReadStoreTests` fail.
- [x] Cross-module isolation: a site with an enabled module other than `calendar` (if any exist by the
      time this is built) does not appear in this report's numbers — proven by a test, not assumed from
      the `module_key` filter alone.

## Open questions

Whether a conversation can start more than one `calendar` module task in the current design, and if so
whether this report counts conversations or tasks — resolve by reading `Conversation.StartModuleTask`
before writing the query, record the answer, do not guess.
