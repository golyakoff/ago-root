# What people are trying to do, and what must be true for them

Rewritten 2026-09-04 through `.claude/skills/user-story-writer`, from the author's annotations on the
first version. The factual half — every screen that exists today, with its states — is
`ui-inventory.md` beside this file.

**These are stories, not designs.** Each says what a person must be able to do, must want to do, and
must never be made to want or do. **How any of it looks is the designer's answer, not this
document's.** The test applied to every sentence: could a designer satisfy it three different ways?
If only one arrangement of pixels satisfies it, the sentence was cut or raised to the need beneath it.

`built` / `partial` / `planned` come from `ui-inventory.md`, not from memory. A story about a screen
that exists is a critique; one about a screen that does not is a proposal. Do not confuse them.

---

## The optic

Stand in the role's shoes and argue for them — **but their interest is served only as far as it
coincides with the tenant's, because the tenant pays; and the tenant's only as far as it stays
commercially viable for the platform owner.**

```
visitor / operator interest  ⊂  tenant interest  ⊂  platform-owner commercial viability
```

Two bounds, without which that ordering is a licence rather than a tie-breaker:

- **The floor does not move.** Honesty, and persuasion-not-manipulation, are not subject to it. "The
  tenant wants more conversions" never authorises invented scarcity; "the platform needs revenue"
  never authorises flattering a tenant's numbers.
- **Interest is measured over the relationship, not the session.** Most apparent conflicts dissolve at
  that horizon. Each story below states its conflict or states there is none — and **silence is a
  claim that gets checked.**

## The objective functions

| Role | Wants | The product wants |
|---|---|---|
| **Visitor** | their question answered, or a slot that suits them, with least effort and no commitment they will regret | that they start talking at all; invest a little attention; book; and failing that, leave a name and a phone so the conversation is not lost |
| **Chat operator** | to do the work without friction, and to be judged on something they recognise as fair | the work to be comfortable to do and uncomfortable to fake |
| **Calendar operator** | the schedule to reflect reality with the least disruption to people already booked | capacity that is accurate, and changes that do not cost customers |
| **Tenant** | to know whether this is making them money, and to spend well | to be honestly worth keeping — including saying when it is not yet |
| **Platform owner** | to act rarely, safely, and reversibly across tenants | that irreversible cross-tenant acts are legible and confirmed, never fast |

---

# 1. Visitor

The only person here who did not choose this product, does not know its name, and will never see the
console. On **somebody else's website**, usually on a phone, usually with one question or one slot in
mind. Everything below happens inside a `<script>`-tag widget in a Shadow DOM.

## 1.1 Asking a question at all

**Status**: built · **Objective**: visitor (1) — start talking · **Interest conflict**: none found

**As** a visitor, **I want** to ask my question without filling anything in first, **so that** I find
out whether this place can help me before I invest anything.

**The moment.** On a phone, on a shop's page, mid-scroll. They have not decided to be a customer.
Their alternative is closing the tab, and it costs them nothing.

**Must be able to** type a question immediately, with nothing required before the first message; send
an attachment and see whether it arrived; and leave without being pursued.

**Must want to** start, which means believing the effort is small and an answer is coming.

**Must not be made to** identify themselves before they know if it is worth it, or to guess whether
the widget is a live conversation or a contact form.

**Must never happen**: a widget that cannot be closed, or that captures the host page's scroll. It is
somebody else's site; overstaying gets the whole product removed rather than reconfigured.

**When the primary goal fails.** They read and leave. That is a legitimate outcome and must cost them
nothing — an unclosable or nagging widget converts a neutral non-customer into a hostile one.

**How we know it worked.** The proportion of widget opens that reach a first sent message.

**What exists.** `ui-inventory.md` §9: launcher, panel, five message kinds, nine states.

## 1.2 Writing when nobody is there

**Status**: partial · **Objective**: visitor (1) and (4) · **Interest conflict**: none found — the
horizon settles it, see below

**As** a visitor arriving out of hours, **I want** to say what I need and be sure it will be dealt
with, **so that** I do not have to remember to come back.

