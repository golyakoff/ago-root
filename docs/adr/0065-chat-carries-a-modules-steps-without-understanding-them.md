# ADR-0065: AGO Chat carries a module's steps without understanding them

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 14/20 (decided ahead of both, because it shapes how each is built)

## Context

AGO Chat is the platform's main conveyor: a dialogue between a person and an operator, over whatever
channel — the widget today, SMS and Telegram at Stage 14. AGO Calendar is not the only thing people
will want to *do* through that dialogue. A visitor who wants an appointment, and later a visitor who
wants a ride or a delivery, all arrive through the same conversation.

The obvious shape is the wrong one. If `Ago.Chat.*` learns what a booking is — a slot, a service, a
reschedule — then every product after Calendar gets written into it too, and the product that was
supposed to be a conveyor slowly accumulates other products' domains. `adr/0027` already refused the
mirror-image version of this (Calendar does not reuse Chat's `Operator` row), and
`clean-architecture.md` names premature generalisation as the failure mode of shared layers.

So the question is not *whether* Chat learns that Calendar exists. Something has to connect the two,
and that something is the site owner switching a module on. The question is **exactly what Chat is
allowed to know**, and where the boundary is enforced rather than merely intended.

One constraint makes this sharper than a normal extensibility problem: **the widget is one renderer
among several, and SMS cannot render anything.** Any design where a module ships its own UI is a
design that works on exactly one channel. The channel matrix — module × channel — is the thing that
kills schemes of this kind, and it has to be answered in the design rather than discovered later.

## Decision

### 1. Chat handles three nouns, none of which is about booking

- **`moduleKey`** — an opaque string.
- **`task`** — something started inside this conversation. Chat holds an id and whether it is open.
- **`step`** — a content kind, an opaque payload, and first-class actions.

**Chat never opens the payload.** Calendar can rewrite half its model tomorrow and not one line of
`ago-chat` changes. Multi-step state belongs to the module, keyed by its own task id; Chat's
per-conversation ordering guarantee (`concurrency.md`, non-negotiable rule 6) applies to the steps for
free.

### 2. Knowing a module is enabled is data, not code

"Site X has a module with key K" is a row. There is no `using Ago.Calendar` and no `"calendar"`
literal in `Ago.Chat.*`. Complete ignorance of a module's *existence* is not a goal — it is an
impossibility, because somebody has to connect the two, and that somebody is the site owner.

### 3. The mechanism already exists

`adr/0061` (`14-06`) gave a message structure Chat does not understand: kind, opaque payload,
first-class actions. Modules use that, not a second mechanism built beside it.

### 4. The primitive vocabulary is closed, and Chat owns it

Chat defines a small set — a choice list, a form, a confirmation card, a date-and-time picker.
Modules **fill them in**; modules do not define kinds of their own.

The reason is the channel matrix. With a closed vocabulary the widget is written once and does not
grow per module, and SMS and Telegram support every module **for free**, because each primitive has a
text rendering ("for an appointment, reply 2"). With open kinds, every module needs a renderer in
every channel — a multiplication, and the thing that kills designs like this one.

The open-kind variant is **deferred, not refused**. It opens when the ceiling meets a concrete need,
and then the rich kind ships as a separately, lazily loaded bundle so the base widget stays its
current size.

### 5. A module may push a step with nothing prompting it

"Your driver is assigned", "your appointment is tomorrow". This is an integration event through the
outbox (non-negotiable rule 4), not request/response. Chat's consumer materialises it as a message in
the conversation.

### 6. No intent detection in v1

Module enabled means the entry point is always present. "Chat should expect a booking request rather
than chatter" is precisely domain knowledge; smartness arrives later and not inside Chat — either the
module subscribes after the visitor has explicitly entered a task, or a separate resolver is itself
asked and answers with a `moduleKey`, never with "the visitor wants an appointment".

### 7. Turn routing, as a principle

At most one active task per conversation. While it is active, input goes to the module. **An operator
may intervene at any moment**, and an escape to a human always exists and **cannot be suppressed by
the module**. This is policy about dialogue rather than about booking, which is why Chat is entitled
to hold it.

### 8. There is no module runtime

No discovery, no sandboxing, no versioning, no third-party publication. Calendar is the sole
implementation and is wired statically. The seam is real and tested; the machinery waits for a second
candidate that actually exists. "Module" is used in code — `moduleKey` — and "plugin" is not, because
it promises an ecosystem this is not.

### 9. Three guards, so that the boundary is enforced rather than intended

- The IL scan from `14-06`: `Ago.Chat.*` names no other product's domain.
- A bundle-input check: the base widget bundle has **zero** inputs from module directories — the same
  technique that separated `demo-boot.js` from `ago-chat.js`.
- **New:** a check for string literals of known module keys inside `Ago.Chat.*`. This is the one gap
  the IL scan cannot see — `if (moduleKey == "calendar")` compiles to a string, not a type reference —
  and it is the cheapest way to shortcut the whole design under time pressure.

## Consequences

`ago-calendar` stays a separate product with its own console and its own hosts. **`adr/0027` is not
weakened**: Calendar gains a *second* surface rather than replacing its first, and its `Operator`,
`Worker`, `Customer` and `Event` remain its own.

Expressiveness is capped on purpose. A week grid or a map is not expressible in the closed vocabulary,
and if Calendar's real flow needs one, that is the trigger for the deferred variant — a measured
trigger, not a mood.

Chat is deliberately not smart in v1. A visitor who types "I'd like to book" gets no special
treatment; they use the entry point like a menu.

`20-06` is being built **outside** this seam and is not blocked by this ADR. Its result is the first
implementation, and a follow-up item moves it behind the contract. Designing a seam against a real
flow is more honest than designing it against an imagined one — which is also why several questions
below are left open rather than guessed at now.

The guards cost something to maintain: three tests that fail for reasons a reader has to understand
before they can fix them. That is the intended cost. The alternative — a boundary held by review
attention — has already failed once in this project, on a widget bundle, and was caught by a check
rather than by a reviewer.

## What this ADR does not decide

**Transport: in-process or over the wire.** A package reference gives compile-time checking but
creates a product-to-product dependency, for which `adr/0012` sets no precedent. A wire contract
(HTTP plus events) avoids it, at the cost of contract tests and one network hop in the step path. The
leaning is the wire: most steps run at human pace, and an unreachable module degrades honestly into
the unsuppressible escape to an operator. **To be decided after `20-06`**, against a real flow.

**Who confirms a booking made from a chat conversation.** `adr/0027` is explicit that Calendar has its
own `Operator` and that it is never the same row as Chat's. If a chat operator acts on a booking card,
Calendar has to authorise an identity belonging to another product. This is a **direct tension with a
recorded decision** and is tracked as its own backlog item rather than left implicit here.

**Which primitives the closed vocabulary actually contains.** Deliberately deferred: fixing the set
before `20-06`'s flow exists is exactly the premature generalisation this project keeps naming.

**What a module may observe in a conversation.** That is a personal-data decision
(`personal-data.md`), not an implementation detail.

**What happens to a half-finished task when an operator intervenes.** The principle is decided above;
this detail is not.

**Operator permissions over module actions.** Blocked on the existing open decision in
`authorization.md`.

## Alternatives considered

**"Calendar publishes an API and Chat works out what to call."** The author's own first formulation,
and it inverts the dependency: working out *which* call to make is domain knowledge, merely hidden
inside a call site instead of a type name.

**The contract in `Ago.Platform.*`.** The platform knows about transport and does not know what a
conversation with an operator is. Generalising before the second case is the failure mode
`clean-architecture.md` warns about, and this contract is Chat's domain rather than the substrate's.

**Open kinds with a renderer per product (the deferred variant), adopted now.** It is renderer work
per *module × channel*. Adopting it up front trades the one property that makes SMS and Telegram work
at all for fidelity nobody has asked for yet.

**A real plugin runtime — discovery, sandboxing, versioning.** There is no second candidate. Taxi was
invented in conversation to test the shape and will not be built; inventing a second implementation to
justify an abstraction is the oldest way to get one wrong.

**Chat detects intent and maps it to products.** Rejected for the same reason as the first
alternative, and it is the version most likely to creep back in later, which is what guard 9 exists
to catch.
