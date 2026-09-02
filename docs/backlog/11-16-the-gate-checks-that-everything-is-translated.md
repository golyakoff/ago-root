# The gate checks that everything is translated

- **Stage**: 11
- **Status**: ready
- **Raised by**: the author, 2026-09-02 — *"в аудит по фронту надо добавить ещё что всё переводится
  на русский (кроме страниц доступных ТОЛЬКО platform owner)"*.
- **Split from**: `11-15`, which delivered the repair this check protects but not the check itself.
- **Builds on**: `15-11` (the rendered gate this assertion joins), `11-11`…`11-13` and `11-15` (the
  two consoles now both have a string mechanism, so the assertion can be green on day one).

## The check

A fourth assertion in `15-11`'s gate: **on a screen rendered in Russian, no user-facing text is left
in another language.** Both consoles, both viewports.

It could not have been added before `11-15`. `ago-calendar-console` had no localisation at all, so the
assertion would have been permanently red there — the failure mode `ago-calendar-console#26` exists to
unwind. That console now has a string table and translated screens, so this check joins as a
regression guard in both places rather than as a to-do list.

## How to make the check precise rather than noisy

The hard part is telling **interface text** from **data** — a customer really may be called *John*, and
a brand name is not a translation failure.

**Seed every fixture in Cyrillic.** The gate already controls all data on screen (`ux-gate/fixtures/`),
so with names, services and notes written in Russian, **any Latin-script run left on the page is by
definition interface chrome.** That turns a fuzzy heuristic into an exact one, and it costs nothing but
editing a fixture file.

Exemptions, each **named rather than pattern-matched**:

- Platform-owner-only screens — `/owner` in `ago-console`, gated by `RequirePlatformOwner` server-side
  and `useOwnerEligibility` in the navigation. Seen by one person, who wrote them.
- The product name itself, and any string that is a technical identifier a translator must not touch
  (a URL, a header name, a status code).

An exemption list a reader can audit is the point. A regular expression over "words that look
technical" would quietly exempt the next real defect.

## Decided: an untranslated string fails the build

The original item left this open — *"does an English string on a Russian screen fail the build, or
warn?"* — on the reasoning that an untranslated label is less severe than an unreachable control.

**The author decided on 2026-09-02: it fails.** A warning in a gate nobody is blocked by is a
permanently ignored line of output, and the whole reason this gate exists is that green checks have
repeatedly coexisted with user-visible breakage here. The severity argument cuts the other way once
the tenant is a Russian-speaking business who cannot read the untranslated string: for her it is not
cosmetic.

This makes `ago-calendar-console#26` — making that repository's gate blocking at all — a prerequisite
rather than a neighbour. A failing assertion in a gate whose exit code nothing reads changes nothing.

## Scope

- A fourth assertion in `15-11`'s gate, sharing its `lib/` shape, run at both viewports, in
  `ago-console` and `ago-calendar-console`.
- Fixtures re-seeded in Cyrillic in both consoles.
- A named exemption list.
- The assertion **proven to fail first** against a deliberately untranslated label — in both
  repositories, not just one.

## Out of scope

- `ago-widget`. It has its own locale mechanism (`11-10`: `widgetLocale` arrives on the session
  response) and its surface is three buttons and a composer. Worth checking eventually; not this item.
- Any language beyond the two already modelled.
- Extracting a shared string mechanism into a package. Same reasoning as `11-14`: two consoles, no
  shared package, and 84 tokens against 5 — a shared layer does not get decided under launch pressure.

## Done when

- [ ] A screen rendered in Russian with Cyrillic fixtures shows no Latin-script interface text, in
      both consoles, at both viewports — and the assertion is **proven to fail first** against a
      deliberately untranslated label.
- [ ] `/owner` is exempt, and the exemption is a named list a reader can audit — not a pattern.
- [ ] A failing assertion **fails the run**: the gate exits non-zero and something reads that exit
      code in `ago-calendar-console` (`#26`), not only in `ago-console`.
- [ ] `15-11`'s existing three assertions stay green in every repository they are green in today.

## Open questions

- **Is the tenant-facing booking widget in scope later?** It is the surface a *customer* sees, which
  makes it more exposed than either console, and nobody has looked at its localisation at all.
- **What happens to the ten pre-existing gate failures** (`#22`/`#23`, overflow and sizing) when the
  calendar console's gate becomes blocking? They have to be fixed or explicitly quarantined first,
  or `#26` cannot land — which makes them this item's problem in practice even though they are not
  its subject.
