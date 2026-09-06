# ADR-0140: Widget config freshness is a day, not the identity token's own renewal window

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-54`)

## Context

`adr/0029` decided config is read once, at bootstrap, and named its limitation plainly: a visitor
with the widget already open on their page will not see a changed color or position until that page
is reloaded. `17-07` later gave a returning visitor's *identity* token a renewal cycle - exchanged
for a fresh one once less than a third of its 7-day lifetime remains - and, as a documented side
effect, that same exchange refreshes the cached `widgetPrimaryColorHex`/`widgetPosition`/
`widgetLocale`/notice fields too, because they ride the identical response shape
(`POST /api/v1/visitor-sessions`(`/renew`)).

That side effect quietly became the *only* mechanism keeping a returning visitor's cached config
current, and it is a bad fit for that job: the identity renewal window only opens once **two-thirds**
of the token's 7-day lifetime has passed. A returning visitor's browser - the ordinary case for
anyone who embedded the widget on their own site to check a change, not an edge case - holds a token
nowhere near that window on almost every page load, so an ordinary reload, and even a hard reload
(`Ctrl+F5`, which bypasses the HTTP cache but never touches `localStorage`), made **zero** requests
and left a changed colour or launcher position invisible. The visible symptom, and what actually
happened on this project's own live deployment: a tenant changed the widget's colour and position in
the console, reloaded the embedding page twice, and saw nothing change until clearing the browser's
site data outright removed the stored session and forced a fresh mint.

This is worse than what `adr/0029` accepted. That decision's named gap was about a tab **already
open** when the change happens - reload it and it is current. What actually shipped left a **closed
and reopened tab** stale too, for any returning visitor, for up to `2/3` of the identity token's own
lifetime (roughly 4 days 16 hours) - and the console's own copy on `/settings/widget`
(`widgetDescription`, `ago-console`) told the operator making the change "changes here take effect the
next time a visitor's page loads the widget," which was simply false for that visitor.

Two shapes were available to fix it, with very different costs:

1. **Refetch config on every single page load**, for every tenant's site, regardless of how old the
   cached copy is. Correct in the sense of "always current," but it turns a value `caching.md` already
   characterizes as low-frequency into a mandatory network round trip on every visit, for every site
   this product ever hosts - the cost `adr/0029`'s own "Alternatives considered" section declined to
   pay for a live-push channel, paid instead as a blanket policy.
2. **A cache with a sensible, bounded expiry**, decoupled from the identity token's own renewal
   schedule, using the endpoint that already exists.

## Decision

**A day.** `ago-widget`'s `VisitorSessionManager.start()` now renews (`POST
/api/v1/visitor-sessions/renew`) whenever *either* the identity token has entered its own renewal
window (unchanged from `17-07`) *or* `CONFIG_REFRESH_INTERVAL_MS` (24 hours) has passed since the
stored token - and so the config cached beside it - was last minted or renewed. The check reads the
same `nbf`/`iat` claim `tokenExpiry.ts` already reads for the identity window, for the identical
reason that file gives for reading `exp` rather than storing a second, driftable copy of the fact: one
answer, correct for every session already on a visitor's device rather than only the ones written
after this shipped.

No new server endpoint, no new response shape, no new stored field. The existing renewal endpoint
already returns current config on every call; this only changes *when the widget decides to call it*.
`adr/0029`'s own still-standing limitation - an already-open tab does not update live, full stop - is
untouched by this: the fix is entirely about what a **reload** does, which is the case `adr/0029`
assumed would already be current and the console's own copy already promised.

**A day**, specifically, because that is the number the tenant who hit this defect found acceptable
to explain to their own visitors, and because it is short enough that "changes take effect within a
day" is now an honest sentence rather than the false "next page load" the console said before. It is
a UX freshness budget, not a security boundary - nothing about the identity, the token's validity, or
the visitor's authorization depends on it - so it is free to move independently of
`RENEWAL_THRESHOLD_FRACTION` or the identity token's own lifetime, unlike the number this decision
replaces as the *de facto* freshness bound.

`ago-console`'s `/settings/widget` copy and its tenant-facing `/settings/device-storage` disclosure
page are updated in the same change to state the real number, rather than the "next page load"
promise that was never quite true for a returning visitor.

## Consequences

- A returning visitor whose browser already holds a valid, out-of-window token now costs the API at
  most one extra request per day, instead of zero requests for up to `2/3` of the token's 7-day
  lifetime. Bounded, and far short of "every page load."
- The console's own copy on `/settings/widget` and the tenant-facing device-storage disclosure now
  state a real, honest number instead of a promise the implementation did not keep.
- `storage.disclosure.test.ts` and its `ago-console` hand-maintained counterpart needed no new row -
  this changes *when* an existing write path runs, not what it writes.
- A tenant who needs a change to appear inside minutes, not up to a day, still has no mechanism for
  that - `adr/0029`'s live-push alternative remains undecided and unbuilt, for the same cost reasons
  that ADR gave.

## Alternatives considered

- **Refetch config on every page load, unconditionally.** Rejected: turns a low-frequency value into
  a mandatory round trip for every visit to every tenant's site, the cost `adr/0029` already declined
  to pay for a stronger guarantee (live push) - paying it for a weaker one (bootstrap-time freshness)
  is a worse trade, not a better one.
- **Leave it exactly as `17-07` left it, and only fix the console's copy to state the true, longer
  bound (up to `2/3` of the identity token's lifetime).** Rejected as the sole fix: the true number
  it would have had to state - four to five days, worst case - is not a number this project's own
  author found acceptable when asked, and a defect that is merely *documented* accurately is still a
  defect a tenant experiences the same way. The copy fix landed anyway, alongside the code fix, because
  a promise the code cannot keep is worth correcting regardless of which number ends up true.
- **A separate stored "config last synced at" timestamp**, written alongside the session. Rejected for
  the same reason `tokenExpiry.ts` already gives for reading `exp` from the token instead of storing
  a parallel expiry: a second copy of the same fact that can drift from it, and one that would need a
  response-shape change and leave every already-stored session with no value to read. Reading the
  existing `nbf`/`iat` claim works on every session already on a visitor's device today.
