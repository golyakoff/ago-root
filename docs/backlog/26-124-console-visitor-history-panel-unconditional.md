# 26-124 · [console] VisitorHistoryPanel must render unconditionally after `HasChannelIdentity` removal

- **Stage**: 26 — follow-up to `26-114` (which removed `VisitorHistoryResponse.HasChannelIdentity`).
- **Status**: ready — a required console fix; without it the returning-history panel regresses to never showing.
- **Found**: 2026-09-25, landing `26-114`: the backend widened visitor history to per-visitor-on-site and
  dropped the `HasChannelIdentity` wire field, but `ago-console`'s `VisitorHistoryPanel.tsx` still gates on
  `hasChannelIdentity === false` (via `types.ts` + tests). With the field now absent (undefined → falsy),
  the console would render **no** history panel at all — the opposite of the intended "now reachable for
  everyone" behaviour.

## Scope

- Remove the `hasChannelIdentity` gate in `ago-console`'s `VisitorHistoryPanel.tsx` — render the panel
  unconditionally (it now has data for every visitor, widget-only included).
- Drop `hasChannelIdentity` from the console's `types.ts` and any fixture/test that sets/asserts it; update
  those tests to the new unconditional behaviour.
- Run the full console gate incl. `npm run ux-gate` (Playwright) — a DTO-shape change like this is exactly
  what a stale fixture silently breaks.

## Done when

- [ ] The console renders the visitor-history panel for every visitor (no `hasChannelIdentity` gate); the
      field is gone from types/fixtures.
- [ ] typecheck / lint / test / ux-gate green.