**The moment.** Evening or Sunday. Nobody is at the console. Everything is the same as 1.1 from the
visitor's side, and they have no way of knowing it is not.

**Must be able to** leave the question and a way to be reached, and believe somebody will come back to
them.

**Must want to** write in the first place — which is what a closed-door message destroys.

**Must not be made to** care whether a reply was written by a person, and **must not be led to believe
somebody is sitting there** when nobody is. Those are two different things and only the second is a
lie. **Must not be** made to feel they have arrived after closing time and should come back later —
they will not.

**Must never happen**: a promise nobody keeps. Whatever the visitor is told will happen, happens.

**When the primary goal fails** — out of hours and nothing can be resolved automatically — the
success condition is no longer *answered*, it is **contact kept**.

> **The author's own suggestions** (verbatim, as suggestions rather than requirements): *"1. Сделать
> ответ робота максимально человечным. 2. Постараться понять — можем ли мы решить вопрос без
> оператора вообще? Если можем — решить его. 3. Если пользователь попал на оффлайн-время, а
> автоматически решить нельзя — он сам уже не вернётся, надо взять вопрос и показать ему форму ввода
> телефона и имени, попросить ввести их и пообещать перезвонить в рабочее время."* And: *"не стоит
> разделять визуально автоответ робота и ответ человека, не стоит писать «оффлайн/онлайн»."*

**How we know it worked.** Of conversations started out of hours, the proportion that end with a
reachable contact **and** are actually followed up in working hours. The second half is not optional:
without it this measures capture, not kept contact.

**Interest note.** The visitor would rather not leave a phone number; the tenant cannot run a business
on unreachable enquiries. Over one session that is a conflict; over the relationship it is not — the
visitor who is called back got what they came for. **Tenant wins**, and the cost owed back to the
visitor is that the promise is kept and the number is used for that and nothing else.

**What exists.** Offline auto-reply (`14-04`). The widget's resting state after one is undesigned, and
today looks identical to a live conversation.

## 1.3 Coming back to a conversation

**Status**: partial · **Objective**: visitor (2) — the attention already invested · **Interest
conflict**: none found

**As** a returning visitor, **I want** to see that what I already said is still there and understood,
**so that** I do not repeat myself and do not wonder whether I should.

**The moment.** Next morning, maybe a different tab or device. They said something yesterday that took
effort to explain.

**Must be able to** see their own previous messages and that the other side has them.

**Must not be made to** repeat themselves — and, **just as costly, must not be left wondering whether
to.** The uncertainty is the damage, not only the repetition.

**Must never happen**: an empty box that implies the earlier conversation is gone when it is not.

**How we know it worked.** The proportion of returning visitors whose first new message restates
something already in the thread. It should fall to near zero, and it is measurable from the transcript
without asking anybody.

> **The author's own annotation**: *"обязательно должен давать! Важно видеть что оператор в контексте
> и не надо повторять — ничто так не бесит как повторение уже сделанного, потому что оно пропало."*

**What exists.** The visitor token renews and lasts seven days (`17-07`, `17-08`), so the history is
there. Whether the widget makes it discoverable is undesigned.

## 1.4 Booking a slot

**Status**: partial · **Objective**: visitor (3) — the booking · **Interest conflict**: real, see
below

**As** a visitor, **I want** an appointment at a time that suits me, **so that** I can stop thinking
about it.

**The moment.** On a phone, possibly standing up, possibly with the shop's own page behind the widget.
They may know exactly who they want, or not care at all.

**Must be able to** find a time without first choosing a person, **and** find a person without first
choosing a time — both, because customers genuinely split on this. Then: confirm the phone number and
finish, without losing what they already chose.

**Must want to** finish, which means the remaining effort is visible and small at every step.

**Must not be made to** decide anything twice, re-enter anything, or discover a requirement after they
have committed attention. **Must not be** shown invented pressure — no "3 people are viewing this
slot", no timers. If a slot really is the last that week, saying so is information; anything else is
manipulation.

