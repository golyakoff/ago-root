# 26-17 · Settings: theme, active site, О приложении, and sign-out

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21. Three other items in this wave lean on this screen and none of them owns it:
  `26-09` stamps a commit into the APK that nothing displays, `26-12` implements a sign-out with no
  control, and `26-06` needs that control to exist before it can hang device revocation off it.
- **Verified**: 2026-09-21 — `scope-inventory.md` §10 records `/appearance` as folded into an
  app-level Settings screen rather than standing alone; §11 records the active-site switcher as a
  screen with no console equivalent; `navigation.md` records that the sign-in screen deliberately
  names no deployment and that the build variant's name lives here instead.
- **Depends on**: `26-16` (the Ещё list this hangs from), `26-12` (the session and the sign-out
  mechanism).

## What this item is

The Settings screen and the four rows it carries in this wave. One promise: **an operator can see and
change what the app itself does.**

## Scope

- **The Settings screen**, reached from the foot of Ещё.
- **Тема** — the three-state system / light / dark choice `/appearance` already is, folded in rather
  than given its own destination (`scope-inventory.md` §10), sitting beside whatever `26-10` decided
  about Android 12+ dynamic colour.
- **Текущий сайт** — the active-site switcher. `GET /api/v1/me/tenancies` feeds it; switching
  re-points the single source of truth `26-12`'s header plugin reads and the hub's own query-string
  parameter, then returns to Диалоги. It exists because one identity can hold operator seats at
  several sites (`adr/0068`), and `26-12` only ever *picks* one at sign-in.
- **О приложении** — the build variant's name and the commit `26-09` stamped into `versionName`. This
  is deliberately where the deployment is named, because the sign-in screen deliberately is not: the
  debugging need is real and it is served better where a tester looks and an operator does not
  (`navigation.md`).
- **Выход** — the control for the sign-out `26-12` implements. Once `26-06` lands it also revokes this
  device's push registration, and the ordering (revoke while the token is still valid, *then* discard
  it) belongs to that item.

## Out of scope

- **Уведомления** — `26-19`. It needs push to exist first, and a settings screen whose switches
  control nothing is the dishonesty `26-19` exists to remove.
- **Удалить аккаунт.** It belongs at the foot of Settings and nowhere else (`scope-inventory.md` §9 —
  a deliberate friction, and the honest alternative to excluding a capability the operator legitimately
  holds), but it destroys a whole tenant irreversibly and it is not this wave's to build.
- Every other Ещё row — channels, automation, administration.
- Presence and the Away control.

## Done when

- [ ] All three theme states apply immediately and survive a process restart.
- [ ] An operator with seats at **two** sites switches between them and the conversation list changes
      accordingly — proven against two real tenancies, since a switcher tested with one tenancy tests
      nothing.
- [ ] Switching the active site re-points **both** the REST header and the hub connection, not just
      the header.
- [ ] О приложении names the exact commit the installed APK was built from — checked against the
      release `26-09` published, not against a local build where the value is easy to fake.
- [ ] Sign-out returns to the launch screen and leaves no token behind — proven by inspecting the
      encrypted store afterwards, not by the UI having navigated away.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
