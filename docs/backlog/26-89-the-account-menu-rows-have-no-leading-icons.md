# 26-89 · The account menu's «Настройки»/«Выйти» rows have no leading icon, the mockup draws one

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-24, by the author — "согласно мокапам у пунктов меню пользователя «Настройки» и
  «Выйти» должны быть слева иконки, даже нарисовано какие. Необходимо их добавить."
- **Verified against the real mockup** (`AGO Chat Design` artifact,
  `https://claude.ai/code/artifact/8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`, section 08 "Аккаунт и шапка"):
  each `.pop-item` row is `<svg icon>Текст<svg chevron?>` — «Настройки» carries `#i-sliders` (leading)
  plus `#i-chev` (trailing, already shipped as `AgoIcons.ChevronRight` per `26-77`); «Выйти» carries
  `#i-logout` (leading, no trailing icon). Neither leading icon exists in `AgoIcons.kt` yet.
- **The real path data, transcribed from the mockup's own `<symbol>` sprite** — copy these into
  `AgoIcons.kt` following that file's own established `strokeIcon(...)` pattern (24×24 viewport, 1.8
  stroke width, round caps/joins — every existing icon in that file already follows this shape; do not
  approximate, transcribe faithfully the way that file's own doc comment requires):
  - `#i-sliders` (→ e.g. `AgoIcons.Sliders`): `<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/>` (three separate
    move/line subpaths — read as `M4 7 h10`, `M18 7 h2`, `M4 17 h4`, `M12 17 h8`) plus
    `<circle cx="16" cy="7" r="2"/>` and `<circle cx="10" cy="17" r="2"/>`.
  - `#i-logout` (→ e.g. `AgoIcons.Logout`): `<path d="M9 21H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3"/>`
    (a door: down, left, rounded corner, up, rounded corner, right — an open-sided rounded rectangle),
    `<path d="M16 17l5-5-5-5"/>` (the arrowhead), `<path d="M21 12H9"/>` (the arrow's shaft).

## Scope

- Add both icons to `AgoIcons.kt`, named to match that file's own convention.
- Wire `AgoIcons.Sliders` as `DropdownMenuItem`'s `leadingIcon` on the «Настройки» row in
  `AccountAvatarAction.kt`, alongside the trailing chevron it already has.
- Wire `AgoIcons.Logout` as the leading icon on the «Выйти» row — no trailing icon, matching the mockup.
- Match the mockup's own visual weight: small icon size, muted colour (`onSurfaceVariant` or equivalent
  — the mockup's own `.pop-item svg{color:var(--ink-soft)}`), consistent spacing with the text
  (`gap:10px` in the mockup) — read the actual token names this app's own theme uses rather than
  inventing new ones.

## Out of scope

- Any other menu item — the account menu has exactly these two rows today; nothing else needs an icon.

## Done when

- [ ] Both icons exist in `AgoIcons.kt`, transcribed faithfully from the mockup's own path data.
- [ ] «Настройки» shows the sliders icon on the left, the chevron on the right (unchanged).
- [ ] «Выйти» shows the logout icon on the left, no trailing icon.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
