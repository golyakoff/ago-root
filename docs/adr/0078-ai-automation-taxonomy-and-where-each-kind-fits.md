# 0078: AI automation is several different capabilities, not one feature, and most of them fit the existing module contract unchanged

## Status

Accepted

## Context

`ago-business/docs/decisions/0009` named AI automation as the largest, riskiest gap against Jivo and
deliberately did not turn it into a backlog item — "too large and too early to estimate without real
customer demand for it specifically." `ago-business/docs/decisions/0010` reverses that specific call:
the author decided to scope real work now rather than wait for a demand signal. This ADR is the
engineering side of that reversal — not a re-litigation of whether to build AI features (that question
is `0010`'s), but of *what kind of AI feature* means what, and which of those kinds this project can
build without breaking what `adr/0065` already decided.

Jivo's own example, quoted directly (`ago-business/decisions/0009`'s own source): a visitor asks
whether a specific TV model is in stock and whether a discount applies; the bot answers with a live
price and stock check and offers to place the order. That single example already names three distinct
capabilities bundled together — answering from a knowledge base, answering from *live, external* data
the shop owns, and *acting* (starting a checkout) — and they carry three different risk profiles.
Treating "AI automation" as one feature is exactly the framing that made `0009` call the whole thing
too large to scope; splitting it is what makes parts of it scopeable now.

`adr/0065`'s own boundary is the constraint every kind below has to fit inside without exception:
`Ago.Chat.*` carries a `moduleKey`, a `task` id and a `step`, and never opens what a module's payload
means. That boundary was chosen so a module — Calendar today, potentially others later — can exist
without Chat's own code growing per-module branches, and `20-07`'s guard 2 (`ModuleKeyLiteralRule`)
enforces it at build time, not just by convention. An AI capability that needs Chat to understand
*anything* about products, orders, or a specific business's own domain would be the same mistake
`adr/0065` already named and rejected once (intent detection living in Chat) — recommitted at a larger
scale.

## The five kinds, ordered by risk and by how cleanly each fits the existing boundary

### 1. Operator reply-draft assist ("copilot") — lowest risk, no architecture change

