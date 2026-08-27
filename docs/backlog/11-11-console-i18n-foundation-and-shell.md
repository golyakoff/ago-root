# The console's own chrome speaks the tenant's chosen language

- **Stage**: 11
- **Status**: ready
- **Depends on**: `11-10-widget-locale-from-console.md` (shipped) — `Site.WidgetLocale` already
  exists and is already the tenant-level setting this item reads; no new backend field. `13-07-one-
  login-several-tenants.md` (shipped) — the reason this item cannot pick one locale for an identity
  and be done: an operator can hold seats on sites with different locales at once.

## Why this exists, and why now

Found live, testing `4-06`'s presence fix with a real multi-tenant identity: the widget speaks
Russian on a `ru` site (`11-10`), but the console the operator answers from is English regardless -
"Conversations", "Sign out", every label, every error message. The author's own framing: language is
not a widget setting, it is a *tenant* setting, and an operator working a Russian tenant should see a
Russian console the same way a visitor sees a Russian widget. Confirmed with the author directly
(2026-08-27): the console's language follows the active site strictly, with no personal per-operator
override, and a page with no site at all (`/onboarding`, `/owner`) stays English - there is no tenant
whose language it could follow.

This is the first of a small family of items rather than one item covering every console screen -
`11-10`'s own six-sweep discipline does not shrink just because the surface changed from one hand-
rolled widget class to ~40 React files, and a slice with no working locale switch behind it is not a
slice `CLAUDE.md` calls done. This item is the foundation every later one needs: the string-table
mechanism itself, locale resolution wired to the active tenant, and the shell chrome every screen sits
inside (header, navigation labels, the tenancy switcher, sign-out, the public-demo notice). Later
items translate what sits inside that shell, screen by screen - named below, not built here.

## Scope

- **`buildTenantNavItems`/`OperatorShell`/`AppShell`/`ShellIdentity`/`TenancySwitcher` speak the
  active site's locale.** Every string these five files render - nav labels ("Conversations", "All
  conversations", "Widget appearance", "Offline auto-reply", "Platform sites"), "Sign out", the
  tenancy-switcher's own "Site" label, the public-demo notice's two variants (`AppShell.tsx`'s
  `PublicDemoNotice`), "Skip to content" - gets a Russian counterpart. Enumerate by reading the five
  files' own source, `11-10`'s own six-sweep model, not from this list.
- **A small string table, mirroring `ago-widget`'s own proven shape exactly** (`src/i18n/en.ts` /
  `src/i18n/ru.ts` in `ago-console`, a flat `ConsoleStrings` interface) - not a new pattern invented
  for this repository, the same one `11-10` already validated in production. Closed set of two
  locales, same reasoning `11-10` gave for not building locale-negotiation infrastructure nobody has
  asked for.
- **Locale resolution reads the active site's existing `WidgetLocale`, not a second network call.**
  `usePermissions()`'s `GET /api/v1/operators/me` response already returns `siteId` for the active
  site; this item adds `locale` to that same response (`Ago.Chat.Api`'s `MeEndpoints` /
  `ResolveOperatorIdentityHandler` - reads the resolved `Operator`'s `SiteId`, one more field off the
  `Site` row it already joins) so the console has the answer in hand at the same moment it has
  `siteId`, the identical "no second round trip" principle `11-10` used for the widget's own bootstrap.
- **A React context + `useStrings()` hook**, resolved once permissions resolve and re-resolved on
  every tenancy switch - which already triggers a full page reload (`TenancySwitcher`'s own doc
  comment), so "switch tenant, get its language" falls out of the existing reload rather than needing
  a second mechanism.
- **Before the locale is known** (the same brief window `11-03`'s widget bootstrap has), the shell
  renders its English default - the widget's own precedent, not a spinner or blank chrome.
- **A page with no active site** (`/onboarding`, `/owner`, `/signup`, `/callback`) **renders English,
  unconditionally** - confirmed with the author: there is no tenant whose language such a page could
  follow, and guessing from the operator's browser locale is exactly the negotiation scheme `11-10`
  already rejected for the widget, for the identical reason.

## Out of scope

- **Every other console screen's strings** - the operator workspace (queue, conversation thread,
  composer), the site-configuration screens (`/admin`, `/settings/widget`, `/settings/auto-reply`),
  and `OwnerSitesPage`. Each is a real, separately-sized item once this one's mechanism exists:
  `11-12` (operator workspace), `11-13` (site-configuration screens). `OwnerSitesPage` and
  `/onboarding`/`/signup` are not planned for translation at all, by the design decision above - they
  have no site to take a language from.
- **A personal, per-operator language preference independent of the active tenant.** Explicitly
  rejected by the author for now, the same deferral shape `11-10` used for a third locale: a real
  follow-on if ever asked for, not built speculatively.
- **Translating anything server-generated that is not a fixed UI string** - a conversation's own
  messages, an operator's typed notes, a site's own configured name. This item is chrome, the same
  boundary `11-10` drew for the widget.

## Done when

- [ ] A console session against a site with `WidgetLocale = ru` renders the shell (header, nav,
      identity, switcher, demo notice) in Russian - proven by a DOM test reading rendered text, the
      same bar `11-10`'s `locale.test.ts` set for the widget, not by asserting the config value alone.
- [ ] A console session against a site with no `WidgetLocale` set renders identically to before this
      item - a real regression test, not an assumption.
- [ ] Switching tenants via `TenancySwitcher` lands on the newly active site's own language after the
      reload it already performs.
- [ ] `/onboarding`, `/owner`, `/signup`, `/callback` render in English regardless of any signed-in
      identity's own tenancies.
- [ ] This item's own body lists every string it found and translated, `11-10`-style, so the
      enumeration can be checked rather than trusted.
- [ ] Verified live against at least one real browser if the managing session can arrange a deploy; if
      not, say so plainly, the same honesty `11-10` used for the half of its own verification it could
      not reach.

## Open questions

None left open by this item - the one real design call (personal override vs strict tenant-follows;
English-only for tenant-less pages) was put to the author directly and answered above, rather than
guessed past.