**Must never happen**: an unverified booking existing at all. The public endpoint is unauthenticated
by construction — a `Customer` has no account — so the verified phone **is** the identity.

**When the primary goal fails.** No suitable slot, or they stop at verification: the outcome becomes
1.2's — the contact is kept and the shop can call.

**How we know it worked.** Of visitors who select a slot, the proportion that complete verification.
That single number isolates the interruption, which is where this flow actually breaks.

**Interest note.** Phone verification is pure cost to the visitor and the tenant's whole basis for
trusting a booking. **Tenant wins.** What is owed back: it is asked **at the moment it is needed and
not before**, and the interruption is designed for — they leave the browser to read an SMS and must
come back to exactly what they left.

**What exists.** Slots materialised from a schedule template over a horizon. Phone verification by
code. `ui-inventory.md` §9 has the booking primitives. A longer-than-one-slot booking (`20-18`) and
extra verified channels (`20-11`) both reshape this — design once, for both.

## 1.5 Changing a booking

**Status**: planned · **Objective**: visitor — trust that survives the booking · **Interest
conflict**: apparent only

**As** a customer with an appointment, **I want** to move or cancel it without phoning, **so that** I
do not have to schedule a phone call to schedule a haircut.

**Must be able to** reach their own booking from the same place they made it, and change it within
whatever rules the shop sets.

**Must not be made to** feel they are getting away with something, or that cancelling will be held
against them. A cancellation the shop learns about early is worth more than a no-show.

**How we know it worked.** No-show rate. If self-service cancellation does not reduce it, the feature
did not pay for itself and should be said so.

**Interest note.** It looks like the tenant loses bookings. Over the relationship the opposite: an
early cancellation is a slot that can be resold, and a no-show is not. If the data disagrees once it
exists, the tenant wins and the rules tighten — but the honest version is to measure it, not assume it.

**What exists.** Nothing. The only route today is contacting the shop. That is a product decision that
should be made rather than inherited.

---

# 2. Chat operator

Someone doing a job for eight hours. The screen is open all day, so small frictions compound in a way
they never do in a flow used once. **This is also the role where the product's objective has a sharp
edge** — "uncomfortable to fake" is built as *the honest path is the easy path* and *the work is
visible*, never as surveillance.

## 2.1 Knowing what needs them right now

**Status**: built · **Objective**: operator — do the work without friction · **Interest conflict**:
none found

**As** an operator, **I want** to see at a glance what is unanswered, what is mine, and what is going
stale, **so that** I spend my attention on the person most likely to leave.

**The moment.** Between conversations, all day. Sometimes on a phone, because in a small shop the
operator is also the owner and is cutting hair.

**Must be able to** tell those three things apart without reading every row, and act on a waiting
conversation — **which today is impossible: `Waiting` conversations appear in three places and are
actionable in none. No claim or assign action exists anywhere in the product** (`ui-inventory.md` §12).

**Must not be made to** rely on a number that flickers. Unread counts come from a consumer and
presence from Redis; both can be briefly stale, and a count that jitters is worse than one that lags.

**Must never happen**: an ordering that implies a global sequence. Message order is guaranteed **per
conversation, never globally**, so any "everything, newest first" view promises what the system does
not deliver.

**How we know it worked.** Time from a visitor's first message to an operator's first reply. Not
messages handled, not conversations opened — see 2.4.

**What exists.** `ui-inventory.md` §3: the workspace grid, its two breakpoints, the rail, the empty
`/`.

## 2.2 Holding a conversation

**Status**: built · **Objective**: operator; tenant (conversion) · **Interest conflict**: none found

**As** an operator, **I want** to know who else is in this conversation and whether the visitor is
still there, **so that** I do not answer into an empty room or over a colleague.

**Must be able to** see whether the visitor is present, whether their last message was delivered, and
whether anyone else is on this conversation.

**Must not be made to** lose a half-typed reply when they are pulled away, or to re-establish context
they had two minutes ago.

