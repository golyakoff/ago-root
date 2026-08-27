# The widget speaks the tenant's chosen language

- **Stage**: 11
- **Status**: done
- **Depends on**: `11-01-widget-config-data-model-and-api.md` (shipped) — the additive-field precedent
  this item follows exactly, not a new mechanism. `14-04-offline-auto-reply.md` (shipped) — the most
  recent example of the same shape (a new `Site` setting, read cache-aside through `WidgetConfig`,
  exposed in the console) and the place its own real bug (a half-evicted cache key) was found; read it
  before repeating it.

## Why this exists, and why now

`golyakoff/ago-widget#22` split the two public demo pages by language — `demo-shop1` in Russian,
`demo-shop2` in English — and named the seam it could not close: the page wrapper is translated, but
the chat bubble the wrapper embeds is the same compiled widget bundle for both, and every string in it
is hardcoded English. A visitor reading a Russian page opens an English chat. This item closes that
seam by making the widget's own language a real, per-tenant setting rather than a build-time constant.

## Scope

- **`Site` gains a `WidgetLocale` setting**, the same additive shape `OfflineAutoReplySettings`
  established: a value object, a column with a default, a domain event on change mapped to the
  existing `SiteSettingsChanged`/cache-invalidation path (`caching.md`; check whether it reuses
  `SiteOfflineAutoReplyUpdated`'s exact mapper shape or needs its own — they should look the same).
  **A closed set of two locales to start: `en` (default) and `ru`.** Not an open list and not a
  locale-negotiation scheme — this project has exactly two demo tenants needing exactly two
  languages today, and a third locale is a name and a string file away whenever a real one is needed.
  Inventing infrastructure for locales nobody has asked for is the premature generalisation
  `CLAUDE.md` warns against.
- **Every user-facing string in `ago-widget` currently in English gets a Russian counterpart.**
  Enumerate them by reading the bundle's source, not from memory or by guessing which ones matter —
  `17-03`'s six-sweep discipline is the right model: grep every literal string rendered into the DOM,
  not just the obvious ones (composer placeholder, send control, connection/reconnection states,
  attachment upload states, the `14-04` "Automatic reply" label, any default launcher text, every
  error message a visitor can see). List what was found in this item's own write-up when done, so the
  list can be checked rather than trusted.
- **A small string table, not an i18n framework.** Plain per-locale maps (e.g. `src/i18n/en.ts` /
  `src/i18n/ru.ts`), selected once at boot from the `WidgetConfig` response `11-03`'s bootstrap already
  fetches — no second network call, no client-side locale negotiation. An unrecognised or missing
  locale falls back to `en` silently; a widget must never fail to render because of a bad locale value.
- **Console**: one new control in `11-02`'s existing widget-config screen — a language selector,
  gated by `site:configure` the same way every other appearance setting already is. No new permission.
- **Once this ships, the managing session sets `demo-shop1`'s tenant to `ru` and `demo-shop2`'s to
  `en`** — a config change on the live deployment, not part of this item's own Done-when, the same way
  `adr/0058`'s `DemoTenant__Enabled` flag was flipped separately from the code that built it. Stated
  here so it is not forgotten once the feature exists.

## Out of scope

- **Locale-sensitive number/date formatting.** `Intl` already renders those correctly from the
  browser's own locale; this item is about translated strings, not formatting, and the two are
  independent concerns.
- **Right-to-left layout.** Not needed by either locale in scope; the string table's shape should not
  assume it either way, but building RTL support now would be solving a problem this item does not have.
- **A locale picker visible to the *visitor*.** This is the shop owner's choice about their own
  widget, made once in the console — not a per-visitor toggle, and not detected from the visitor's
  own browser locale (a shop in one country serving customers in another gets to say which language
  its support chat speaks).
- **Translating tenant-authored content** — `14-04`'s auto-reply scripts, future canned responses.
  Those are always exactly what the tenant typed; this item never machine-translates anything a human
  wrote.
- **A third locale.** Named as the obvious next step once a real tenant needs one, not built
  speculatively — the same deferral shape `14-04` used for its own LLM-backed variant.

## Done when

- [x] A widget booted against a site with `WidgetLocale = ru` renders every enumerated string in
      Russian — proven by a DOM test reading rendered text, not by asserting the config value alone.
      `ago-widget/src/ui/locale.test.ts` mounts the real `ChatWidget`, stubs the visitor-session mint
      with `widgetLocale: "Ru"` in the response body, opens the panel and asserts `.textContent`/
      `.placeholder`/`aria-label` on the toggle, panel, title, close button, input, send button,
      attach button, the booking button in both its states, the connection status, and the
      restarted-session note — not the config value in isolation. `booking/flow.test.ts` covers the
      booking flow's own step bodies and action labels the same way, and `attachments.test.ts` covers
      the courtesy-rejection frame text.
- [x] A widget booted against a site with no `WidgetLocale` set (every existing tenant today) renders
      identically to before this item — `locale.test.ts`'s sibling `describe` block, same assertions,
      English side, with the mocked response omitting `widgetLocale` entirely (not merely set to
      `"En"`) so it is a real regression test for "the field does not exist yet" rather than an
      assumption. `ago-widget/src/ui/booking.test.ts`'s six pre-existing tests (unchanged by this
      item) serve as a second, independent regression proof: they already assert English text with no
      `widgetLocale` in their own stubbed responses and kept passing throughout.
