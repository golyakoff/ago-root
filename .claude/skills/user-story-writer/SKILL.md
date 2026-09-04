# Writing user stories for the design pass

Turns what the product *does* into what a person is *trying to get out of it*, in a form a designer
can act on and an author can check afterwards. The output feeds a design tool
(`docs/design/flows.md` and `ui-inventory.md` are its two inputs).

**Use this when** a role's flows are about to be redesigned, a new surface is being scoped, or a
finding needs to become something design can act on. **Not** for backlog items — those go in
`docs/backlog/` and answer "what do we build". A user story answers "what is this person trying to
achieve, and how will we know they did".

---

## 0. Before writing anything: state the role's objective function

**A story without a stated objective is a screen description with a person's name attached.** Every
role is optimising for something, the product is optimising for something, and where those two
diverge is where the design decisions actually live.

Write the objective for the role **first**, in the role's own terms, then the product's, then name
the tension. Example, filled in by the author for the visitor:

> **The visitor wants** their question answered, or a slot at a time that suits them, with the least
> effort and no commitment they will regret.
> **The product wants** them to (1) start talking at all, (2) invest a little attention, (3) book,
> and (4) if they will not book now, leave a name and a phone so the conversation is not lost.
> **The tension**: every step that serves (2)–(4) adds effort the visitor did not ask for.

Get this written down and agreed before drafting stories. If the author has not stated it, ask —
guessing an objective function is how a design pass produces confident work in the wrong direction.

### The objectives already stated for this product

Carry these forward rather than re-deriving them, and extend them when the author says more.

- **Visitor** — as above: interest, a small investment of attention, a booking, and failing that, a
  way to reach them later.
- **Chat operator** — the work must be *comfortable to do* and *uncomfortable to fake*. Both halves,
  and the second is about transparency of process, not surveillance. See the trap below.
- **Calendar operator** — capacity is the unit of work, and the expensive moments are the ones that
  affect a customer who already booked.
- **Tenant** — must be able to see whether the product is making them money, **honestly**, including
  when it is not; and be helped to make it pay better. Retrospective analytics *and* forecasting
  ("what happens if we add this?"). Conversion is the number they care about, so the operators'
  results and the tools that watch that work are what they are buying. The interface must look
  **grown-up**: they are spending money and want to see they spent it well.
- **Platform owner** — few people, rare actions, irreversible and cross-tenant. Legibility and
  confirmation over speed.

---

## 0.5. Whose interest wins — the optic

**Stand in the role's shoes and argue for them. But their interest is served only as far as it
coincides with the tenant's, because the tenant is the one paying. And the tenant's is served only as
far as it stays commercially viable for the platform owner.**

Nested, and stated in that order deliberately:

```
visitor / operator interest  ⊂  tenant interest  ⊂  platform-owner commercial viability
```

This is a **tie-breaker for genuine conflicts**, not a licence, and the difference decides whether it
makes the product better or worse. Two things bound it.

### The floor does not move

Section 1's rules — honesty, and persuasion-not-manipulation — are **not** subject to this ordering.
"The tenant wants more conversions" never authorises invented scarcity, and "the platform needs the
revenue" never authorises flattering a tenant's numbers. The hierarchy decides *whose interest wins
when they genuinely conflict*; it does not decide whether to be truthful, because a product that
resolves that question by hierarchy has no floor at all.

### Measure the interest over the relationship, not the session

**Most apparent conflicts dissolve at the right horizon, and this is the part worth being rigorous
about.** A visitor pushed into a booking they regret cancels, tells somebody, and does not come back
— the tenant loses twice. An operator squeezed by a metric games it, and the tenant's conversion
numbers stop meaning anything. A tenant charged for something that does not pay off churns, and the
platform owner loses the account.

So before invoking the hierarchy, **check whether the conflict survives a longer horizon.** Usually
it does not, and the story is simply better for everyone. When it *does* survive — those are real,
and they are exactly what the ordering exists for.

The ones that genuinely survive tend to look like this, and a story should say so plainly rather than
pretend the interests align:

- The visitor would prefer to book without leaving a phone number. The tenant cannot run a business
  on unreachable bookings. **Tenant wins**, and the story's job is to make the cost worth it to the
  visitor rather than to hide it.
- The operator would prefer their slowest days not to be visible. The tenant is buying visibility of
  exactly that. **Tenant wins**, and the story's job is to make the measure fair and the operator the
  first to see it.
- A tenant wants a capability that costs more to run than their plan brings in. **Platform owner
  wins**, and the honest form is to say so and price it, not to build it and absorb the loss quietly.

### What this asks of every story

Name the conflict, or state that there is none. **Silence is a claim** — that the interests align —
and it will be checked. Where a conflict exists, say which layer won and what was done to soften the
cost to the layer that lost. A story in which the visitor always wins is not advocacy, it is a story
that has not been thought through commercially; one in which they never do is a product nobody
returns to.