**How we know it worked.** The proportion of conversations with two operators replying within the same
minute — collisions are the observable symptom of not knowing.

## 2.3 One person arriving through several channels

**Status**: partial · **Objective**: operator; visitor (not repeating themselves) · **Interest
conflict**: none found

**As** an operator, **I want** to see the person rather than the channel, **so that** I do not ask
somebody something they told us on Telegram yesterday.

**Must be able to** see that this is the same person, and what they said elsewhere.

**Must not be made to** work it out from an identifier. **And the visitor must not be made to
repeat themselves across channels** — 1.3's rule does not stop at the widget's edge.

**How we know it worked.** Same measure as 1.3, across channels: restatements in a first message after
a channel switch.

**What exists.** Channel-identity linking (`14-12`, `adr/0079`). The data carries the link; the screen
does not foreground it.

## 2.4 Being measured

**Status**: partial · **Objective**: product — uncomfortable to fake; tenant — conversion ·
**Interest conflict**: real, see below

**As** an operator, **I want** to be judged on something I recognise as fair and can see before my
manager does, **so that** I improve the work instead of managing the number.

**Must be able to** see their own numbers, the same ones their tenant sees, **first**.

**Must want to** be measured — which only happens if the measure survives their own scrutiny.

**Must not be made to** compete on things outside their control: who was online when the hard
conversation arrived, or which visitor happened to be easy. **Must not be measured on activity** —
keystrokes, messages sent, conversations opened. Activity metrics are gamed trivially and punish the
operator who solved it in one good answer.

**Must never happen**: a metric an operator first learns about from their manager. That is a metric
they will manage rather than work to, and it destroys the data the tenant is buying.

**How we know it worked.** Whether operators can predict their own numbers before seeing them. If they
cannot, the measure is not legible, whatever else it is.

**Interest note.** The operator would rather their slow days were invisible; the tenant is buying
exactly that visibility, and it is the basis of the conversion reporting they pay for. **Tenant
wins.** What is owed back: the measure is about outcomes for the visitor, it is fair to the shift you
were actually given, and you see it first.

## 2.5 Going offline

**Status**: partial · **Objective**: visitor (1.2) as much as operator · **Interest conflict**: none
found

**As** an operator, **I want** to say I am leaving, **so that** visitors are told the truth and my
colleagues know.

**Must be able to** stop being the person expected to answer, deliberately.

**Must not be made to** just close the tab and hope — which is what happens when the act has no
surface.

**What exists.** Offline auto-reply is configured **per site, not per operator**, so the operator's own
act of leaving has no representation at all.

---

# 3. Calendar operator

A different job from chat, wearing the same login since `22-05`. The unit of work is a week, not a
message, and the expensive moments are the ones that touch a customer who already booked.

## 3.1 Setting up a master

**Status**: built · **Objective**: tenant — capacity that is accurate · **Interest conflict**: none
found

**As** a person setting up the calendar, **I want** to get from nothing to bookable, **so that** the
booking widget has something to offer.

**The moment.** First run, and they have never met the words *template*, *horizon* or *materialised*.

**Must be able to** reach a bookable state without understanding the model first, and find out what is
still missing.

**Must not be made to** learn three concepts at once before anything works.

**Must never happen**: a setup that looks finished and produces no slots.

**How we know it worked.** Of tenants who start setup, the proportion that reach a first bookable
slot, and how long it takes.

**What exists.** `ui-inventory.md` §7 — worker card, schedule template, horizon. A first-run
experience currently shaped like a settings screen.

## 3.2 Re-cutting a schedule that already has bookings

**Status**: built · **Objective**: tenant — changes that do not cost customers · **Interest
conflict**: real, and it is a three-way

**As** a calendar operator, **I want** to change a master's pattern from next month without hurting
the people already booked, **so that** I can fix the schedule without paying for it in customers.

**The moment.** They have decided the change; they are about to find out what it costs.

**Must be able to** see, before committing, exactly what breaks: which days, which bookings, which
customers. **Must be able to** decide **per booking**, not in bulk. **Must be able to** stop.

