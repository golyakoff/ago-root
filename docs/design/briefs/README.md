# Per-role briefs

Five documents, one per role, each joining `../flows.md` (what a person is trying to do) to
`../ui-inventory.md` (what exists). They are input for the design pass, not part of it.

| Brief | Stories | Surfaces the role can reach |
|---|---|---|
| [visitor.md](visitor.md) | 1.1 – 1.5 | the widget only — a launcher, a panel, five bubble kinds, four booking content kinds |
| [chat-operator.md](chat-operator.md) | 2.1 – 2.5 | two routes (`/`, `/conversations/:id`) plus six aside panels and two dialogs |
| [calendar-operator.md](calendar-operator.md) | 3.1 – 3.4 | seven `/calendar/*` routes, two of them reachable only from a row action |
| [tenant.md](tenant.md) | 4.1 – 4.5 | seventeen routes — every settings and report screen, plus the three pre-session ones |
| [platform-owner.md](platform-owner.md) | 5.1 – 5.3 | one route, `/owner` |

## What each brief contains, per story

- the routes and surfaces the story touches, with their inventory section
- the states those surfaces have today
- **the states the story requires that do not exist**, each pairing a quoted sentence from
  `flows.md` with a recorded finding in `ui-inventory.md`
- the mobile constraints from inventory §10 and §11 that apply
- the cross-cutting facts (§12 inconsistencies, §13 stubs and dead ends) that bear on it

**Nothing in these files is new judgement.** Where a brief says a state is missing, it is because the
story requires it and the inventory recorded its absence — not because anyone decided it ought to be
added. No brief proposes a layout, a control or a word of copy.

## Two things a reader should know before using them

**1. Story 4.3 is marked `built` and has no screen.** `flows.md` marks "Giving a colleague access"
`built`, and `docs/backlog/13-01-*.md` agrees — the backend merged on 2026-08-28. The inventory
records (§13.4) that the console has **no route, nav entry or UI** for inviting, listing, removing or
re-roling an operator, and that `site:manage-operators` is never checked by the console at all. The
capability is built and the tenant cannot reach it. By the story-writer skill's own rule — *a story
about a screen that does not exist is a proposal; one about a screen that does is a critique* — this
one is currently filed as the wrong kind. Worth settling before design starts.

The same shape, already correctly labelled, appears at 5.2 ("built as an API, **no screen at all**")
and is noted in the inventory for conversation transfer (§13.5) and tenant data export (§13.6).

**2. `ui-inventory.md` §13.1 is stale.** It records the `/calendar/setup` embed snippet as broken
four ways. That finding became `22-22` and was **fixed in `ago-console` at `a64fcac`**; the backlog
item is still marked *in review*. The tenant and calendar-operator briefs both carry the correction
in place, and `ui-inventory.md` now carries a dated corrections section.

## Related

- `../ui-inventory.md` — every screen and view state that exists
- `../flows.md` — the twenty-two stories
- `../design-system/` — the console's tokens and eleven components, previewed faithfully
- `.claude/skills/user-story-writer/SKILL.md` — the format `flows.md` is written in