---

## 1. The two hard rules

### Honesty is not negotiable, and it is also the strategy

The tenant is being shown numbers about their own money. **Never inflate, never flatter, never hide
the bad case.** A dashboard that only ever shows good news is not read as good news; it is read as
marketing, and then *none* of the numbers are believed — including the true ones that would have
kept the customer.

So: show the unfavourable result plainly, attribute honestly (say what the product did and did not
cause), and label every projection as a projection with its assumptions visible. **A product that
tells a tenant "this is not paying off for you yet, and here is why" earns the right to be believed
when it says the opposite.**

The same rule applies to the visitor. "Usually replies in 5 minutes" is a **promise**. Show it only
if it is derived from real recent data, and stop showing it when it stops being true.

### Persuasion, yes. Manipulation, no. The line is consent.

The visitor objectives above are persuasion goals, and that is legitimate: helping somebody do a
thing they came to do is the job. The line is whether the technique works **because the person
understood**, or **because they did not**.

Never write a story that requires any of these, and reject one that arrives with them:

- **Invented scarcity or urgency** — "3 people are viewing this slot", countdown timers on nothing.
  If a slot really is the last one that week, say so; that is information, not pressure.
- **Confirmshaming** — a decline button that reads "No thanks, I like waiting on hold".
- **Pre-ticked consent**, bundled consent, or consent that is hard to withdraw. In this product's
  market that is also a legal matter, not only an ethical one.
- **A hidden or late-revealed cost or commitment.**
- **Making the exit hard to find** — a widget that cannot be closed is a widget that gets blocked.
- **Fake presence.** The visitor **must not have to care** whether a reply was written by a person,
  and **must not be led to believe somebody is sitting there** when nobody is. Those are two
  different things and only the second is a lie. The need underneath is that the visitor believes an
  answer is coming — so whatever is promised must be kept, and a promise nobody will keep out of
  hours is the manipulation, not the phrasing.

**The test:** if this technique were explained to the visitor afterwards, would they feel helped, or
worked on?

---

## 2. A story says what the person must be able to and want to — never how it looks

**This is the boundary the whole skill turns on, and it is easy to cross without noticing.**

A user story states the *person's* side: what they must be able to do, what they must want to do, and
what they must never be made to want or do. **How that is achieved on screen is the designer's
answer, not the story's.** A story that specifies a form, a panel, a label or a colour has taken the
design decision and left the designer transcribing.

The author made this correction explicitly, and it also resolves a contradiction: `flows.md` and
`ui-inventory.md` both refuse to recommend, on purpose. A story that prescribed layout would smuggle
back in what those two documents deliberately keep out.

### The author's own annotations, read correctly

| `flows.md` had | What the annotation actually establishes |
|---|---|
| "Open question — how the widget *looks* after an offline auto-reply; the two states look alike." | **Must want to**: write at all, believing an answer is coming. **Must not be made to feel**: out of contact, or that they have reached a closed door — "we are shut, we will reply in the morning" costs the conversation before it starts. **Must not have to care** whether the reply came from a person or not — so the distinction must not be forced on them. **Must be able to**, when it is out of hours and nothing can be resolved: leave the question *and* a way to be reached, and believe somebody will come back. |
| "Whether the widget makes the history discoverable, or shows an empty box, is undesigned." | **Must be able to** see that what they said before is still there and the operator has it. **Must not be made to** repeat themselves — and, just as costly, **must not be left wondering whether to**. The uncertainty is the damage, not only the repetition. |

Notice what is *not* in the right column: no form, no placement, no wording. "Leave a name and a
phone" is the author's own suggested practice and it belongs in the story as **the author's
suggestion, clearly labelled** — not as a requirement. The requirement is *a way to be reached*.

Two lessons that generalise:

1. **Name the state the person must not be put in.** "Out of contact." "Did I have to say that
   again?" Those can be checked with a real person; "shows an empty box" cannot.
2. **Carry the fallback for when the primary goal fails.** The out-of-hours case is the pattern: the
   booking will not happen now, so the success condition becomes *the contact is kept*, not *the
   booking is made*.

### The line, in one test

Ask of every sentence: **could a designer answer this three different ways and satisfy all three?**
If yes, it is a story. If only one arrangement of pixels satisfies it, you have designed, and you
should either raise the sentence to the need beneath it or move it to the labelled suggestions.

---

## 3. The format

One story per file or per section, in this shape. Keep each under a page — an unread story is worse
than none.

