# the calendar console's gate checks that everything is translated

- **Stage**: 11
- **Status**: done (2026-09-03). **Written retrospectively on 2026-09-06**; see `23-49`.
- **Found**: 2026-09-03, as `11-16`'s other half — `ago-console` got the assertion in `ago-console#92`;
  `ago-calendar-console` had not.

## Written retrospectively

`ago-root#350` shipped with one commit and no backlog file. This is the reconstruction `23-49` asked
for. The issue body is reproduced and matched against what the commit actually did; where the two
disagree, the commit is treated as the truth, since it is the thing that ran.

## The gap the issue named

A fourth assertion, ported to `ago-calendar-console`'s own UX gate: on a screen rendered in Russian, no
user-facing text is left in another language, across both viewports and all eight screens. `11-15` had
already given this console `en`/`ru` tables and translated every screen, so the issue expected this to
pass on day one — **and said explicitly that if it did not, that was a real defect to report, not
exempt away.**

The issue pointed at `ago-console/ux-gate/lib/i18nCompleteness.ts` as the shape to port rather than
reinvent, and named the two decisions that make it exact: every fixture seeded in Cyrillic including
the locale-switching field itself, and an exemption list that is a named, auditable set rather than a
pattern — explicitly not to be copied from `ago-console`'s own list, since this console has no
`/owner` and may have loanwords `ago-console` does not.

It also flagged two known risks going in: the gate was blocking as of `15-12`, so a red assertion here
would redden every pull request; and `ago-console`'s gate flaked on `page.goto` timeouts (`#349`),
which was called out as "the same problem and not a new one" if it recurred here.

## What the commit actually did

`ago-calendar-console` commit `f6d2e8a` — `feat(11-19): the gate's fourth assertion - no untranslated
text on a Russian screen` — matches the issue's own instruction closely:

- Every fixture seeded in Cyrillic, including the string-table-switching field, so a surviving
  Latin-script run is interface chrome by construction rather than a coincidentally-Latin customer
  name.
- Its own exemption list, **derived from running the assertion for real** rather than copied from
  `ago-console`: four named phrases (the product name, IANA, Email, the seeded zone id) plus `<pre>`
  and `<code>` excluded structurally by tag, plus two whole-node shape exemptions `ago-console` did not
  need — an invited operator's email address and the allowed-origins textarea — each matching the
  entire trimmed node against an unambiguous format, never a substring.
- **It found three real defects on first run rather than passing outright**, none of them exempted
  away: raw `toLocaleString`/`toLocaleTimeString`/`toLocaleDateString` calls in four screens with no
  locale argument, rendering in whatever the runtime happened to be — the commit message calls this
  "the same defect `11-17` fixed next door, found here independently by the same kind of check," and
  routes all four through one helper driven by `strings.intlLocale`.

The commit message does not mention the `page.goto` flake risk the issue called out, which reads as
that risk not having recurred here — not confirmed independently, since no separate report exists.

## What is not recoverable

The commit is a single, self-contained change; there is no design-decision trail beyond what its
message states (quoted above in full for that reason). If the exemption list changed shape during
development, or if any fixture needed more than one pass to seed correctly, that history was not kept
anywhere this reconstruction could find.

## Out of scope

- Re-implementing or re-verifying the assertion — it shipped and is live in `ago-calendar-console`'s
  gate.

## Done when

- [x] The record exists: what the issue asked for, what the commit actually built, and that the two
      match closely enough that nothing here needed correcting against the code.
