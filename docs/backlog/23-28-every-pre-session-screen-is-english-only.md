# every screen a person sees before they have a site renders in English only

- **Stage**: 23
- **Status**: ready. **The question below is answered** (author, 2026-09-05) — see *The answer*.
- **Depends on**: nothing.
- **Found**: 2026-09-05, while building `23-27`. Filed under CLAUDE.md rule 14 as a question rather
  than an answer, because the fix turns on a choice about where a locale comes from.

## Goal

A person invited to a Russian shop's AGO Chat, or signing up for one, reads the screen in Russian.

## What is actually wrong today, verified

Four routes sit outside `StringsProvider` and render hardcoded or English-resolved text:

| Route | Who reaches it |
|---|---|
| `/callback` | anyone returning from Keycloak |
| `/signup` | a visitor with no session |
| `/onboarding` | an authenticated identity with no site |
| `/redeem-invite` (`23-27`) | somebody handed an invite code |

This is not an oversight in any one of them. `StringsProvider` resolves the locale from **the site**,
and none of these four callers has one yet — `/redeem-invite` most sharply, since a person redeeming
an invite is by definition not yet an operator anywhere. `23-27` added the fourth and exempted it from
`ux-gate`'s untranslated-text assertion by name, the same way `owner-sites` already was, and recorded
that as a gap rather than a decision.

**`ui-inventory.md` has said "Language: hardcoded English" under three of these for some time.** What
changed is that the product is about to take Russian clients, so a line that read as a note now reads
as a defect.

## The question, and it is the author's

Where does the locale come from for somebody who has no site?

1. **The browser's own `Accept-Language` / `navigator.language`.** Costs nothing, works for every one
   of the four routes, and is what most services do. It is a guess: a Russian shop assistant on an
   English-configured laptop gets English.
2. **A locale carried on the invite** (and on the signup link). Exact for the case it covers —
   whoever sent the invite knows what language the recipient reads — but it covers only `/redeem-invite`
   and possibly `/signup`, and leaves `/callback` and `/onboarding` to fall back on option 1 anyway.
3. **Both**: the carried locale when there is one, the browser otherwise.

Option 3 is the only one that answers all four routes without guessing where it does not have to, and
it costs a parameter on two links. **It is not chosen here**: which of the three ships is a product
call, and this item exists to put it in front of the author rather than to make it by being written.

## The answer (author, 2026-09-05)

**The site's own setting decides. Where nothing is set, Russian.**

That is none of the three options above, and it is better than all of them. Each of mine assumed the
locale had to be *derived* from something — the browser, the invite — because the site could not
supply one. The author's answer removes the premise: for a product selling to Russian shops, Russian
is not a fallback for a failed guess, it is the correct default, and a guess is only worth making when
it can beat the default.

What this commits to:

- **A signed-in person with a site reads that site's locale**, exactly as every other screen already
  does. Unchanged.
- **Every pre-session screen renders Russian** — `/callback`, `/signup`, `/onboarding`,
  `/redeem-invite` — because none of them has a site to ask.
- **No new plumbing.** No `Accept-Language` parsing, no locale on the invite, no third source of truth
  to keep consistent. The two locale files already carry every string.

**And it makes the `ux-gate` exemption removable**, which was the point of writing this item as a
question rather than a note: with a real locale to render, `redeem-invite` no longer needs to be
excused from the untranslated-text assertion, and the exemption's disappearance is what proves the fix.

## Out of scope

- **Adding a third locale.** The console ships `en` and `ru`; this item makes the existing two reach
  four screens that cannot use them.
- **`/owner`.** `11-11` decided that renders in English on purpose, for one reader who wrote it that
  way. That exemption stays and this item must not quietly widen itself into it.
- **The invite's own delivery.** How a code reaches a person is `10-05`'s.

## Done when

- [ ] The author has chosen among the three options above, and the choice is recorded.
- [ ] All four routes render in the reader's language under that choice.
- [ ] `ux-gate`'s by-name exemptions for `redeem-invite` shrink or disappear, whichever the choice
      allows — the exemption existing is what makes this item checkable.
- [ ] `ui-inventory.md`'s "Language: hardcoded English" lines are corrected, since three of them
      currently describe the intended state rather than a defect.
