# AI FAQ / knowledge-base module

- **Stage**: 19 (AI assistance)
- **Status**: ready
- **Depends on**: `20-07-calendar-becomes-a-chat-module.md` (done) — this item is the second real
  consumer of the module contract `adr/0065`/`adr/0077` built, and the first test of whether that
  contract actually generalizes beyond Calendar or was accidentally Calendar-shaped

## Goal

A visitor's routine question (return policy, business hours, shipping cost — whatever the tenant
configures) gets answered by an AI grounded in a knowledge base the tenant supplies, through the
identical module contract Calendar already uses — `Ago.Chat.*` gains no new knowledge of what "FAQ"
means, the same way it gained no knowledge of what "booking" means in `20-07`.

## Why this, and why now

`docs/adr/0078` names this as kind 3: the first AI capability that talks to a visitor directly (so a
wrong answer has a real cost, unlike kinds 1-2), and the first one that is genuinely a module in
`adr/0065`'s own sense rather than console-side UX. Building it is the actual test of `adr/0065`'s own
bet — that the closed-primitive-vocabulary design would let a second module exist without Chat's code
growing per-module branches. `20-07` proved the contract works for one module; this item is the
evidence for or against it generalizing, which `20-07`'s own report could not provide alone.

## Context to read first

`docs/adr/0065` and `docs/adr/0077` in full — the contract this item is bound by exactly, not a
variant of it. `docs/adr/0078`'s kind 3 section — the low-confidence-escape reasoning this item's own
Done-when depends on. `20-07`'s own backlog file, especially its "What this item found" sections — the
real gaps and decisions a first module implementation actually hit, worth reading before assuming this
second one will be simpler because the contract already exists.

## What is genuinely new here, not inherited free from the contract

**The knowledge base itself.** Where it lives, what format it is in, how a tenant supplies and updates
it — this item has to decide, and "a few paragraphs of text a tenant pastes into a console field" is
the honest minimum viable shape, not a document-ingestion pipeline with chunking and embeddings, unless
this item's own investigation finds that minimum genuinely insufficient for a real answer quality bar.
Start narrow; a richer knowledge-base format is a real, separate future item if the narrow one proves
too limited, not assumed necessary up front (`CLAUDE.md`'s premature-generalization caution, applied
here to knowledge-base tooling instead of code).

**The low-confidence escape.** `adr/0065`'s own "an unreachable module degrades to the escape to an
operator" covers network/availability failure. A module that is *reachable* but *unsure* — the LLM
itself signals low confidence, or the question is plainly outside what the tenant's knowledge base
covers — needs the identical escape, triggered by the module's own judgment rather than a timeout. This
is new behavior this item has to build and test, not something that falls out of `20-07`'s own contract
for free; state explicitly how the module signals "I don't know, hand this to an operator" over the
wire, since neither `ModuleWireContract` nor `ModuleTaskContracts` (Calendar's own two files) had a
reason to need that signal before this item.

**Where the module's own backend lives.** A real, open decision — a new lightweight repository (the
same "own repository, own deploy" shape Calendar has, scaled down since this module has no tenants,
workers, or availability model of its own to justify a full second product's worth of infrastructure),
or a smaller service folded into an existing deployment. Decide and record before writing code, the
same way `14-02`'s tenant-routing question was decided explicitly rather than assumed.

## Scope

- The knowledge-base storage/format decision above, made and recorded.
- The module's own implementation of `ModuleWireContract`'s two endpoints (start, reply), the identical
  shape `Ago.Calendar.Api/ChatModule/ChatModuleTaskEndpoints.cs` already implements for Calendar — this
  item's own module is a second, independent implementer of the same interface, not a fork of
  Calendar's code.
- A visitor-typed trigger command (`/faq`, `/помощь`, or whatever the tenant's own registered trigger
  words are) that starts the task — reusing `20-07`'s own registry and trigger-matching mechanism
  unchanged.
- The low-confidence escape, designed and tested as its own real behavior.
- A console-facing configuration screen where a tenant supplies/edits their own knowledge-base content
  and registers the module for their site — the `EnableModuleForSite` use case `20-07` already built,
  reused, plus whatever UI the knowledge-base format needs.

## Out of scope

- Live external data of any kind (product stock, pricing) — that is kind 4 (`docs/adr/0078`), not this
  item; this module answers from the tenant-supplied knowledge base alone.
- Order-taking or any action beyond answering a question — this module only ever produces text
  responses through the same primitive vocabulary Calendar already renders, never a `confirmation_card`
  that commits to anything.
- A document-ingestion pipeline (PDF upload, website crawling) for the knowledge base, unless this
  item's own investigation finds the narrow "paste text" shape genuinely insufficient — named above,
  not assumed.

## Done when

- [ ] A visitor asking a question the tenant's knowledge base actually covers gets a correct, grounded
      answer through a real conversation, on the widget and proven over at least one text-only channel
      (matching `20-07`'s own "not secretly widget-shaped" bar).
- [ ] A visitor asking something the knowledge base does not cover gets the low-confidence escape to an
      operator, proven by a test, not by inspection.
- [ ] `Ago.Chat.*` gains zero new type references and zero new string literals of this module's own key
      — proven by the identical guard 1/guard 2 tests `20-07` already built, run again unmodified
      against this second module, the direct evidence for or against `adr/0065`'s own generalization
      bet.
- [ ] The knowledge-base storage decision and the module-hosting decision are both recorded, the same
      way `14-02`'s tenant-routing decision is recorded in its own file.

## Open questions

The knowledge-base format and the module's own hosting location, both named above as this item's real
decisions to make, not questions to leave for a future session.
