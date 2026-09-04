# sixteen produced error codes are not mapped, and return 500

- **Stage**: 22
- **Status**: done (2026-09-04), `ago-calendar#40`. Includes the set-mismatch guard the third Done-when
  left open as a decision — built, and shown to fail with an arm removed
- **Found**: 2026-09-04, while doing `22-15` — which swept the *other* direction.

## The gap

`ago-calendar`'s `ErrorExtensions.ToProblem` switches on an error code to choose an HTTP status, and
ends with `_ => StatusCodes.Status500InternalServerError`. Sixteen codes that real handlers construct
are not named in that switch, so every one of them reaches an operator as **500 Internal Server
Error**:

```
recut.forbidden                      recut.worker_not_found
recut.worker_not_on_a_calendar       recut.worker_has_no_schedule
recut.from_before_today              recut.not_a_regression
recut.horizon_before_from            recut.stale
recut.missing_decision               recut.day_changed_concurrently
recut.invalid                        worker_slots.forbidden
worker_slots.worker_not_found        worker_slots.invalid_range
availability.worker_has_no_schedule  configuration.no_schedule
```

They are reached from live console endpoints — `/workers/{id}/schedule/recut` and its `preview`,
`/workers/{id}/slots`, the day-boundary edit and the worker-schedule read — all wired in
`ConsoleEndpoints.cs` and all returning through `.ToProblem(httpContext)`.

## Why this is worse than it looks

**`recut.forbidden` is a permission refusal.** An operator without the right permission on
`/workers/{id}/schedule/recut` is currently told the server broke. So is one who names a worker that
does not exist (`recut.worker_not_found` — a 404), and one whose edit lost a race
(`recut.day_changed_concurrently` — a 409, the one case where the client's correct response is to
reload and retry, which nothing can infer from a 500).

Three separate things follow from a 500 that do not follow from the right status:

- **The console cannot tell the user anything useful**, because a 500 has no per-case meaning to
  branch on.
- **A 500 is an alert.** If anything watches error rates, an ordinary permission refusal is
  indistinguishable from a fault, which is how a real fault gets lost in the noise.
- **`api-design.md`'s contract is broken silently.** The `problem+json` body still carries the right
  `code`; only the status lies. So a reader of the response body sees a coherent error, and a reader
  of the status sees a crash.

## Why it is not part of `22-15`

Different promise. `22-15` is *no mapping names a code nothing produces* — dead arms removed. This is
*every produced code is mapped* — missing arms added. Each lands green alone, and `22-15` shipped
without this.

They were found together because the same enumeration answers both, which is worth saying: the check
is "match the set of produced codes against the set of mapped codes", and each direction of the
mismatch is a different bug.

## What has to be decided rather than defaulted

**The status for each code, one at a time.** `ErrorExtensions` already carries comments arguing
individual choices — `booking.public_api_disabled` is 403 rather than the 404 its neighbours use, and
`access.account_owner_requires_contact_access` was 409 rather than 403 because the caller *is*
permitted in general and the aggregate refuses the particular request. Those arguments are the value
of the file; sixteen codes mapped by prefix convention would throw that away.

In particular `recut.stale`, `recut.day_changed_concurrently` and `recut.not_a_regression` are all
"the world moved" refusals rather than bad requests, and 409 is probably right for all three — but
that is a judgement to make and record, not to assume.

**And the mismatch should stop being findable only by accident.** Both `22-15` and this were found by
a person reading the file for another reason. A test that enumerates constructed codes and asserts
every one is mapped would catch both directions forever; whether that is worth its cost is part of
this item.

## Done when

- [ ] Every code any handler constructs has a mapping, and the status chosen for each is argued where
      the argument is not obvious.
- [ ] `recut.forbidden` returns 403 and `recut.worker_not_found` returns 404, proven over real HTTP
      rather than at the switch — the endpoint is what a person meets.
- [ ] The set-mismatch is checked by something that runs, or the decision not to check it is recorded
      with its reason.