**Must not be made to** choose blind between two lossy outcomes — today the system offers exactly two
per affected day: cancel the booking, or leave the day in the old grid.

**Must never happen**: a customer losing an appointment without the operator having seen that customer
on screen and chosen it.

**When the primary goal fails** — the world moved while they were deciding — that is an **expected**
outcome, not an error. The system already computes a fingerprint and refuses a stale confirm; the
person needs to be told *what changed*, not that something went wrong.

**How we know it worked.** Bookings cancelled per re-cut. It should fall when moving becomes possible;
if it does not, the preview is not doing its job.

**Interest note.** The customer wants to keep their slot; the tenant wants a schedule that reflects
reality; over a longer horizon a cancelled customer costs the tenant more than the inconvenience of
keeping a day in the old grid. **Nobody wins outright and that is the point** — the story's job is to
put the trade in front of a person with enough information to make it, one booking at a time. Moving
instead of cancelling (`20-17`/`20-29`) is what makes the trade less bad; designing this screen as
though only *cancel* exists would bake in the lossy version permanently.

**What exists.** The operation, and — since `22-20` — sixteen refusal codes that used to be a blanket
500. `ui-inventory.md` §7 notes this screen has a manual **Refresh** button and no polling, on the one
screen where every row carries a deadline.

## 3.3 Booking somebody who called

**Status**: planned (`20-28`) · **Objective**: tenant — capacity used · **Interest conflict**: none
found

**As** an operator with a customer on the phone, **I want** to find or create them and put them in a
slot while still talking, **so that** the call ends with an appointment.

**Must be able to** find an existing customer from a phone number typed mid-sentence, see the whole
grid, and create the customer as part of booking rather than before it.

**Must not be made to** leave the booking to go and create a customer record.

**How we know it worked.** Time from starting to booked, measured in the interface — the caller is
waiting through all of it.

## 3.4 Recording what happened at the visit

**Status**: planned (`20-23`) · **Objective**: tenant — knowing what the product earned ·
**Interest conflict**: real, mild

**As** an operator, **I want** to record the outcome and the takings on the same card as the booking,
**so that** it takes seconds and I actually do it.

**Must not be made to** enter it anywhere other than where they already are, or twice.

**Interest note.** This is data entry that benefits the tenant's reporting, not the operator's day.
**Tenant wins**, and what is owed back is that it costs seconds — a form that takes a minute will be
filled in with fiction, which is worse for everyone than an empty field.

**Open question for the author.** Does an outcome survive a moved appointment, or belong to the visit?
Different answers give different designs; `20-23` flags it and does not settle it.

---

# 4. Tenant

The person who pays. Visits rarely, in a hurry, usually because something is wrong or something new
must be switched on. **Every screen they see is either onboarding or troubleshooting** — there is no
third mode, and treating these as ordinary settings pages is the mistake most worth undoing.

The interface must read as **grown-up**. They are spending money and want to see they spent it well.

## 4.1 Getting from signed-up to working

**Status**: partial — **the weakest flow in the product** · **Objective**: tenant; platform owner
(activation is the whole funnel) · **Interest conflict**: none found

**As** a shop owner who has just signed up, **I want** to end up with a working chat on my own site,
**so that** I find out whether this is worth paying for.

**The moment.** They have paid attention, not money. Between them and value: get a script tag, install
it on a site they may not administer, confirm it works, and invite whoever will answer.

**Must be able to** find out **that it is working**, from their own site, without reading anything
technical. **Must be able to** get help installing it when they cannot do it themselves — a real and
common case, not an edge one.

**Must want to** finish the setup rather than defer it, which means each step visibly ends.

**Must not be made to** guess whether silence means *not installed*, *installed and nobody has
written*, or *broken*.

**Must never happen**: being handed something that cannot work. `22-22` is exactly that — the calendar
embed snippet was broken four ways and one of them failed silently, so the tenant would have concluded
booking was not switched on.

**When the primary goal fails.** They cannot install it. The success condition becomes: **we know
they are stuck**, and can reach them — the same shape as 1.2.

