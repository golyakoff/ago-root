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
- **Fake humanity.** Making an automatic reply read like a person is good; letting a person believe a
  *human is present* when nobody is, is not. The author's own instruction — do not label
  "offline/online", do not visually split robot from human — is about **not making the visitor feel
  out of contact**, not about pretending somebody is there. A story must say what the visitor is
  promised, and that promise must be kept.

**The test:** if this technique were explained to the visitor afterwards, would they feel helped, or
worked on?

---

## 2. What the author's own corrections teach — the shape to aim for

The author annotated two bullets in `flows.md`, and the difference between what was there and what
they added is exactly what this skill exists to produce.

| The flow document said | The author added |
|---|---|
| "Open question — how the widget *looks* after an offline auto-reply; the two states look alike." | Do not let the person feel out of contact. "We're closed, we'll answer in the morning" pushes many out of starting at all. Do not visually split robot from human; do not write offline/online. Make the automatic reply as human as possible; try to resolve without an operator; and if it is out-of-hours and unresolvable, **take the question, ask for a name and phone, and promise a call back** — otherwise they do not return. |
| "Whether the widget makes the history discoverable, or shows an empty box, is undesigned." | It must. The visitor has to see the operator is in context. **Nothing is as annoying as repeating what you already did because it vanished** — and even the *uncertainty* "should I repeat this?" costs loyalty. |

Two lessons, and they generalise:

1. **A story names the feeling to avoid, not only the state to render.** "Out of contact." "Did I
   have to say that again?" Those are testable with a person in a way "shows an empty box" is not.
2. **A story carries the fallback for when the primary goal fails.** The author's out-of-hours case
   is the whole pattern: the booking will not happen now, so the story's success condition becomes
   *the contact is kept*, not *the booking is made*.

---

## 3. The format

One story per file or per section, in this shape. Keep each under a page — an unread story is worse
than none.

```markdown
### <short name a person would use>

**Role**: visitor | chat operator | calendar operator | tenant | platform owner
**Status**: built | partial | planned      ← from `ui-inventory.md`, not from memory
**Objective served**: which numbered objective from section 0, and whose

**As** <role>, **I want** <what they are actually trying to do — in their words>,
**so that** <the outcome they get, not the feature they use>.

**The moment this happens.** Where they are, what they were doing before, what they are holding in
their head. On a phone? Mid-task? With somebody waiting?

**What must be true for this to feel right.**
- …
- …

**What must never happen.** The failure that costs the relationship, not the pixel.

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
author's own annotation?** If `flows.md` says a state is undesigned and the story only says it should
be designed, the story has added nothing. It has to arrive at the *instruction* — do not split robot
from human; take the question and ask for a phone — or at a clearly-argued different one.

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
