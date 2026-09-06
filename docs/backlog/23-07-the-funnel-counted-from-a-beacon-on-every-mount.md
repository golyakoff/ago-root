# the funnel — loads, opens, conversations — counted from a beacon on every mount

- **Stage**: 23
- **Status**: done (2026-09-06). Three counters on a per-day table, accumulated in memory and
  flushed by a hosted service, with the advice resolved in Domain. Deployed the same day. One
  Done-when clause could not be closed honestly and carries out to `23-40` — see the Outcome.
- **Depends on**: `23-06` — the sighting record and the installation read this extends
- **Decision**: `docs/design/decisions.md` §3, the funnel half and the *beacon* amendment
  (2026-09-04)

## Goal

The tenant sees three numbers rather than one — widget loads, panel opens, conversations started —
and, when one of them is zero, advice that matches *which*. §3: one figure without a denominator
reads as advertising; three make the tenant see where they lose people.

## Why a beacon, and why it is not optional

§3's amendment, and it is the reason this item is not just a counter. The widget mints a visitor
session at mount — but `ago-widget/src/session.ts` `start()` returns the stored session **with no
network call at all** when the token is outside its renewal window, and `ChatWidget.bootstrapSession`
says so in its own doc comment ("for a returning visitor with a token nowhere near expiry it resolves
synchronously-fast from storage with no request at all"). So loads counted from mints and renewals
systematically undercount returning visitors, and the open rate computed against that denominator is
**inflated** — a number wrong in the flattering direction, which decision 7 refuses.

So the widget sends one beacon per mount. §3 states what that costs and what it must therefore be:
**the highest-volume public endpoint in the product** — no authentication, a tiny body, and **no
database write per call**.

## The advice rule, which is the load-bearing half

It is a rule about honesty, not layout:

- **zero loads** → the script is not on the page, or its origin is refused. Recommending a channel
  here is actively harmful: the person goes off to connect Telegram instead of fixing the install.
- **loads, no opens** → placement, appearance, first line. A channel will not help.
- **opens, no conversations** → *here* channels, offline auto-reply and response time are right.
- **no loads but the product is in use** → `23-06`'s fourth state. None of the above applies, and the
  install advice must not be produced.

And: **only ever recommend what that tenant can actually act on.** Advice ending at "available on
another plan" reads as a sale, and the whole point of the block is that it is on the tenant's side.

## Context to read first

- `docs/design/decisions.md` §3 in full
- `docs/design/flows.md` 4.1 and 4.4; `docs/design/ui-inventory.md` §6.1, §9.5
- `.claude/skills/embeddable-widget/SKILL.md` — anything added to the mount path runs on somebody
  else's page
- `Ago.Chat.Module/Pipeline/BatchAccumulator.cs` and `BatchFlusherService.cs` — the shape to copy,
  not the types to reuse: theirs is a *message* batch
- `Ago.Chat.Api/Auth/AuthEndpoints.cs` and `VisitorSessionRateLimitOptions` — the existing
  unauthenticated public endpoint and how it is rate-limited
- `ago-widget/src/ui/widget.ts` (`mount`, `bootstrapSession`, `toggleOpen`) and `src/session.ts`

## Scope

- **The endpoint**: one unauthenticated `POST` taking the site's public key and an event kind
  (`load` | `open`) and nothing else. It resolves the site through the same cache-aside read the
  session mint uses, applies the same origin check, and is rate-limited per IP through
  `IRateLimiter`. **It writes nothing synchronously.**
- **Accumulate and flush.** Build the pair on the shape `BatchAccumulator`/`BatchFlusherService`
  already establish, in `Ago.Chat.Module`, flushing into a per-site, per-day counter table
  (`site_widget_activity`: `site_id`, `day`, `loads`, `opens`, `conversations`). §3 licenses
  approximation, so **losing an unflushed batch to a pod restart is acceptable and is written into
  the item** rather than engineered away. A systematic undercount of one whole class of visitor is
  *not* the same thing and is what the beacon exists to remove.
- **The beacon also feeds `23-06`'s `last_seen_at`**, through the same conditional update, which is
  what closes that item's stated returning-visitor gap.
- **Loads**: one beacon per widget mount, sent from `ChatWidget.mount`, before and independently of
  the session bootstrap so a mount whose bootstrap fails still counts as a load it can honestly
  claim.
- **Opens**: `toggleOpen()` makes no network call today. It sends one `open` beacon per session, not
  per click.
- **Conversations**: already observable — a conversation is created on a visitor's first message.
  Counted from the existing write path, never from a second beacon.
- **The read**: the installation read `23-06` built returns the three counts for a window plus the
  resolved advice state, computed server-side so the console does not re-derive the rule. The advice
  is filtered by what the tenant's tier can reach — the tier is already on the `sites` row.
- `ago-console` `/settings/install`: the funnel and the one piece of advice its state implies.

## Out of scope

- Any per-visitor analytics, session recording, or funnel segmentation. Three numbers.
- Reporting a load from a page where the widget failed to bootstrap **before `mount` ran**. It cannot
  report what did not run, and pretending otherwise is the invented number `CLAUDE.md` forbids.
- Anything in the beacon body beyond the site key and the kind. It is a public unauthenticated
  endpoint on a third party's page; every field is a field an attacker can set.
- The reports at `/analytics*` — different audience, different honesty rules (`23-16`).

## Done when

- [x] Three counts appear for a site that has had traffic, and `0 / 0 / 0` for a brand-new one.
- [x] A page load by a returning visitor whose token needs no renewal still counts as a load, and
      still updates `last_seen_at` — the two failures the amendment names, asserted together.
- [x] Opening the panel twice in one session counts one open.
- [x] The beacon writes no row synchronously: a test asserts the request path issues no database
      write.
- [x] The beacon is refused from an origin the site does not allow, and rate-limited per IP with a
      `429` and a `Retry-After` (`5-20`'s existing shape).
- [x] Each zero state produces its own advice and none produces another's — asserted on the resolved
      state, not on the rendered words.
- [x] Advice naming a capability the tenant's tier does not include is never produced.
- [~] A pod restart mid-window loses at most the unflushed batch and never a whole day. **Half
      met.** "Never a whole day" is structural and proven; the shutdown flush is not covered, and the
      test written for it was dropped rather than merged. Carried out to `23-40`.
- [x] The widget's bundle-size budget still passes (`ago-widget`'s own gate).
- [x] `data-model.md` carries the table and says it is approximate; `api-design.md` carries the
      public endpoint.

## Open questions

None.

## Outcome

**Shipped 2026-09-06**, backend then widget, then deployed to the demo stand the same evening:
`ago-chat#203`, `ago-widget#58`, and `ago-chat#204` for the one Done-when found untested at landing.
Migration `20260906103639_Stage23AddSiteWidgetActivity` applied cleanly on the stand; smoke 45/45.

**The write path is the part worth remembering.** A mount beacon fires on every page load of every
tenant's site, so a row per beacon would have put the busiest table in the system on the visitor
request path. Beacons accumulate in memory per `(site, day, kind)` and a hosted service flushes
counter *increments* every ten seconds. Rule 8 does not bite — nothing reads these counters to decide
a write — and `docs/design/decisions.md` §3 already licenses the screen being approximate.

**Three things this item found that it did not go looking for:**

- **Dapper 2.1.79 cannot bind a `DateOnly` parameter at all**, while Npgsql maps it to `date` happily,
  so reads worked and writes threw. The handler is deliberately not the obvious
  `ToDateTime(TimeOnly.MinValue)` fix — turning a calendar day into an instant to satisfy a library
  invents a time of day. Where it registers took two wrong answers first, each refused by something
  concrete rather than by taste; the file records both.
- **The rate limiter shipped with nothing exercising its refusing branch.** Every test passed a
  limiter that always allows. Closed by `ago-chat#204`.
- **The flusher's shutdown flush cannot currently be proven.** The test for it passes alone and fails
  about half the time in the full integration project, and an instrumented run showed the row written
  with no swallowed exception. Dropped rather than merged, because a test that is right half the time
  is worse than the gap it covers. Everything learned is in `23-40`.

**One correction made after merge rather than before.** The widget PR's description said the beacon
used `navigator.sendBeacon` with a `keepalive` fallback. It does not — it is an ordinary `fetch`
whose promise is never awaited and whose rejection is swallowed. The description had been written from
this item's wording rather than from the code. Both the PR and `api-design.md` now say what is true,
including what the plain `fetch` gives up.
