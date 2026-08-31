# Conversation topic and tag breakdown report

- **Stage**: 18
- **Status**: done (`ago-chat#139`, `ago-console#73`, merged 2026-08-30)
- **Depends on**: `18-04-internal-notes-and-tags.md` (done) — the tag data this item reports on;
  `18-08-basic-operator-analytics.md` (done) — the per-channel breakdown shape this item extends with a
  second dimension

## Goal

A site owner can see, alongside `18-08`'s per-channel numbers, a breakdown by **what conversations are
actually about** — "which channel/topic is worth the money spent on it", the value-for-money half of
`ago-business/docs/decisions/0009`'s reporting gap (the other half, conversion, is `18-10`).

## The real dependency, named honestly before scoping the rest

`18-04` built tagging as an **operator-applied, manual** feature — an operator labels a conversation if
and when they choose to. Nothing in this system tags a conversation automatically today. A report that
groups by tag, built against manual-only tagging, will in practice show mostly-untagged conversations
for any site whose operators do not consistently tag every chat — the same "nobody fills in optional
metadata" failure every product with an optional field eventually hits, and a report built on top of
that would report on the minority of conversations someone bothered to label, silently presenting it as
if it covered all of them.

**This item is buildable against manual tags alone**, and is honestly limited that way until `19-02`
(automatic conversation categorization, `docs/adr/0078`) lands — at which point the same report becomes
meaningfully complete without changing its own query shape, since `19-02`'s own scope is "assign one of
the site's own existing tags," the identical vocabulary this report already groups by. State this
dependency in the report's own console UI too (an honest "N% of conversations are tagged" figure
alongside the breakdown, not just in this document), the same "don't let an incomplete number look
complete" discipline `18-10`'s own `Unset`-exclusion decision already holds itself to.

## Scope

- Extend `18-08`'s read store (or add a sibling query, decided the same way `18-09` decides) with a
  tag-dimension breakdown: conversation count, and (once `18-10` lands) conversion rate, grouped by
  tag — a conversation with multiple tags counts once per tag it holds, stated explicitly since it means
  the breakdown's totals will not sum to the site-wide total, the same non-mutually-exclusive-category
  honesty a multi-tag system always owes its own report.
- A "percentage of conversations tagged at all" figure, computed and shown alongside the breakdown —
  the honesty check named above, not an afterthought.
- A console panel extending `OperatorAnalyticsPage` (or a sibling page, decide by how large the
  combined page gets) with the tag breakdown table.
- Gated the same permission `18-08`'s own handler already uses.

## Out of scope

- Any automatic categorization — that is `19-02`'s own scope entirely; this item only reports on
  whatever tags already exist, by whatever means they were applied.
- A tag-management UI beyond what `18-04` already built (renaming, merging near-duplicate tags) — a
  real, separate concern if manual tagging in practice produces messy near-duplicate tags, not
  something to solve inside a reporting item.

## Done when

- [ ] Conversation count per tag, and the "percentage tagged" figure, compute correctly against real
      seeded data with a mix of tagged and untagged conversations and conversations holding multiple
      tags, proven by a test.
- [ ] Once `18-10` has landed, conversion rate per tag is included in the same breakdown — if `18-10`
      has not landed when this item is picked up, ship the count-only breakdown and record the
      conversion column as a follow-up, not a silent gap.
- [ ] Cross-site isolation is proven by a test.
- [ ] The console panel renders the breakdown with the "percentage tagged" figure visibly alongside it,
      not buried — proven by a rendered-component test asserting both are present, not just that the
      component mounts.

## Open questions

None left open by this item's own scope. Whether `19-02` should land before or after this item is a
sequencing call for whoever picks up Stage 18/19's own queue, not a blocker this item's Done-when
depends on — the item is honestly useful either way, just more useful after.
