# ADR-0129: A muted navigation entry means "you can obtain this yourself" — replacing "a colleague here could grant it"

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 23 (`23-31`)

## Context

`23-24` (`docs/design/decisions.md` §10, "Navigation shows what a colleague here could grant. Nothing
else") decided the console's navigation had exactly three states for a gated entry: held (ordinary),
not held but a colleague at this tenant could grant it (**muted**, with a lock glyph, still a real
link), or not held and nobody at this tenant could ever grant it (nothing drawn at all). That rule
correctly closed a real defect — `23-21`'s own finding that "you cannot do this" and "nobody granted
you this" rendered as the identical absence for the calendar — and generalised it to every other gate
in the flat, twenty-four-item strip: `site:configure`, `site:erase`, `site:manage_operators`.

`23-31` restructures that flat strip into seven sections behind a two-level accordion (`consoleNav.ts`
`buildTenantNavSections`, `docs/backlog/23-31-*.md`) and, in the same change, **splits what used to be
one signed-in identity into two audiences with different reasons to see a muted entry**:

- **A tenant** (in practice, whoever holds `site:configure` — the same permission
  `ProductsPage.PRODUCTS_PERMISSION` already treats as "may act for the tenant as a whole", the
  identical gate `/account/billing`'s own checkout uses) can genuinely **buy** a module the site does
  not have yet, or grant themselves a permission on one it already has. Nothing about that requires
  anyone else's cooperation.
- **An operator** (anyone lacking that permission) can do neither. Whatever they lack, a *person* —
  an owner or admin at the same tenant — decided not to grant them, or the module was never bought at
  all. Either way, nothing the operator does next changes it.

Once those are different facts, `23-24`'s single "a colleague could grant it" test does not carve the
same line any more. Every one of the thirteen `site:configure` entries, the `site:erase` one, and the
`site:manage_operators` one, are things **a colleague grants**, not things the viewer buys — under a
rule that means "you could obtain this yourself", none of those thirteen qualify for `muted` any
longer. Only one gate in this console is genuinely self-obtainable by the tenant: the calendar module,
behind `calendar:configure`.

The item's own instruction states the consequence plainly rather than leaving it to be inferred: *"An
operator sees nothing muted at all. Their tenant granted what it chose to grant; nothing here depends
on the operator, so an entry they can neither use nor obtain is noise."* That is a real narrowing of
`23-21`'s own fix, not an oversight repeating its mistake, and this ADR exists specifically to record
that trade rather than let the next reader assume `23-24` still holds unchanged.

## Decision

**Muted now means "this identity could obtain the thing behind this entry itself."** Concretely, in
`consoleNav.ts`:

| The person | The permission-gated entry (`site:configure` / `site:erase` / `site:manage_operators`) | The calendar (`calendar:configure`) |
|---|---|---|
| Holds it | ordinary | ordinary |
| Lacks it, holds `site:configure` (the tenant) | **hidden** — a colleague grants this, the tenant cannot buy it | **muted**, badge names "buy this" |
| Lacks it, does not hold `site:configure` (an operator) | **hidden** | **hidden** |

Every gate that used to render "muted when lacking" now renders **hidden when lacking, ordinary when
holding** — the shape this file had *before* `23-24`, restored for exactly those thirteen entries,
because they were never buyable to begin with and only ever looked as if the same rule applied to
them because `23-24` had one rule for everything. The calendar is the only survivor of the old
three-state shape, and it survives with a **narrower** third case: no more single "operator, tenant
has the module, but I don't hold it" muted entry (`23-21`'s own fix) — that case now collapses into
hidden too, because the operator still cannot self-obtain it regardless of what the tenant has bought.

**The marker changes with the meaning.** `23-24`'s padlock (`AppShell.tsx`'s `NavLockGlyph`,
`adr/0030`'s 2026-09-05 amendment) said "locked, someone else holds the key" — accurate for a
colleague-granted permission, wrong for a price. The calendar's own muted entry now carries a small,
visible `Badge` (`strings.navBuyableLabel`, "Докупить"/"Add-on") instead — the same closed
eleven-component set `adr/0030` already includes, reused rather than extended a second time. This is
not a new icon-set question: `NavLockGlyph` had exactly one meaning and that meaning left with the
rule it illustrated, so the glyph is deleted rather than repointed at a fact it no longer states.

**`AppShellNavItem.reserved`** (new in this item, not a muting-rule change but adjacent to it) is a
third, unrelated state: a place held in the structure for a screen that does not exist yet (`Записи`,
`Общение`, three channel screens, two AI-automation screens, `Документы`). It is never a link at all —
no `href`, not part of the tab order — and is drawn identically for every viewer who can see the
section it sits in, since nothing about "does this screen exist yet" depends on who is looking.

## Consequences

**The cost, named because `23-24` was right to worry about it.** An operator who lacks
`calendar:configure` no longer sees any indication the calendar exists on this console at all, on a
tenant that has bought it or not. Before this item, `23-21`'s fix specifically kept one muted entry
visible so that operator could learn the capability existed and think to ask for it. That path is
gone. Nobody's workflow in this codebase today depends on an operator discovering the calendar through
the nav rather than being told about it directly (there is no in-product request-access flow this
would have fed into either — `ProductsPage`'s own scope note: "enabling a product is owner-only today,
through a runbook, not a console write"), so the accepted trade is real but bounded: shorter, more
honest navigation for the large majority of operators, in exchange for one discovery path that led
nowhere actionable regardless.

**Thirteen entries get simpler, not just differently coloured.** `hasPermission("site:configure")`
(and `"site:erase"`, `"site:manage_operators"`) now decide a plain show/hide, the same shape they had
before `23-24` ever introduced the three-way split for them. Reverting to that shape is not "undoing"
`23-24` — `23-24`'s own finding (the calendar's absent-looks-like-forbidden defect) is untouched, and
the muted treatment for the one gate that is actually buyable is kept in a narrower, more accurate
form. What is removed is the part of `23-24` that never should have generalised past the calendar in
the first place: thirteen entries where the "you could still get this, from someone" story was never
true.

**`adr/0030`'s 2026-09-05 amendment is superseded, not merely unused.** That amendment opened the
closed component set by exactly one glyph, "for one meaning" — the meaning is gone, so the opening is
too. `NavLockGlyph` is deleted from `AppShell.tsx`; nothing in the console renders a lock icon any
more. The set stands at eleven again, with `Badge` (already one of them) carrying the one thing that
still needs marking.

**`ux-gate/fixtures/screens.ts` needed a second scenario, not a rewording of the first.** The old
`admin-limited-permissions` fixture existed to exercise "every row of decision §10's table in one
screen" — under this decision there is no single screen that exercises both the operator's hidden
state and the tenant's muted state at once, because they are reached by different permission grants.
`calendar-nav-muted` (new) exercises the tenant/muted case at `/calendar/waiting` — chosen because the
calendar's own muted item's `to` is exactly that address, so the rail's own route-matching opens the
Календарь section automatically, without this gate ever needing to click a section header.

## Alternatives considered

**Keep one rule, make the calendar an exception inside it.** Rejected: a rule with one silent
exception is a worse rule than two named ones, and the next person to read `consoleNav.ts` would have
had to discover the exception by reading code rather than a decision record.

**Mute every entry for the tenant, matching the old "three states, one rule" shape, and hide every
entry for the operator.** This is close to what shipped, and was seriously considered — the difference
is whether *hidden* entries include the calendar for a tenant who has bought the module but lacks
`calendar:configure` personally. Rejected in favour of muting it for the tenant regardless of
`enabledModules`: the tenant can always fix that gap themselves (grant themselves the permission, or
buy the module if it is not yet bought), so hiding it there would reintroduce exactly the
absent-looks-like-unavailable ambiguity `23-21` fixed, one level up.

**Keep the padlock glyph and just change its hidden label.** Rejected: a lock icon reads as
"restricted", not "for sale" — repointing the same shape at the opposite meaning would have been a
worse-than-nothing visual pun, and this console already has a component (`Badge`) built for exactly
"a short, named status next to something".