**How we know it worked.** Of tenants who sign up, the proportion whose site sends a first real
visitor message, and how long that takes.

**What exists.** `ui-inventory.md` §2 and §6. `10-06` exists because *the tenant never learns how to
install the widget*.

## 4.2 Switching on the calendar

**Status**: partial · **Objective**: tenant; platform owner (revenue) · **Interest conflict**: real

**As** a tenant, **I want** to understand what changes for me before I turn it on, **so that** I am
not buying a word.

**Must be able to** see what is different afterwards, what it costs, and what they must do next —
because enabling a module is a **before/after**, not a toggle.

**Must not be made to** discover the setup work after committing.

**How we know it worked.** Of tenants who enable it, the proportion reaching a first booking. An
enablement that never reaches one was a sale that did not deliver.

**Interest note.** The platform would like this switched on; the tenant should only switch it on if it
will pay. **Over the relationship these agree**, and the honest form follows: say what it takes to get
value, including the work.

**What exists.** Module enablement (`19-03`, `22-11`). The paid version with a quota is `22-07` —
planned. An owner can grant it without payment (`22-17`) — API only.

## 4.3 Giving a colleague access

**Status**: built · **Objective**: tenant · **Interest conflict**: none found

**As** a tenant, **I want** to give somebody the access their job needs, **so that** they can work and
I have not handed over everything.

**Must be able to** think in jobs and have the system translate to permissions — **the recurring
failure is that permissions are shown as capabilities and understood as job titles.**

**Must not be made to** learn an eleven-permission vocabulary to add a receptionist.

**Must never happen**: a person granted access who sees nothing and cannot tell why. **This is
`22-14`'s lesson generalised: absent and forbidden look identical**, so every gated surface must say
what a person who is *not* entitled sees. "Nothing" is a decision, and usually the wrong one.

**How we know it worked.** Invitations that end in the invited person completing a first action.

## 4.4 Seeing whether this is paying off

**Status**: partial · **Objective**: tenant — the reason they renew · **Interest conflict**: apparent
only, and the resolution is the whole story

**As** a tenant, **I want** to know whether this is making me money, **so that** I can decide to keep
paying or to change how I use it.

**The moment.** Renewal is near, or they are wondering where the month went.

**Must be able to** see what happened — conversations, bookings, what came of them — and **what it is
attributable to**. **Must be able to** ask *what if*: what happens if we add a chair, extend hours,
answer faster.

**Must want to** look at it, which means it must be readable in a minute and not feel like an exam.

**Must not be made to** accept a number without its basis. **Must not be shown** a projection dressed
as a fact: every forecast carries its assumptions, visibly.

**Must never happen**: **inflated, flattered, or selectively-good numbers.** A dashboard that only ever
shows good news is not read as good news — it is read as marketing, and then *none* of the numbers are
believed, including the true ones that would have kept the customer. **The unfavourable result is
shown plainly**, and the product says so when it is not yet paying off, with why.

**When the primary goal fails** — it genuinely is not paying off — the success condition becomes: the
tenant finds that out **from us, early, with a route to improving it**. A customer who leaves knowing
exactly why may come back; one who leaves feeling misled does not, and tells people.

**How we know it worked.** Whether tenants can state, unprompted, what the product did for them last
month. If they cannot, the reporting failed regardless of how good it looks.

**Interest note.** Short-horizon, the platform benefits from flattering numbers. Over the
relationship the reverse, decisively — the floor rule (honesty) is not subject to the hierarchy
anyway, and here it happens to also be the commercial answer.

**What exists.** `ui-inventory.md` §5: `/analytics` and three siblings. Operator identity renders as
eight hex characters, so the reports name operators the reader cannot identify.

## 4.5 Finding out what happened to a message

**Status**: partial · **Objective**: tenant — trust · **Interest conflict**: none found

**As** a tenant whose customer says they got nothing, **I want** to find out whether we sent it,
**so that** I can answer them honestly.

**Must be able to** answer *did it send* without reading a log or asking support.