```markdown
### <short name a person would use>

**Role**: visitor | chat operator | calendar operator | tenant | platform owner
**Status**: built | partial | planned      ← from `ui-inventory.md`, not from memory
**Objective served**: which numbered objective from section 0, and whose
**Interest conflict**: none found | <layer that won, and what softened the cost to the layer that lost>

**As** <role>, **I want** <what they are actually trying to do — in their words>,
**so that** <the outcome they get, not the feature they use>.

**The moment this happens.** Where they are, what they were doing before, what they are holding in
their head. On a phone? Mid-task? With somebody waiting?

**Must be able to.** Capabilities, in the person's terms. *A way to be reached*, not *a phone
field*.

**Must want to.** What they have to actually want for this to work, and what makes it wantable
honestly. If the honest version is not wantable, that is a finding about the product, not a brief for
better wording.

**Must not be made to want or do.** The boundary. Includes both manipulation (section 1) and ordinary
disrespect — repeating themselves, re-deciding, wondering whether something registered.

**Must never happen.** The failure that costs the relationship, not the pixel.

**The author's own suggestions, if any.** Verbatim, and labelled as suggestions rather than
requirements, so a designer can improve on them without appearing to disobey.

**When the primary goal fails.** What still counts as a good outcome, and what the product does to
get it.

**How we know it worked.** One observable thing. A number, a proportion, or an event that either
happens or does not. If it cannot be stated, the story is not finished.

**What already exists.** Cite `ui-inventory.md` — the route, the states it has, the states it lacks.
Never assert a screen exists without it.

**Open questions for the author.** Only genuine forks where different answers give different designs.
```

### On "How we know it worked"

This is the field that separates a story from a wish, and the one most often fudged.

- Prefer an outcome the *visitor or operator* experiences over one the business experiences.
  "Proportion of conversations where the visitor sent a second message" beats "engagement".
- **A metric becomes a target and then gets gamed** — this is the operator trap below. Prefer
  measures nobody can improve without doing the real work.
- If the honest answer is "we cannot measure this yet", write that. It is a finding.

---

## 4. Traps this product has already walked into

**Absent and forbidden look identical.** Screens appear and disappear by permission, so a person who
lacks a grant sees exactly what a person for whom the feature does not exist sees. That is how
`22-14` was found. Any story about a gated surface must say what the person sees when they are *not*
entitled — "nothing" is a decision, and usually the wrong one.

**Errors here are ordinary outcomes of correct use.** The schedule re-cut that conflicts, the grant
that lapsed, the verification code that did not arrive, the confirm that went stale. Each is a
person doing the right thing and being told no. A story that covers only the happy path has skipped
the majority of this product's difficult design.

**Three of the five roles are often one person.** A one-chair salon owner is tenant, chat operator
and calendar operator, on a phone, between customers. Write at least one story from that person's
day, or the design will be right for the largest customers and wrong for the first ones.

**One login, two products, and the customer must not be able to tell.** Never write a story that
requires the visitor or the tenant to know that chat and the calendar are different systems.

**The operator objective has a sharp edge.** "Uncomfortable to fake" must be built as *the honest
path is the easy path* and *the work is visible*, never as surveillance. Two specifics:

- **Measure outcomes, not activity.** Count resolutions, first-response time, whether the visitor
  came back — not keystrokes or messages sent. Activity metrics are trivially gamed and they punish
  the operator who solved it in one good answer.
- **The operator sees their own numbers first, and the same ones their tenant sees.** A metric an
  operator learns about from their manager is a metric they will manage rather than work to.

---

## 5. The back-propagation check — run it before handing anything over

Invented by the author, and it is the cheapest quality gate here.

Take the finished story back to the source material and ask: **would this story have produced the
author's own annotation?** If `flows.md` says a state is undesigned and the story only says it ought
to be designed, it has added nothing. It has to arrive at what the person must be able to and want to
— *believe an answer is coming; not have to care whether a human sent it; be reachable later* — or at
a clearly-argued different account of the same moment.

Then the second half of the check: **does any sentence answer "how does it look"?** If so, cut it or
raise it to the need beneath it. Arriving at the author's practices word for word is a sign of the
first kind of failure, not success — they are one designer's answer, and the story is meant to admit
more than one.

Then, one further pass: **read the story as the person in it.** Not as its author. Where would they
hesitate, and what would they assume? Those two answers are usually the story's real content.

---

## After writing

- Put the stories in `docs/design/`, beside `flows.md` and `ui-inventory.md`.
- **Mark status from `ui-inventory.md`, never from memory.** A story about a screen that does not
  exist is a proposal; a story about one that does is a critique. A reader who cannot tell them apart
  cannot use either.
- Anything you discovered that is a defect rather than a design question goes to `docs/backlog/` as
  its own item, with its own number — not buried in a story. `22-22` is the example: the interface
  inventory found a broken embed snippet, and it became a ticket rather than a paragraph.
- If the objective function had to be guessed rather than stated, say so at the top. That is the one
  thing a reader must not have to reverse-engineer.
