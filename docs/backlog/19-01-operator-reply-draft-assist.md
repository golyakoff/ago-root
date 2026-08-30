# AI operator reply-draft assist

- **Stage**: 19 (AI assistance — reserved stage, first use)
- **Status**: ready
- **Depends on**: nothing new architecturally — console-side, reads data the operator already sees

## Goal

An operator, looking at a conversation, can request an AI-drafted reply suggestion into the composer —
editable and discardable, never sent without the operator choosing to send it — the lowest-risk of the
five AI capabilities `docs/adr/0078` names, and the one this stage starts with for exactly that reason.

## Why this is safe to build first, stated precisely

The visitor never sees anything the operator did not read, judge, and choose to send. A wrong or
low-quality suggestion costs an operator a few seconds of judgment; it cannot reach a customer directly,
the same trust boundary `18-03`'s canned responses already sit behind. This is `adr/0078`'s own
reasoning for ordering the five kinds by risk — this item is where the ordering starts.

## Context to read first

`docs/adr/0078-ai-automation-taxonomy-and-where-each-kind-fits.md` — kind 1's own full reasoning,
including why this needs no module contract and no change to `adr/0065`'s boundary. `18-03`'s own
backlog file — the closest existing precedent for "console offers the operator a piece of text to send,
they choose whether to," reused as the trust model, not the mechanism (canned responses are static
text a tenant configured; this item's text is generated per-conversation).

## The provider choice — a real, named decision, not assumed

This project has never called an external LLM API. **Which provider, and under what contract** (a
direct API key held as `infra-credentials`, matching every other external-API secret this codebase
already holds that way — `YooKassaOptions`, `TelegramBotApiOptions`) is a real decision this item makes
explicitly, the same way `20-05`'s own SMS-vendor question was named as open rather than guessed at.
State the choice and why, in this item's own Outcome once built — `CLAUDE.md`'s "measure or stay
silent" rule applies to a vendor choice with real per-call cost exactly as it does to a numeric
constant.

## Scope

- A new port, `IReplyDraftGenerator` (or similarly named once the actual shape is written), in
  `Ago.Chat.Application/Abstractions` — the dependency-rule boundary: Application knows a draft can be
  requested, not which HTTP API produces it, the same reasoning every other external-resource port in
  this codebase already follows.
- An `Ago.Chat.Infrastructure.<Provider>` project implementing it against whichever provider this item
  decides on, wrapped in the same resilience pipeline (timeout/retry/breaker) every other outbound call
  in this codebase already uses — an LLM call is exactly the kind of external, sometimes-slow,
  sometimes-down dependency `Ago.Platform.Resilience` exists for.
- A console control ("Suggest a reply" or similar) that calls a new endpoint, receives a draft, and
  populates the composer — never auto-sends.
- The prompt context: the conversation's own recent message history (already visible to the operator
  requesting it — no new personal-data exposure beyond what the operator already reads), plus whichever
  minimal system framing the provider needs. **No tenant-specific business knowledge** (product
  catalogs, policies) — that is kind 3's own scope (`19-03`), not this item's; conflating them would
  turn a cheap, safe feature into a scoped-down version of the riskier one.
- Rate/cost containment: a per-site or per-operator cap on requests in some window, named and decided
  explicitly (a real cost-control decision, not an afterthought) — every call costs real money against
  a real API budget, unlike every other console interaction this project has built so far.

## Out of scope

- Any tenant-specific knowledge base or grounding — `19-03`'s own scope.
- Auto-sending a draft without operator action — never, by this item's own design, not a future
  toggle this item leaves half-built.
- Multi-turn "chat with the AI about how to answer" — a single suggest-and-edit interaction, not a
  conversational assistant UI.

## Done when

- [ ] An operator can request a draft reply for a real conversation and receives real generated text
      into the composer, editable before sending — proven end to end against the real provider chosen.
- [ ] The provider is never called with more context than the conversation's own message history plus
      the minimal framing needed — proven by inspecting the actual request payload in a test, not by
      code review alone.
- [ ] A rate/cost cap exists and is enforced, proven by a test that exceeds it and confirms the
      expected rejection, not just that a config value exists.
- [ ] The resilience pipeline's own unreachable-provider path degrades to "suggestion unavailable,"
      never to a stuck or silently-failing UI control.

## Open questions

The provider choice itself, resolved by whoever picks this item up and recorded in its own Outcome
section — not guessed at here.
