# every gated navigation entry says whether it is available, without being clicked

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-21` — the second list on `GET /api/v1/operators/me` and the shared
  `CalendarAccessRefusal` treatment it introduced. This item generalises both rather than inventing
  a second version of either.
- **Decision**: `docs/design/decisions.md` §10 (2026-09-05)

## Goal

A person opening the console can tell, at a glance and without clicking anything, which entries are
theirs to use and which are not — and, for the ones that are not, who can change that.

## What is actually wrong today, verified

`23-21` fixed one gate of three. `consoleNav.ts` has exactly three permission gates and only one of
them has an else branch:

| Gate | What is behind it | Branch for "no permission" |
|---|---|---|
| `calendar:configure` | five calendar entries | **yes**, since `23-21` |
| `site:configure` | `/admin`, `/search`, `/analytics`, the reports | **none** — they vanish |
| `site:erase` | erasure | **none** — it vanishes |

So the defect `23-21`'s title describes is still live for most of the console. That is a slicing
error rather than an implementation one: `23-21`'s Done-when list asked for the calendar case and got
it.

**And the entry that does appear looks ordinary.** An operator who lacks `calendar:configure` today
sees a normal-looking `/calendar` link and only discovers it is refused by clicking it. Decision §10
is explicit that this is the part to fix: nobody should have to click a thing to find out they cannot
use it.

## Scope

- **The remaining two gates get the same shape** `23-21` established: shown when a colleague at this
  tenant could grant the permission, hidden when nobody there could. `site:configure` and
  `site:erase` are both grantable by an owner at the tenant, so both are shown.
- **A muted treatment for an entry the caller cannot use**, applied to all three gates including the
  calendar one `23-21` already ships. **Muted is a style, never `disabled`** — the entry stays a real
  link, keyboard-reachable and announced, because the page it opens is where the explanation lives
  (§10's own reasoning).
- **One lock glyph**, inline SVG, beside a muted entry. It carries a **translated** visually-hidden
  label; without one it does not exist for a screen reader, and `11-13` makes an untranslated one a
  gate failure rather than a nit.
- **`adr/0030` gains an amendment**, not a replacement: one glyph, for one meaning. The ADR closed
  the component set at eleven on purpose and `gaps.md` lists the icon question among the ten still
  open; this item answers it **narrowly** and says so, so the exception is not read as permission to
  bring a whole icon set.
- **The refusal page is the shared one**, extended to name each capability rather than a second
  hand-written block per gate — the same consolidation `23-21` did for the calendar's seven.

## Out of scope

- **What a tenant has not bought.** That stays hidden, per §10, and is `23-25`'s surface.
- Changing who holds which permission — `23-22`.
- A tooltip. It is one of `gaps.md`'s ten open questions and this item deliberately does not need
  one: the glyph marks, the page explains.
- The `/owner` screens (`ui-inventory.md` §8.1).

## Done when

- [ ] An operator without `site:configure` sees the admin entries, muted and marked, and reaches a
      refusal naming who can grant them — asserted on the rendered state, not on pixels.
- [ ] The same for `site:erase`.
- [ ] The calendar entry `23-21` already shows is muted and marked too, so the three gates are one
      treatment rather than two.
- [ ] A capability the tenant does not have is still shown to nobody — a test, because this is the
      half most likely to be "fixed" into over-disclosure by a later reader.
- [ ] The lock glyph has a hidden label present in both `en.ts` and `ru.ts`.
- [ ] `ux-gate` passes, including its WCAG AA contrast measurement — which is what bounds "muted"
      from drifting into unreadable.
- [ ] `adr/0030` carries the one-glyph amendment, and `gaps.md`'s icon question records that it was
      answered narrowly rather than closed.

## Open questions

None. §10 settles the rule; this item applies it.
