# The widget speaks the tenant's chosen language

- **Stage**: 11
- **Status**: ready
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

- [ ] A widget booted against a site with `WidgetLocale = ru` renders every enumerated string in
      Russian — proven by a DOM test reading rendered text, not by asserting the config value alone.
- [ ] A widget booted against a site with no `WidgetLocale` set (every existing tenant today) renders
      identically to before this item — a real regression test, not an assumption, since every current
      tenant must see zero change.
- [ ] The console control changes live behaviour without a rebuild, matching `11-*`'s own bar — proven
      the same way `14-04`'s toggle was: through the real outbox → cache-invalidation chain, not a
      mocked cache.
- [ ] This item's own body lists every string it found and translated, so the enumeration can be
      checked against what actually shipped rather than trusted.
- [ ] Verified live against at least one real browser if the managing session can arrange a deploy;
      if not, say so plainly rather than claiming it, the same honesty `14-04` and `18-05` both used
      for the parts they could not reach.

## Open questions

**Where exactly the locale value lives relative to `WidgetConfig`'s existing shape** — a new top-level
field beside `appearance`, or nested under it — is a real design call this item should make and record,
not guess past. If the answer is non-obvious, it is worth an ADR (`0068` is free); if it is genuinely
just "one more field, same shape as the last one," say so and skip the ceremony, the way `18-05`
correctly judged it did not need one.
