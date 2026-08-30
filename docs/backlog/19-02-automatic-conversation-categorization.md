# AI automatic conversation categorization

- **Stage**: 19 (AI assistance)
- **Status**: done (`ago-chat#134`, `ago-console#68`, merged 2026-08-30) - not verified against a real
  YandexGPT account, no live API key/folder id exists in this environment
- **Depends on**: `18-04-internal-notes-and-tags.md` (done) — the tag vocabulary this item assigns
  into, never invents its own; `19-01-operator-reply-draft-assist.md` — reuses whichever LLM provider
  port that item establishes, a second consumer of the same port rather than a second integration

## Goal

Conversations get tagged automatically, from the site's own existing tag vocabulary, without an
operator having to remember to do it — closing the real gap `18-11`'s own file names: manual-only
tagging leaves most conversations untagged in practice, which makes a topic-breakdown report report on
a minority.

## Why this, and why now

`docs/adr/0078` names this as kind 2 — lowest risk alongside kind 1, because the output lands in a
database column an operator can see and correct, never in a message a visitor reads. `18-11`'s own file
names the dependency directly: its report is honestly limited until this item exists.

## Context to read first

`docs/adr/0078`'s kind 2 section — the risk argument this item's own design has to preserve (no
customer-facing output, ever). `18-04`'s `Tag`/`ConversationTag` domain shapes — this item writes into
the identical rows a human tagging action already writes into; nothing new to model there. `13-06`'s
own periodic-job precedent (`PartitionMaintenanceJob`) or `15-04`'s retention jobs — the architectural
shape this item's own background classifier follows: a `Ago.Chat.Worker` `BackgroundService`, not a
request-path call, since classification has no reason to block anything a visitor or operator is
waiting on.

## Scope

- A periodic `Ago.Chat.Worker` job that finds recently-closed (or recently-created, decide which better
  matches "worth classifying") conversations with no tags yet, and calls the LLM provider port `19-01`
  established to pick zero or more of the **site's own existing tags** — never a tag the LLM invents
  that does not already exist in that site's vocabulary. This constraint is load-bearing: an
  auto-created tag vocabulary would defeat the whole point of grouping by a small, operator-understood
  set of categories, and would make `18-11`'s report noisy rather than useful.
- If a site has **no tags configured at all**, this item does nothing for that site — never invents a
  starter vocabulary on a tenant's behalf. A tenant with no tags gets no automatic categorization,
  stated as the correct behavior, not a gap.
- The applied tag is distinguishable from an operator-applied one at the data level (a source column,
  or a distinct flag) — an operator seeing "AI tagged this" versus "an operator tagged this" is a real
  trust-and-correction signal worth preserving, not collapsing into one undifferentiated tag list.
- An operator can remove or add to an AI-applied tag exactly the way they already can for any tag
  (`18-04`'s own UI, unchanged) — this item adds a writer, not a new removal/correction path.

## Out of scope

- Inventing new tags — see above, a hard constraint, not a preference.
- Real-time classification (tagging the instant a conversation starts or a message arrives) — a
  periodic batch job is the correct shape here; nothing downstream needs the tag within seconds of the
  conversation existing.
- Classifying conversations that already carry at least one manual tag — an operator who already tagged
  a conversation has already made the judgment this item exists to approximate; do not overwrite or
  add alongside it silently. If a partially-tagged conversation should also get an AI pass, that is a
  real design question for a later revision, not assumed here.

## Done when

- [x] A real conversation with no tags gets classified into zero or more of the site's own existing
      tags by a real periodic job run, proven against a real seeded site with a real tag vocabulary.
      Independently re-proven by the managing session: disabling the handler-level candidate-membership
      guard let the handler apply a tag outside the site's own vocabulary.
- [x] A site with zero configured tags produces zero AI-applied tags, proven by a test, not left
      untested as "probably fine."
- [x] An AI-applied tag is visibly distinguishable from an operator-applied one in the console, proven
      by a rendered-component test. Independently re-proven: hardcoding the neutral tone and disabling
      the AI-marker branch made the dedicated test fail.
- [x] A conversation that already carries a manual tag is skipped by this item's own job, proven by a
      test.

## Open questions

None left open — the "never invent a tag, never touch an already-tagged conversation" constraints
above are this item's own decisions, not questions for a future session.
