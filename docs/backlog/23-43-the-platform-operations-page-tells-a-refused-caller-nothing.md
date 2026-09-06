# the platform-operations page tells a refused caller nothing about the owner

- **Stage**: 23
- **Status**: done (2026-09-06). Two pages, one condition and one sentence each.
- **Depends on**: nothing. Sits beside `23-42`, which removed the same audience's band.
- **Decision**: the author's, 2026-09-06 — *«а для демо оператора ничего не должно быть про
  владельца, проверь»*

## Goal

Somebody who signed in with the published demo login learns nothing about the platform owner —
not that the role exists, not where its view is.

## What the check found

Three surfaces name the platform owner. **Two were already right**, and their gates fail closed in
every direction that is not an explicit yes from the server:

- the rail link in `OperatorShell` — absent while the probe is in flight, on a refusal, and on an
  error, with three tests holding it there;
- the onboarding alert — same gate, same failure direction.

**The server is right too, and this was checked live rather than reasoned about:** a freshly minted
demo operator's token gets **403** from `GET /api/v1/owner/sites` on the deployment as it stands.
`12-01`'s policy is the gate and it held.

**`/owner` and `/owner/{siteId}` were not**, and both are reachable by anyone — the demo console's
operator login is published on the demo pages, so signing in and typing the address needs no
invitation. For a caller the server had just refused, both pages:

1. drew a **"Platform sites" link in the rail**, unconditionally; and
2. said in prose *"This view is restricted to the platform owner."*

## What actually leaked, stated precisely

**No data.** Not a site name, not a row, not a count — the refusal arrives before anything is
fetched, and the pages render no partial state.

**The existence of the role, and the address of its view**, to a reader who is not it. On a console
whose operator login is published, "a reader who is not it" is everybody.

That is a small disclosure and it is worth being honest about its size: this is not a vulnerability
and nothing here was exploitable. It is the console volunteering a fact about its own operator model
to a stranger, which is a thing to stop doing, not an incident.

## The change

**The pinned link renders only once the server has accepted this caller** — the identical condition
`demoNoticeAudience` on the same two pages already used. `"unknown"` draws nothing either, because a
link that appears for a moment and then vanishes on the refusal has already said it.

**The refusal says the caller was refused, and no longer says by what.** Equally true, smaller
disclosure, and the reader who *is* the owner never reaches this branch.

## Why it survived, which is the part worth keeping

**Neither behaviour had a test.** The full suite was green before the change and stayed green after
the first draft of it — 871 passing tests, none of which looked at what a refused caller sees.

Every test on these pages was written from the owner's seat, because the pages are the owner's. The
refused branch existed, rendered, and was reasoned about carefully in its own code comments — and
nobody ever asserted a word of it. **A branch with a thoughtful comment and no test is still an
untested branch**, and comments are exactly what makes one feel covered.

## Done when

- [x] A refused caller sees no platform-sites link, on either page.
- [x] A refused caller is told they were refused and not what refused them.
- [x] Their own console is untouched — this hides one link, it does not strand them.
- [x] Both behaviours are asserted, and each reddens on its own against the old code.

## Out of scope

- The `/owner` route's existence. A stranger typing it still reaches a page that refuses them, which
  is correct: the alternative is a 404 that lies, and this console does not do that anywhere else.
- Whether the demo operator's login should be published at all. That is `8-06`'s decision and this
  item does not reopen it.
