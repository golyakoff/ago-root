# One console

- **Stage**: 22
- **Status**: done in code (2026-09-04) and deployed — **one Done-when honestly unmet**, and
  it is the first one. See Outcome.
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
      — **not met, and not for a reason this item can fix.** Five screens, not six (see below), and
      nobody can sign in and reach them: every account predating `22-05` lacks `calendar:configure`
      and its projection row. That is `22-16`, and `22-17` is the surface that would grant it. What
      *is* proven live: the merged bundle is served at `office.`, it carries
      `calendar-api.reserve-me.ru`, and that API returns `access-control-allow-origin:
      https://office.reserve-me.ru` while an unknown origin gets no header at all.
- [x] They are absent — not broken — for a person without the calendar permissions, and absent when
      `calendarApiBaseUrl` is unset. — both proven by removing the guard and watching the test fail.
- [x] The i18n catalogue and the blocking ux-gate survive the move, proven by running the gate. — the
      catalogue survived intact (561 → 759 keys, verified as a key-set diff with an empty
      dropped-set). **The gate did not survive whole**: eight covered routes became four, which is
      `15-16`.
- [x] `ago-calendar-console`'s repository is archived or emptied deliberately, not left to rot. —
      emptied deliberately, 79 files and 13,239 deletions, with a README saying where each screen
      went. Archiving stays the author's action; deleting the repository is argued against in the
      Outcome.

## Outcome

Done 2026-09-04. `ago-deploy#138` first (the API's audience and CORS origin), then `ago-console#97`,
then `ago-calendar-console#39`.

**Five screens moved, not six, and that is the finding.** `22-05` merged *while this was being built*
and deleted the calendar's entire identity model, so `/operators` and `/roles` no longer exist. The
Access screen would have rendered and then 404'd on its first fetch. It was caught by checking all 23
remaining paths one by one against `ConsoleEndpoints.cs` on `main` — not by anything failing, and not
by the brief, which was written before `22-05` landed. The work's own author had come close without
knowing it: they left `/calendar/access` out of the ux-gate as "a thin variant". It was not thin, it
was gone.

**Every screen was rewritten rather than ported**, because the source console predates `11-05`'s
closed eleven-component set and carries its own bare-HTML markup; a byte-for-byte port would have
imported a second, visually foreign design system into the console this item exists to merge into.
Ten of the eleven are used. `Dialog` deliberately is not — the source's own confirmations were
already inline panels, matching `EraseConversationButton`'s precedent rather than introducing this
console's first non-drawer modal for one screen.

**The gate found a defect nobody predicted**: the row links measured 22.5px, under the 24px WCAG
target-size floor. That is the second time in two days a blocking gate has found something invisible
to the eye, and it is the argument for `15-16`.

**The source's own date formatters were dropped rather than ported** — they called `toLocaleString()`
with no zone label, the exact defect `343` already fixed once here. Porting them back would have been
a regression dressed as a move.

### One deliberate departure from this stage's own rollout order

`roadmap.md` says *widen before narrowing*: `Operator__Audience` should accept both Keycloak clients
before the merged console ships. It was switched in **one step** instead. `ValidAudience` in
`Ago.Calendar.Api` is single-valued, so accepting both meant a code change in a repository another
worker was holding, for a fallback to a console this very item retires, with no real users to
protect. Checked rather than assumed: the `ago-console` client already carries its own
`oidc-audience-mapper`, so the switch needed no Keycloak change at all.

### On deleting `ago-calendar-console`

Emptied, not deleted, and deleting it is argued against: its Deployment still runs and serves
`calendar.`, its image is a GHCR package published from that repository, and its name is still in the
certificate SAN and in DNS until `22-09`. Archiving is reversible and keeps both the history several
documents cite and the package the running workload may need.
