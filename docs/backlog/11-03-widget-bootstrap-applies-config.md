# Widget bootstrap: apply per-site configuration

- **Stage**: 11
- **Status**: done — implemented, then verified live end to end through `11-01`'s real running API.
  The build pass could not reach a live stack at the time it ran (ports busy with another session's
  work) and said so plainly rather than asserting; the managing session then ran the real round trip
  afterwards. See Done-when for what was actually observed.
- **Depends on**: `11-01-widget-config-data-model-and-api.md` (the handshake response field this item
  reads) — not on `11-02`, since this item can be verified against `11-01`'s real API directly (a curl
  `PUT`, matching how `5-01`'s CORS mechanism was verifiable before any console UI existed to drive it)

## Goal

The widget bootstrap in `ago-widget` reads the primary color and launcher position `11-01` added to
`POST /api/v1/visitor-sessions`'s response and applies them to what it renders — no rebuild, no
redeploy, no per-site bundle. This is the last piece of Stage 11's own done-when bar: it is what makes
a console-side change in `11-02` actually visible on a real embedded page.

## Context to read first

**`.claude/skills/embeddable-widget/SKILL.md` in full** — the same constraint list `5-09`/`5-10` were
built against: Shadow DOM isolation, bundle-size ceiling enforced in CI, "every entry point wrapped so
an internal failure degrades to no-widget, never a broken host page." This item's own failure mode
specifically: a missing, malformed, or out-of-range config value from the handshake response must fall
back to the widget's own built-in default silently, never throw. `docs/backlog/5-09-widget-bootstrap-and-messaging.md` —
the exact bootstrap sequence this item extends (`data-site` → `POST /api/v1/visitor-sessions` → mount
Shadow DOM root → render), and the current bundle-size number (18.4 KB gzipped at `5-09`, 19.9 KB after
`5-10`, against a 45 KB budget) this item must re-measure against. `11-01`'s exact response field
shapes and its ADR's stated limitation (config is read once, at bootstrap; an already-open widget does
not update live) — this item is where that limitation becomes a real, observable fact about the shipped
bundle, not just written down.

## Scope

- Bootstrap reads the new field(s) from the handshake response already fetched at `data-site` time (no
  second network call — the response already carries this by the time `11-01` ships). **Real gap found
  while implementing, fixed in scope**: `5-09` actually made that fetch (`getOrCreateVisitorSession`)
  lazy, on first widget open, not eager at mount time - fine for the real-time connection itself
  ("nothing heavy before first interaction"), but wrong for position specifically, since position
  decides where the *closed* launcher renders, before any interaction could ever trigger a lazy fetch.
  Fixed by splitting the two: `ui/widget.ts`'s constructor now kicks off `bootstrapSession()` (identity +
  config only) eagerly, storing the promise; `connect()` (still built lazily, on first open) awaits that
  same promise instead of re-requesting it, so the actual SignalR connection stays exactly as lazy as
  `5-09` built it. `session.ts`/`storage.ts`'s own doc comments have the full reasoning, including the
  real, named limitation this surfaces: a *returning* visitor's cached config is not refreshed on a
  fresh page load either, since re-requesting through this same endpoint would mint a second visitor
  identity to get it - fixing that for real needs a session endpoint that can return current config
  without minting a new visitor, a `ago-chat` API change out of this item's own scope.
- **Position**: `ui/widget.ts`'s `container` (`.ago-root`, a `position: fixed` div appended to
  `document.body` via `mount()`) gets an `ago-position-left` class toggled by `parseWidgetPosition`'s
  result; `ui/styles.ts` defines the mirrored `right`/`left` placement for both the launcher and the
  panel under that class. An unrecognised or missing value falls back to the widget's own existing
  default placement (`bottom-right`), not an error.
- **Primary color**: applied as a CSS custom property (`--ago-accent`) on the **host element** (the
  outer, light-DOM div `createShadowHost` returns - not the `ShadowRoot` object itself, which has no
  `.style`), inherited into the shadow tree despite `:host { all: initial; }` (custom properties are
  excluded from the `all` shorthand). `ui/styles.ts`'s stylesheet declares `--ago-accent: #2f6fed;` as
  the built-in default inside `:host {}` and every place that used to hardcode `#2f6fed` (`.ago-toggle`,
  `.ago-header`, `.ago-message--visitor`, `.ago-send`, the shared `:focus-visible` outline) now reads
  `var(--ago-accent)` instead. A missing/malformed value falls back to the widget's own existing
  built-in color by simply never calling `.setProperty` (`ui/appearance.ts`'s `parseWidgetColor` returns
  `undefined` for exactly this reason), matching the "courtesy validation, never trust the wire value
  blindly" posture `attachments.ts`'s own `courtesyValidate` already takes.
- Re-measured: **20.5 KB gzipped** (75.7 KB raw), up from `5-10`'s 19.9 KB — `ago-widget/README.md`'s own
  "Bundle size" section states the new number and date.

## Out of scope