- [x] The console control changes live behaviour without a rebuild, matching `11-*`'s own bar —
      `ago-chat/tests/Ago.Chat.Integration.Tests/WidgetConfigCacheInvalidationEndToEndTests.cs`
      extended (not duplicated) to write a locale alongside color/position through the real outbox →
      RabbitMQ → `SiteCacheInvalidationConsumer` → `Ago.Platform.Caching.Redis.CacheInvalidationConsumer`
      → Redis chain, and poll the cache-aside handshake read until it sees the new value — the same
      real-infrastructure bar `14-04`'s own end-to-end test set, not a mocked cache.
- [x] This item's own body lists every string it found and translated — see "The string enumeration"
      below.
- [ ] Verified live against at least one real browser — **not done**. I have no deploy access in this
      worktree; the managing session will need to arrange a real deploy and browser check once the
      four PRs this item produced have landed, the same honesty `14-04` and `18-05` both used for the
      parts they could not reach.

## What was decided here that the item did not name

- **`WidgetLocale` is a flat sibling field, not nested under `appearance`/`WidgetConfig`** — the
  established `11-01`/`14-04` precedent applied once more, not a new design call. This item's own
  "Open questions" offered an ADR (`0068`) if the answer were non-obvious; it was not, so the
  ceremony is skipped here exactly the way `18-05` judged its own equivalent question did not need
  one. Concretely: `Ago.Chat.Domain.Site` gets a private `_locale` field, a computed `Locale`
  property, and its own `Site.UpdateLocale(Locale, DateTimeOffset)` method raising a new
  `SiteLocaleUpdated` domain event — a sibling to `SiteWidgetConfigUpdated`, not a third field folded
  into `WidgetConfig` itself, because locale is not widget *appearance* and a future consumer that
  cares about one and not the other needs to tell them apart at the domain level.
- **One HTTP call still writes two domain events.** `UpdateWidgetConfigHandler` is the one console
  write both `11-01`'s Position/color fields and this item's locale field go through — one PUT, one
  `UpdateWidgetConfigDto`/`WidgetConfigDto` round trip — but internally it calls both
  `Site.UpdateWidgetConfig` and `Site.UpdateLocale`, so a single save now enqueues **two**
  `SiteSettingsChanged` envelopes instead of one. `SiteCacheInvalidationConsumer` already treats a
  repeat invalidation of the same key as free (its own remarks, since `14-04`), so this costs nothing
  beyond the two envelopes; the pre-existing "enqueues exactly one envelope" test was updated to
  assert two, not silently left describing behaviour the code no longer has.
- **`SiteLocaleUpdatedMapper` is a third mapper converging on the same `SiteSettingsChanged`
  contract**, following `SiteOfflineAutoReplyUpdatedMapper`'s own precedent for why convergence
  happens at the outbox boundary and not earlier.
- **The CSS pseudo-element label needed its own mechanism.** `14-04`'s "Automatic reply" label is a
  CSS `content:` string on a `::before` pseudo-element, not a DOM text node — a locale string-table
  swap cannot reach it the way every other string in this item could. Solved the same way
  `--ago-accent` already threads the site's color through: a CSS custom property
  (`--ago-auto-reply-label`), set via `host.style.setProperty(...)` at the same point `applyStrings`
  resolves everything else, with the CSS changed to
  `content: var(--ago-auto-reply-label, "Automatic reply")` — the fallback value is what a visitor
  sees in the brief window before locale resolves, or if it never does, matching the same "widget's
  own built-in default" precedent `11-03` established for color/position.
- **A real ordering bug found by writing the DOM test, not by inspection.** The first draft of
  `bootstrapSession` rendered the `17-07` "your previous chat has expired" note *before* calling
  `applyStrings`, on the reasoning that everything built before locale resolves should read as the
  widget's built-in English default. That reasoning is right for text built in the constructor
  (synchronous, before any network round trip can complete) and wrong here: by the time
  `bootstrapSession` runs at all, `session.widgetLocale` is already in hand, so there is no reason to
  render this one note in the pre-resolution default. `locale.test.ts`'s restarted-session test
  caught it rendering in English against a `ru` site; the fix reorders `applyStrings` before the note.
