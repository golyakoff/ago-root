# AI FAQ / knowledge-base module

- **Stage**: 19 (AI assistance)
- **Status**: built (2026-08-31, `ago-chat#142`, new `ago-faq` repository, `ago-console#80`, not yet
  merged) — see Outcome below for exact scope and the honestly-unmet Done-when boxes
- **Depends on**: `20-07-calendar-becomes-a-chat-module.md` (done) — this item is the second real
  consumer of the module contract `adr/0065`/`adr/0077` built, and the first test of whether that
  contract actually generalizes beyond Calendar or was accidentally Calendar-shaped

## Decided, 2026-08-31 — read before touching Scope below

Three questions this item's own file named as genuinely open, argued through and settled ahead of
writing code, the same discipline `20-07`'s own "Decided in planning" section modelled: reasoning
recorded in full rather than left as a bare conclusion, so a later reader does not have to reconstruct
*why*.

**Knowledge-base storage: a plain text column, one per site, exactly the honest minimum this item's own
text asked for.** No document-ingestion pipeline (PDF upload, crawling, chunking, embeddings) was built,
and no investigation in this pass found the plain-text shape insufficient - there is no real tenant
content yet to test "insufficient" against, so building a richer pipeline now would be guessing at a
need rather than answering one, exactly the premature generalisation `CLAUDE.md` warns against. The
whole knowledge base is passed to the LLM as context on every question - no retrieval step exists
because none is needed at "a few paragraphs" scale (the item's own words); a genuinely large knowledge
base is the concrete, measured trigger a future item would need before chunking/embeddings become
justified, not a mood. Storage lives in `ago-faq`'s own Postgres (`Ago.Faq.Domain.KnowledgeBase`, one
row per `SiteId`, a bounded text field, an `UpdatedAt`) - the module's own data, never Chat's, matching
`adr/0065` decision 1's "Chat never opens the payload" applied one level up: Chat does not hold FAQ's
knowledge base any more than it holds a booking's service catalogue.

**The low-confidence escape: a fifth closed-vocabulary primitive, `PrimitiveKinds.Escalate`, recorded in
full in `adr/0081`.** In short: a module signals "hand this to an operator" through an ordinary step
whose `kind` is `"escalate"` - the identical wire shape every other primitive already uses, recognised
by `RouteConversationToModuleHandler` as a structural string comparison against Chat's own vocabulary,
never by reading what the module's payload means. The task force-closes regardless of the module's own
`complete` flag (`adr/0065` decision 7's "cannot be suppressed by the module", now given a
module-triggered path to the same outcome as the unreachable-module path), and is reported through the
identical `RouteConversationToModuleOutcome.Escalated` value the unreachable case already produces - one
outcome, two roads into it, so a future report asking "was this conversation escalated" already covers
both without knowing there are two.

A **successful** answer does *not* get a sixth primitive. It rides `choice_list` with zero actions and a
`payload.prompt` holding the answer text - a shape `MessageContent`'s own doc comment already documents
and blesses ("a payload with no actions is a card nobody has to answer") before this item ever existed.
Inventing a distinct "plain answer" kind would have been vocabulary growth with no new structural need
behind it - the exact test escalate had to pass and this did not.

**Where the module's backend lives: a new, lightweight repository, `ago-faq`, one host
(`Ago.Faq.Api`), no `Worker`, no `Webhooks`.** It qualifies as its own repository under
`architecture/repositories.md`'s own rule ("only when the thing versions or deploys independently") the
same way Calendar did: it is reachable over its own wire contract, registered per site in Chat's
registry, and has a release cadence of its own. It does **not** get Calendar's three-way host split
(`adr/0013`'s "split by failure profile" reasoning): FAQ has exactly one failure profile (answer an HTTP
request), no outbox-driven async pipeline, no webhook source and no worker loop of its own to justify a
second or third host - building `Ago.Faq.Worker`/`Ago.Faq.Webhooks` with nothing to run in them would be
exactly the premature-generalisation `CLAUDE.md` warns a platform layer against, applied here to a
product's own host count instead.