An LLM call, given the conversation's own history, drafts a suggested reply into the composer for the
*operator* to read, edit, and send — or discard. The visitor never sees anything the operator did not
choose to send. This is the one kind that needs no module contract, no new port, and no change to
`adr/0065`'s boundary at all: it is console-side UX calling an LLM with context the console already
has (the conversation's own message history, already visible to the operator), the same trust level as
`18-03`'s canned responses — a convenience typed into the composer, not a channel to the visitor.

**Hallucination risk is structurally bounded, not eliminated**: a wrong suggestion costs an operator a
few seconds of judgment, never reaches a customer directly. This is the correct first AI feature for
exactly the reason `0009` gave for deferring the larger initiative — it is the one kind cheap enough to
build without first solving hallucination-that-reaches-a-customer, because it never reaches one.

### 2. Automatic conversation categorization — lowest risk, feeds `18-11`'s own reporting gap

An LLM call, run asynchronously after a conversation closes (or periodically over recent ones), assigns
one or more of the site's own existing tags (`18-04`) rather than inventing a new taxonomy. Same
non-customer-facing safety property as kind 1 — the output lands in a database column an operator can
correct, never in a message a visitor reads. This is named here because `18-11`
(`docs/backlog/18-11-conversation-topic-and-tag-breakdown-report.md`) needs a real topic signal to be
worth building, and manual-only tagging (`18-04`'s original scope) means most conversations stay
untagged in practice — the same "nobody fills in optional metadata" problem every product with an
optional tag field eventually hits.

### 3. FAQ / knowledge-base bot — moderate risk, fits the module contract as written

A visitor's routine question (return policy, business hours, shipping cost) gets answered by an LLM
grounded in a knowledge base the tenant supplies — no live external system, no order-taking. This is
the first kind that talks to a visitor directly, so hallucination now has a real cost, and it is the
first kind that is genuinely a **module** in `adr/0065`'s own sense: Chat routes to it exactly the way
it routes to Calendar today (a `moduleKey`, a wire contract, primitives it already knows how to
render), and Chat's own code needs zero changes to support it beyond registering a new `moduleKey` —
`20-07`'s architecture already generalizes to "any module," not just Calendar, which is the whole
argument `adr/0065` made for the closed-vocabulary design in the first place.

**What is genuinely new**: the knowledge base itself (what grounds the answer) and the escape path when
the bot is not confident — `adr/0065`'s own "an unreachable module degrades to the escape to an
operator" already covers "the module is down"; a *low-confidence* answer needs the identical escape,
triggered by the module's own judgment rather than a network failure, which is new behavior worth its
own Done-when when this is actually built, not assumed to fall out of the existing contract for free.

### 4. Product / inventory Q&A — the literal Jivo example, higher risk, needs a port that does not exist yet

Answering "is X in stock, does a discount apply" needs *live* data from a system this project has
never touched: the shop's own product catalog and pricing, which lives in whatever the shop's own
platform is (a real e-commerce backend, a spreadsheet, a 1C instance — unknowable in general, and
exactly why `0009`'s Level 4 (CRM-depth) was rejected: 50+ point integrations is a different, larger
product).

**The shape that keeps this from becoming Level 4 anyway**: the same module contract as kind 3, with
one addition — the module (not Chat) owns whatever catalog integration a given tenant needs, and Chat
only ever sees the closed primitive vocabulary it already renders (a `choice_list`, a `confirmation_card`
with a price and a stock count). A "Catalog module" that one tenant's own integration implements is
architecturally identical to Calendar; a "AGO builds and hosts 50 e-commerce platform integrations" is
Level 4 by another name. This ADR names the shape and does **not** cut a backlog item for it — no real
integration target exists to build against yet (the same "nothing to plug into" gap `14-08`'s own
report named for a different reason), and building the module-side plumbing speculatively, before a
real catalog to integrate with exists, is exactly the premature generalization `CLAUDE.md` already
warns against.

### 5. AI-triggered booking (no `/booking` command typed) — higher risk, explicitly sequenced behind `20-07`'s own live verification

`0009` already named this and its own sequencing rule directly: "a natural continuation of `20-07`'s
manual `/`-command scenario, but *after* the manual path is live-verified, not instead of it." Nothing
in this ADR changes that ordering. Architecturally, this is a form of intent detection — recognizing
"I'd like to book" without an explicit trigger word — which is precisely what `adr/0065` decided does
**not** belong inside `Ago.Chat.*`. The shape that respects the boundary: a component *outside* Chat's
own core (a pre-processing step, or an operator/AI-assist surface that offers to trigger the module on
the visitor's behalf, closer to kind 1's "suggest, human confirms" shape than to a fully autonomous
bot) decides intent and then emits the exact same explicit trigger `20-07` already built — Chat's own
contract does not grow a second, fuzzier invocation path alongside the deterministic one.

### Explicitly out of scope, permanently, not just "not yet": AI processing payment or completing an order

The "Оформить заказ?" step in Jivo's own example is a checkout, and a checkout is a financial
transaction this project has never touched and has no reason to start touching now — `0009`'s Level 4
rejection (CRM/e-commerce depth is a different product) applies with even more force to actually moving
money. The correct shape, if kind 4 is ever built for real, is the module handing back a link to the
shop's *own* checkout (the same non-answer Calendar gives Chat about who confirms a booking, `20-08`'s
own open question) — never AGO Chat or an AGO-built module initiating a charge.

## Decision

Build kinds 1 and 2 now — no architecture change needed, no customer-facing hallucination risk, and
kind 2 directly unblocks a real reporting gap (`18-11`). Scope kind 3 as a real, buildable item now
that a knowledge-base module is a genuine instance of the module contract `20-07` already built, not a
new architectural surface. Name kinds 4 and 5 here, in this ADR, with their real prerequisites (a
catalog integration target for 4; `20-07`'s own live verification for 5) — do not cut backlog items for
either until those prerequisites are real, matching this project's own "decide it here rather than
letting a future test failure decide it" discipline. Payment/checkout automation is rejected outright,
not deferred.

## Consequences

- Three new backlog items land in a new **Stage 19** (`19-01` reply-draft assist, `19-02` automatic
  categorization, `19-03` FAQ module) — Stage 19 was reserved, unplanned, in the `ago-chat`/
  `ago-platform` number range since Stage 10 froze it open; AI assistance is Chat-side work through and
  through, so it is the natural stage rather than inventing a new number.
- `18-11` (topic/tag breakdown report) gains a real dependency on `19-02` landing first for the
  breakdown to be more than "whatever operators bothered to tag by hand" — stated in `18-11`'s own
  file, not assumed silently.
- `20-07`'s module contract is now confirmed to generalize beyond Calendar - the first real evidence
  for or against `adr/0065`'s own bet that a closed vocabulary would not need to grow per-module.
  `19-03`'s own implementation is where that bet gets tested a second time, independently of Calendar.
- No new personal-data surface is created by kinds 1-2 that `docs/architecture/personal-data.md` does
  not already cover (message content already flows through the system these features read from); kind
  3's knowledge base is tenant-supplied content, not personal data about a visitor, and needs its own
  row in that document once `19-03` is actually built, not speculated about here.