- **`ago-widget/src/booking/steps.ts`'s "Reply with a number." was left untranslated, and confirmed
  unreachable rather than assumed so.** `renderStepAsText` (the only place that string appears) has no
  caller anywhere in `src/` outside its own unit tests (`flow.test.ts`, `steps.test.ts`) — the
  in-browser path is entirely `booking/panel.ts`'s button-based renderer. Re-grepped at the end of
  this item, not just taken from the brief, to confirm no call site had been added or missed.

## The string enumeration

Every string below was found by reading `ago-widget`'s own source (not from memory), and translated
into `ago-widget/src/i18n/ru.ts` against the frame in `en.ts`. Numeric/data interpolations (file
sizes, durations, calendar/service/worker names, server-provided problem-detail text) are left
untranslated by design — see "Out of scope" above and the Done-when's own DOM tests, which assert the
translated frame *and* the untouched data in the same string.

- **`src/ui/widget.ts`**: launcher open/close aria-labels, the panel's own aria-label and header title,
  the close button, the booking button's two states (label + aria-label), the connecting/reconnecting/
  disconnected status ternary, the composer's input aria-label and placeholder, the send button, the
  attach button, the `17-07` restarted-session note, the connect()-catch-all, the `17-07`
  session-expired terminal status, the three `dispatchSend` failure notes (unknown outcome, not
  connected, generic failure), the upload-progress word (`"Uploading…"`, with the percentage number
  left interpolated), the upload-failure note, the download-attachment link text, the image `alt` text,
  the attachment-unavailable note, and both fixed demo notices (`8-06`/`8-11`).
- **`src/attachments.ts`**: the file-type-rejection frame (including the "unknown type" fallback used
  when the browser reports none) and the size-rejection frame, both keeping their numeric/data
  interpolations untouched.
- **`src/ui/styles.ts`**: the `14-04` "Automatic reply" pseudo-element label — see "What was decided
  here" above for why it needed a CSS custom property rather than a string-table lookup.
- **`src/booking/panel.ts`**: the free-text answer's aria-label, the "Continue" submit button, the
  loading-times step.
- **`src/booking/flow.ts`**: every step body and retry message the flow itself produces — the
  nothing-to-book/which-calendar/not-an-option (four call sites, same string)/phone-prompt-tail/
  phone-required/name-prompt/booking-finished/what-to-book/minutes-unit/nobody-available/anyone/
  who-to-see/no-free-times/when-to-come/you-are-booked-prefix/still-free sentences, with worker/service/
  calendar names and the `Intl`-formatted slot time left as data.
- **`src/booking/calendarClient.ts`**: the three fixed failure messages (`booking not available`,
  `slot just taken`, `too many attempts`) — threaded through as an explicit, localized message on each
  `throw`, rather than left to the error classes' own English-only default constructor parameters
  (which still exist, for callers with no `WidgetStrings` in hand — this repository's own tests, and
  now stated as such in the classes' own doc comments).
- **`src/booking/steps.ts`**: `"Reply with a number."` deliberately left untranslated — confirmed
  unreachable from the browser, see "What was decided here" above.
- **Explicitly not touched**: `src/demo/boot.ts`/`src/demo/panel.ts` and either `public-demo*/index.html`
  — a separate bundle serving only this repository's own demo pages, out of this item's scope per the
  managing session's own brief.

## Not verified

- **A real browser against a deployed cluster.** See the unchecked Done-when box above — this
  worktree has no deploy access. Every claim in this file rests on `dotnet test`/`vitest run` against
  real infrastructure (Testcontainers: Postgres, RabbitMQ, Redis) for the backend, and jsdom DOM
  assertions for the widget/console, not on someone watching a real page.
- **Browser-locale/tenant-locale mismatch for booking slot times.** `booking/flow.ts`'s
  `defaultSlotLabel` formats a slot's date/time via `Intl`/`toLocaleString` using the visitor's own
  browser locale (an `undefined` locale argument), independent of the tenant's `WidgetLocale`. A
  tenant set to `ru` with a visitor whose browser is `en-US` sees English month/weekday names inside an
  otherwise-Russian booking flow. This is a known, named gap, not a defect this item is required to
  fix — the backlog item's own Out-of-scope section already excludes locale-sensitive number/date
  formatting — but it was worth surfacing rather than leaving undiscovered.
- **Cost of the second outbox row.** `UpdateWidgetConfigHandler` now writes two `SiteSettingsChanged`
  outbox rows per console save instead of one. This is an operator-triggered, low-frequency write (an
  operator saving their own widget settings), not a per-visitor-message path the way `14-04`'s own
  consumer hop was, so no load-test number is attached here — Stage 7's load test is where one would
  belong if this path ever needed one.

## Open questions

**Where exactly the locale value lives relative to `WidgetConfig`'s existing shape** — resolved during
implementation, recorded in "What was decided here" above rather than left open: a flat sibling field
on `Site`, the established `11-01`/`14-04` shape, not non-obvious enough to justify the optional
`adr/0068` this item offered.