- Any field beyond primary color and position (`11-01`'s own scope) — if `11-04` resolves to more
  fields later, this item's own follow-up work grows to match, not guessed at here.
- A live-update channel that changes an already-open widget's appearance without a page reload — `11-01`'s
  ADR already states why this item does not build one; a visitor who has the widget open across a config
  change sees the old appearance until their next page load, which re-runs the bootstrap handshake fresh.
- Any change to the connection/reconnect/messaging protocol layer `5-09` built — this item only changes
  what bootstrap does with one more field in a response it already fetches.

## Done when

- [x] Manually verified against the local cluster, the same hostile demo host page `5-09`/`5-10` used:
      a site's widget config changed through `11-01`'s real API, and a **fresh page load** of the demo
      host page shows the widget in the new position with the new accent colour — the field genuinely
      reaching rendered output, not just round-tripping through a DTO. Actually observed, twice, with
      two different values, against `dotnet run` Api + Worker and the compose stack: with the site set
      to `#12B886` / `BottomLeft`, a fresh load rendered `--ago-accent: #12B886`, class
      `ago-root ago-position-left`, computed `.ago-toggle` background `rgb(18, 184, 134)`, and
      `left: 20px` / `right: -76px`; after changing it to `#E8590C` / `BottomRight` **through the
      `11-02` console UI**, a fresh load rendered `--ago-accent: #E8590C`, class `ago-root` (no
      position class), computed background `rgb(232, 89, 12)`, and `right: 20px` / `left: -76px`.
      The whole chain was exercised, not just the last hop: console → `PUT` → `sites` row → domain
      event → outbox → Worker → broker → `CacheInvalidationConsumer` → Redis key `site-config:demo_site`
      dropped → next `POST /api/v1/visitor-sessions` returned the new values → widget applied them.
- [x] **The caching limitation this item documents is real, and was observed rather than assumed.**
      Two separate effects, both confirmed live and both already stated in `storage.ts`'s own
      `VisitorSession` doc comment and `session.ts`'s: (1) a **returning** visitor (existing
      `localStorage` session) still rendered the *old* `#12B886` / bottom-left after the config had
      already changed to `#E8590C` / bottom-right in the database — because `getOrCreateVisitorSession`
      short-circuits on the stored session and never re-requests; clearing `localStorage` was what made
      the new values appear. (2) Separately, while `Ago.Chat.Worker` was not running, a *fresh* visitor
      also kept getting the old values — the two `SiteSettingsChanged` outbox rows sat unpublished
      (`published_at IS NULL`) so `CacheInvalidationConsumer` never ran and Redis kept serving the stale
      `site-config:demo_site` entry. Starting the Worker published both rows, the Redis key disappeared,
      and the very next handshake returned the new config. Neither is a defect in this item — the first
      is its own documented trade-off, the second is `11-01`/`3-04`'s event-driven invalidation working
      exactly as designed — but both are worth having seen rather than reasoned about.
- [x] A site with no widget config set (the pre-`11-01` default, or a fresh site that never called
      `PUT .../widget-config`) renders with the widget's original built-in appearance — no visible
      regression for every site that predates this item. Proven at the unit level:
      `parseWidgetColor(null)` returns `undefined` and `parseWidgetPosition(null)` returns
      `"bottom-right"` (`ui/appearance.test.ts`), the widget's own existing defaults, and confirmed live
      in the isolated-harness run below (a failed handshake never resolves `session.widgetPrimaryColorHex`/
      `widgetPosition` at all, and the launcher rendered in the default bottom-right position with the
      default `#2f6fed` accent regardless).
- [x] A deliberately malformed value from the handshake response (simulated, e.g. via a local proxy or a
      unit test against the parsing function directly) falls back to the built-in default and never
      throws an uncaught exception on the host page — proven the same
      `window.onerror`/`unhandledrejection`-listener way `5-09`'s own internal-error done-when item was
      proven. Done twice over: `ui/appearance.test.ts` unit-tests `parseWidgetColor`/`parseWidgetPosition`
      directly against malformed/empty/missing values and a CSS-injection attempt (`"red; background:
      url(javascript:alert(1))"`), all falling back cleanly; and, live, in an isolated browser harness
      (a throwaway static page on `localhost:8099`, `dist/ago-chat.js` pointed at an unreachable
      `data-api`) with real `window.addEventListener("unhandledrejection", ...)`/`("error", ...)`
      listeners installed *before* the widget script ran - the eager `POST /api/v1/visitor-sessions`
      call failed outright, the widget's own `logWidgetError` logged it to the console
      (`[AGO Chat widget] TypeError: Failed to fetch`), and both listener arrays stayed empty
      afterward: `guardAsync` (`errors.ts`, already-existing helper, `5-09`) genuinely prevents the
      eagerly-fired `bootstrapSession()` promise from ever becoming an unhandled rejection on the host
      page, and the launcher itself still rendered (Shadow DOM host mounted, toggle button present)
      despite the total handshake failure.
- [x] Bundle size re-measured and stated as a real number in `ago-widget/README.md`; CI's existing
      budget check still passes. **20.5 KB gzipped** (75.7 KB raw), up from `5-10`'s 19.9 KB - measured
      2026-08-24 via `AGO_API_BASE_URL=http://localhost:5009 npm run build`, `build.mjs`'s own 45 KB
      gzipped budget check passed (real headroom, not close to the ceiling).
- [x] `.claude/skills/embeddable-widget/SKILL.md`'s Bootstrap section — currently describing this as
      already true ("The handshake returns the site's widget settings... ") — gets a "Shipped in
      `11-03`" note now that the sentence is actually accurate end to end, matching how every other
      "documented, not yet wired" note in this project gets closed out once real. Done in this same
      change (a separate, small `ago-root` commit, since the skill file lives there, not in
      `ago-widget`).

## Open questions

None for the scope shipped here — the mechanism (read an already-fetched response field, apply as a CSS
custom property and a placement class, fall back silently on anything malformed) follows directly from
`11-01`'s contract and the widget skill's own existing error-handling rules. `11-04`'s open question does
not block this item; it only grows this item's own future scope if it resolves toward more fields.