**Two authentication shapes on `Ago.Faq.Api`, both real, one with a named gap.** The module-task wire
endpoints (`start`/`reply`) are server-to-server and `AllowAnonymous`, the identical shape
`Ago.Calendar.Api/ChatModule/ChatModuleTaskEndpoints.cs` already established and `adr/0077` already
named as a real, open, accepted gap ("no service-to-service authentication exists yet") - extended here
without re-litigating it. The knowledge-base config endpoint (console-facing, operator-authenticated) is
different: it validates the **same** Keycloak-issued operator JWT `ago-chat`'s own console already
obtains - no second Keycloak client was provisioned, because validating a bearer token needs only the
issuer's public signing keys, never a shared secret, so trusting the identical issuer costs nothing new
to set up. This is a real, deliberate difference from Calendar's own separate OIDC client
(`adr/0027`/`adr/0064`): Calendar duplicates its own client because it has a genuinely separate identity
domain (its own `Operator`/`Worker`/`Customer`), while FAQ has none at all - "who may edit this site's
knowledge base" is not a question FAQ's own domain can answer independently, because FAQ has no concept
of a site's operators to begin with. What this endpoint does **not** yet do is re-verify that the
authenticated operator specifically holds `Permission.SiteConfigure` on the site named in the request the
way `EnableModuleForSiteHandler` does inside `ago-chat` - a real, bounded, named gap of the same shape
`adr/0077` already accepted for the module-task endpoints (authenticity is checked; cross-tenant
authorization is not, yet), not silently shipped. Closing it would need either a cross-repository
permission-check call (a new, reversed wire dependency: `ago-faq` calling `ago-chat`) or a
locally-duplicated permission table - both real, larger changes this item's own scope did not ask for
and did not build.

## Context to read first

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
- [x] A visitor asking something the knowledge base does not cover gets the low-confidence escape to an
      operator, proven by a test, not by inspection.
- [x] `Ago.Chat.*` gains zero new type references and zero new string literals of this module's own key
      — proven by the identical guard 1/guard 2 tests `20-07` already built, run again unmodified
      against this second module, the direct evidence for or against `adr/0065`'s own generalization
      bet.
- [x] The knowledge-base storage decision and the module-hosting decision are both recorded, the same
      way `14-02`'s tenant-routing decision is recorded in its own file.

## Outcome

Landed 2026-08-31 across four repositories: `ago-chat#142` (the `Escalate` primitive and
`EnableModuleForSite`'s endpoint mapping), the new `ago-faq` repository (the module's own backend,
initial commit on `main`), `ago-console#80` (the two-panel `/settings/faq` config screen), this
companion doc PR (`adr/0081`, this Outcome).

**Independently re-verified by the managing session, not only reported by the implementing workers**:
`ago-chat` rebased onto `main` (which by then included `14-09`) and its full suite re-run clean,
1805/1805; `ago-faq`'s own suite re-run clean, 61/61, plus one fails-before claim re-proven by hand
(the empty-knowledge-base-escalates check, reverted and confirmed 2 tests go red, restored, full suite
re-confirmed green); `ago-console`'s three checks the implementing worker's own sandbox broke before it
could run itself — `npm run lint` found two real errors (`faqKnowledgeBaseApi.test.ts`'s `vi.spyOn`
typed as `any`, not this codebase's own established `vi.fn()`/`vi.stubGlobal` pattern), fixed and
re-verified; `npm test` 583/583; `npm run build` succeeds.

**A genuine collision, caught before it caused a problem**: this item and `14-09` (running as parallel
background workers) both independently claimed ADR number `0080` for their own decision. `14-09`
merged first, so this item's own ADR was renumbered `0081` throughout — the file itself, every
cross-reference in `ago-chat`'s `PrimitiveKinds.cs`, this backlog file, and five files in `ago-faq`
that cited it — before landing.

**What is honestly not done**: the first Done-when box (a real conversation through the widget, on a
real text-only channel) was out of scope for every worker's own brief and remains unverified — it needs
a live `ago-faq` deployment plus `ago-chat`'s module registry pointing at it, integration across three
repositories no single worker's worktree could exercise. `ago-faq`'s own CI is red on its first run: it
needs the `AGO_PLATFORM_PACKAGES_TOKEN` repository secret (`adr/0018`) that `ago-chat`/`ago-calendar`
already carry — the managing session cannot mint or read that value and has asked the author to add it.
The LLM call itself was never exercised against a real OpenAI-compatible provider, only against an
in-process fake Kestrel host standing in for one (`OpenAiCompatibleFaqAnswerGeneratorTests`, the same
technique `ago-chat`'s own `YandexGptReplyDraftClientTests` established) — no real API key exists
anywhere in this environment. The console's knowledge-base-edit endpoint does not yet re-verify
`Permission.SiteConfigure` on the target site (named and accepted in the "Decided" section above, the
same shape `adr/0077` already accepted for the module-task endpoints).

## Open questions

The knowledge-base format and the module's own hosting location, both named above as this item's real
decisions to make, not questions to leave for a future session — both answered in "Decided" above.
