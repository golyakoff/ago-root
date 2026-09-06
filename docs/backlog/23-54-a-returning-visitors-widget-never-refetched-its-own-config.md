# a returning visitor's widget never refetched its own config, only the identity token did

- **Stage**: 23. **Renumbered from `23-54` at landing.** The rule it was filed under is the
  right one — a found defect takes the stage active when it was reported — but stage 25 is *what a
  lawyer, a regulator and a hosting contract need before the first real tenant*, and every one of
  the eleven defects reported on 2026-09-06/07 went to stage 23. A number in the wrong stage
  misleads anyone reading the roadmap for what a stage is about.
- **Status**: ready — a fix is drafted (see below), pending the managing session's own verification
  and merge
- **Depends on**: nothing. Fixes what `17-07` left, on top of `adr/0029`.
- **Decision**: `adr/0140` — a day, read from the token's own `nbf`/`iat`, no new endpoint or stored
  field.

## What was reported

The author, testing their own tenant's embed on their own site, changed the widget's colour and
launcher position in the console, saved, and reloaded the page - including a hard reload
(`Ctrl+F5`). Nothing changed. Only `F12 → Application → Clear site data` made the new colour and
position appear.

## What actually causes it, and how it was confirmed

`ago-widget/src/session.ts`'s `VisitorSessionManager.start()` reuses whatever session is already in
`localStorage` and makes **no network request at all** unless the stored identity token is inside its
own renewal window - which, per `RENEWAL_THRESHOLD_FRACTION = 1/3` and the 7-day lifetime in
`ago-chat/src/Ago.Chat.Api/Auth/JwtTokenService.cs`, only opens once the token is roughly **4 days 16
hours** old (`2/3` of 7 days). The tenant's own test browser already held a token from an earlier
visit, well inside that "nowhere near renewal" majority of its life, so both an ordinary reload and
`Ctrl+F5` (which bypasses the HTTP cache but never touches `localStorage`) hit this exact path and
made zero requests. `Clear site data` removes the stored token outright, forcing a fresh mint
(`POST /api/v1/visitor-sessions`), which is why that step alone fixed it.

Confirmed with a fails-before test in `ago-widget/src/session.test.ts`: at `T0 + 2 * DAY_MS` on a
token minted at `T0` (nowhere near the ~4.67-day identity renewal window), `start()` made zero
requests and the cached `widgetPrimaryColorHex`/`widgetPosition` stayed whatever they were at mint
time - reproducing the report exactly. Confirmed the other direction with `git stash` isolating the
test changes from the code changes and re-running: 1 of 4 new tests failed against the pre-fix code,
0 failed after.

**One defect, not two.** Colour, position, locale, and the processing-notice text/URL all travel
through the identical `VisitorSession`/`WidgetStorage` path and are refreshed by the identical
`renew()`/`mint()` calls, so nothing here is colour-specific or position-specific.

**The real number, before this fix**: a stale value could persist for up to `2/3` of the identity
token's 7-day lifetime (~4 days 16 hours) after the change, *and* the visitor had to actually reload
during the remaining `1/3` window for the fix to land at all - if they did not reload again before the
token's outright expiry at day 7, the very next visit after that forces a full remint (a different
`VisitorId`), which also picks up fresh config, but drops the resumed conversation with it. Worst
case, unbounded: a visitor who never reloads again simply never sees the change.

`ago-console`'s own `/settings/widget` screen told the operator making the change "changes here take
effect the next time a visitor's page loads the widget" (`widgetDescription`, `en.ts`) - a promise the
implementation did not keep for any returning visitor. That mismatch between a stated promise and the
actual mechanism is what makes this a defect rather than an accepted, `adr/0029`-named limitation:
`adr/0029` named "an already-open tab won't update without a reload" as the accepted gap; it did not
say, and did not intend, that a **closed and reopened** tab would stay stale too.

## The fix (drafted, in `ago-widget` + `ago-console`)

`ago-widget/src/session.ts`: `start()` now also renews when `CONFIG_REFRESH_INTERVAL_MS` (a day) has
passed since the stored token was last minted or renewed (`isConfigStale`, reading the existing
`nbf`/`iat` claim - no new stored field, no new endpoint, reuses `POST
/api/v1/visitor-sessions/renew`). `ago-console`'s `/settings/widget` copy and the tenant-facing
`/settings/device-storage` disclosure (`en.ts`/`ru.ts`) now state the true number instead of "next
page load." Full reasoning and the alternatives declined (refetch every load; leave the identity
window as the only mechanism; a separate stored timestamp) are in `adr/0140`.

**Kept narrow, deliberately.** This does not add a live-push channel for an already-open tab -
`adr/0029`'s own named limitation there stands untouched. It also does not refetch on every page
load: the day-long budget is a bounded, sensible cache expiry, not "always current."

## Scope

- `ago-widget/src/session.ts`, `src/session.test.ts`, `src/ui/sessionRenewal.test.ts`,
  `src/storage.ts` (doc comments and `WIDGET_STORAGE_DISCLOSURE` lifetime text only - no key added).
- `ago-console/src/i18n/en.ts`, `src/i18n/ru.ts` (`widgetDescription`,
  `deviceStorageWidgetColorLifetime`) - copy only, no component change.
- `adr/0140`. **Needs its own row added to `docs/adr/README.md`** - out of scope for whoever drafted
  this (that file was off limits to them); do not let this become a second `24-18`.

## Out of scope

- **A live-push channel so an already-open tab updates without a reload.** `adr/0029` already declined
  this for cost reasons unrelated to this defect; nothing here changes that answer.
- **Changing the identity token's own 7-day lifetime or its `1/3` renewal fraction.** Untouched -
  this is a second, independent freshness check, not a change to `17-07`'s own reasoning.
