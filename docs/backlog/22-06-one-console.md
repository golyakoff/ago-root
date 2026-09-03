# One console

- **Stage**: 22
- **Status**: ready
- **Depends on**: `22-05`, `22-10` (the console's hostname settles first, so this merges into a name that is not moving)

## What changes

The calendar's six screens — Queue, Setup, Workers, Availability, Contacts, Access — move into
`ago-console`, gated by the calendar permissions. A chat operator granted `calendar:configure`
simply sees more menu. `ago-calendar-console` retires.

## The pattern already ships, and that is the point

`19-03` did this for `ago-faq` on 2026-08-31: `FaqModulePage` lives in `ago-console`, gates on
`usePermissions()`, and reads its own backend through `config.faqApiBaseUrl` — declared in
`config.ts` as *"a different backend than `apiBaseUrl` above"*, and **optional**, so the panel is
absent rather than broken when it is not configured.

So this workstream follows `FaqModulePage`; it does not invent a mechanism. `calendarApiBaseUrl`
joins `config.ts` the same way, and `calendar-api.reserve-me.ru` **stays** — the console merges, the
API does not.

## What is genuinely large about it anyway

An entire SPA's worth of screens changes repository, build, i18n catalogue and ux-gate. `11-15` gave
`ago-calendar-console` its own language files and `15-12` made its gate blocking; both have to land
in `ago-console`'s equivalents rather than be lost. The six screens carry their own tests.

## The hostname and CORS work this forces

Named here because it is easy to discover late:

- **`Operator__ConsoleOrigins`** on `ago-calendar-api` currently lists `https://calendar.reserve-me.ru`.
  It becomes `https://office.reserve-me.ru` (`22-10`). Without this the merged console is refused by CORS, and the
  failure looks like a broken screen rather than a configuration line — `20-20` already lost a
  verification to exactly this class of mistake.
- **`Operator__Audience`** is `ago-calendar-console`. The merged console presents a token minted for
  the `ago-console` client, so the audience changes. **Accept both during the transition**, then
  narrow — a single-value switch means the old console breaks the instant the new one is deployed,
  with no overlap to verify in.

## Done when

- [ ] The six screens work at `office.reserve-me.ru`, signed in with the `ago-console` client's token.
- [ ] They are absent — not broken — for a person without the calendar permissions, and absent when
      `calendarApiBaseUrl` is unset. `19-03`'s `permissionGating` tests are the shape to copy.
- [ ] The i18n catalogue and the blocking ux-gate survive the move, proven by running the gate.
- [ ] `ago-calendar-console`'s repository is archived or emptied deliberately, not left to rot.