**Must not be made to** interpret a delivery status that means something only to an engineer.

**How we know it worked.** Support contacts of the form "did this send?" — they should approach zero,
and that is measurable without instrumenting anything new.

**What exists.** Delivery outcomes are recorded. The surface for a non-technical person is largely
absent.

---

# 5. Platform owner

The author, and later whoever runs support. A handful of people doing things that are **irreversible
and cross-tenant**. Volume is low; the cost of a mistake is high. Design for confirmation and
legibility, never for speed.

## 5.1 Seeing every tenant

**Status**: built · **Objective**: platform owner · **Interest conflict**: none found

**As** the platform owner, **I want** an accurate cross-tenant list, **so that** I can find the one I
am being asked about.

**Must be able to** trust that the list is complete. This is the one place a caller's own `site_id`
must be deliberately **ignored** — scoping it would silently return a shorter list, which reads
exactly like a platform with fewer tenants.

**How we know it worked.** It is right, and provably so — `PlatformOwnerAsTenantTests` asserts the
result contains a tenant the caller has no row in.

## 5.2 Granting a product to a tenant without payment

**Status**: built as an API, **no screen at all** · **Objective**: platform owner (sales, support) ·
**Interest conflict**: real

**As** the platform owner, **I want** to give a prospect the calendar for a month, **so that** I can
sell before a payment path exists.

**Must be able to** grant, see what was granted and by whom, and revoke. **Must be able to** state an
end date **or explicitly state there is none** — a grant with no expiry is a discount nobody
remembers giving.

**Must not be made to** believe expiry does more than it does. **`ExpiresAt` binds the granting side
only**: chat stops offering the module the instant it lapses, and **the module is never told**. A
screen presenting expiry as a clean end date would be lying to its own author.

**Must never happen**: this becoming the ordinary path to having a product. Nothing but a Keycloak
realm role gates it, and no write in this codebase grants that role — that is the answer, not an
omission.

**How we know it worked.** Granted trials that convert to payment, against those that lapse silently.

**Interest note.** The tenant would like it free indefinitely; the platform cannot. **Platform owner
wins**, and what is owed back is that the end is stated up front rather than discovered.

**What exists.** `22-17`, `adr/0098` — API only. `/owner` is read-only.

## 5.3 Repairing a tenant

**Status**: partial · **Objective**: platform owner — support · **Interest conflict**: none found

**As** whoever is handling the ticket, **I want** to put right a payment that succeeded and provisioned
nothing, **so that** the customer gets what they paid for today.

**Must be able to** see the tenant's actual state and act on it.

**Must not be made to** write SQL against a live tenant, which is the remedy today.

**Must never happen**: undoing something without seeing it was not yours. Revoke works on a tenant's
**own purchase** as readily as on a grant — an owner can undo something they did not do, and **that
asymmetry has to be visible at the moment of acting**.

**How we know it worked.** Time from support ticket to the customer having what they paid for.

---

## What makes this interface hard, stated once

**One login, two products, and the customer must not be able to tell.** That is Stage 22's premise.
The console is one console; the calendar is a *module* a tenant switches on, and chat never learns the
word "calendar". No story here may require the visitor or the tenant to know they are different
systems.

**Three of the five roles are often the same human.** A one-chair salon owner is tenant, chat operator
and calendar operator, on a phone, between customers. Any design assuming one role per person will be
right for the largest customers and wrong for the first ones.

**Absent and forbidden look identical.** Screens appear and disappear by permission, and "absent" is
the *designed* behaviour for "not granted". Every gated surface owes an answer to *what does someone
without this see*.

**Errors are ordinary outcomes of correct use.** The re-cut conflict, the lapsed grant, the
unverified phone, the stale confirm. Each is a person doing the right thing and being told no.

**Nothing here says how it should look.** Where this document names a state to avoid — *out of
contact*, *did I have to say that again* — it is naming what the person must not be put in, not
prescribing the arrangement that avoids it. If any sentence reads as a design, it is a defect in this
document.
