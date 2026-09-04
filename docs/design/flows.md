# What people are actually trying to do

Written 2026-09-04 as the *intent* half of the input for a deliberate interface pass. The factual half
— every screen that exists today, with its states — is `ui-inventory.md` beside this file.

**This document describes tasks, not screens.** That is the point. The interfaces grew one screen at a
time, and the question never asked was what somebody is *in the middle of* when they arrive. Read a
scenario and ask: where does this person stop, what do they not know, and what does the product do
when the answer is no.

Each scenario is marked **built** (works today), **partial** (works, with a named hole), or **planned**
(an item exists, nothing ships). Do not assume a scenario is safe to redesign because it is listed
here.

---

## 1. Visitor

The only person here who did not choose this product, does not know its name, and will never see the
console. They are on **somebody else's website**, usually on a phone, usually with one question or one
slot in mind. Everything below happens inside a `<script>`-tag widget in a Shadow DOM.

### 1.1 "Is anyone there?" — asking a question — **built**

The visitor opens the widget and types. Behind it: a visitor session issued from the site's public key,
a conversation, messages ordered by a server-assigned sequence rather than a clock.

The decisions that matter and are invisible in a screenshot:

- **Before typing, can they tell whether anyone will answer?** Presence exists in the system. Whether
  the widget says "we usually reply within X" or nothing is a design choice with a revenue
  consequence: the visitor who leaves is never counted.
- **They send a message and nobody is online.** Offline auto-reply exists (`14-04`). The open question
  is what the widget *looks like* afterwards — a conversation that will be answered later needs a
  different resting state from one being answered now, and the two currently look alike.
- **They close the tab and come back tomorrow.** The visitor token renews and lasts seven days
  (`17-07`, `17-08`), so the history is there. Whether the widget makes that discoverable, or shows an
  empty box implying a fresh start, is undesigned.
- **They send an attachment.** Bytes never pass through the API — the browser uploads to object storage
  directly. Progress, failure and retry are all visitor-visible and all currently minimal.

### 1.2 "I want an appointment" — booking a slot — **partial, and the highest-value flow in the product**

This is the flow that closes sales, and the most exposed: a stranger's phone, a shop's own site, no
account, no second chance.

As the system understands it:

1. The visitor is shown **what can be booked** — a service, a master, a day.
2. They pick a **slot**. Slots are materialised from a master's schedule template across a horizon; a
   slot is a real row, not a computed suggestion.
3. They give a **phone number and verify it with a code**. Not optional and not a formality: the public
   booking endpoint is unauthenticated by construction — a `Customer` has no account — so the verified
   phone *is* the identity. An unverified booking must not be able to exist.
4. The booking is confirmed.

Every step has an unanswered design question, and these are the ones worth spending the tool on:

- **Master first, or time first?** The system supports both readings. Real customers split hard: some
  want *anybody, today*; others want *that specific person, whenever*. Serving one well and the other
  badly is what happens when nobody chooses.
- **What does "no slots" look like?** The honest answer is usually "not this week" — and the empty state
  is where the booking is lost. A dead end here is indistinguishable from a broken widget.
- **Phone verification is a hard stop mid-flow**, and it lands *after* the visitor has done the work of
  choosing. They leave the widget, open their SMS, come back — on a phone that is an app switch. What
  survives the switch, and what they see on return, decides whether the booking completes.
- **The code does not arrive.** Resend, a second channel, a way back — none of it designed, and it is
  the most common real failure.
- **A booking longer than one slot** (`20-18`) and **additional verified channels** (`20-11`) both
  change this flow's shape. Design once, for both.

### 1.3 "What did I book, and can I change it?" — **planned**

There is no visitor-facing view of an existing booking. A customer wanting to move or cancel has one
route: contact the shop. Whether that is acceptable is a product decision — but it should be a
decision, not an omission nobody noticed.

---

## 2. Chat operator

Someone doing a job for eight hours. The screen is open all day, so small frictions compound in a way
they never do in a flow used once.

### 2.1 "What needs me right now?" — the resting state — **built**

The screen they stare at between conversations, and therefore the most important one in the console. It
must answer at a glance: what is unanswered, what is mine, what is going stale.

- Ordering is guaranteed **per conversation, never globally**, so any "everything, newest first" view
  is making a promise the system does not make.
- Unread counts are maintained by a consumer and presence lives in Redis — both can be briefly stale. A
  number that flickers is worse than one that updates slowly.
- **This is where mobile-first bites hardest and is least likely to be right today.** Triaging on a
  phone is a real scenario for a small shop whose operator is also the owner, cutting hair.

### 2.2 "Answering" — one conversation — **built**

Real-time both ways; assignment exists. The design questions are about *state a person holds in their
head*: who else is in this conversation, whether the visitor is still on the page, whether their last
message was delivered, and what becomes of a half-typed reply when they get pulled away.

### 2.3 "This one came from Telegram" — one person, several channels — **partial**

Channel-identity linking exists (`14-12`, `adr/0079`), and more channels are Stage 14's subject. The
interface question is whether an operator sees **one person** or **several conversations that happen to
be the same person** — a distinction the data carries and the screen does not foreground.

### 2.4 "I'm going offline" — **partial**

Offline auto-reply is configured per site, not per operator. So the operator's own act of leaving — the
thing they actually do — has no surface at all. Worth deciding whether it should.

---

## 3. Calendar operator

A different job from chat, wearing the same login since `22-05`. This person manages **capacity**, not
conversations, and their unit of work is a week, not a message.

### 3.1 "Set up a master" — **built**

A worker card, then a schedule template, then a horizon over which slots are materialised. Three
concepts at once, and the person learning them is at the least-supported moment in the whole product.
This is a first-run experience currently shaped like a settings screen.

### 3.2 "Change the schedule from next month" — the re-cut — **built, and the sharpest edge in the product**

The tenant changes a master's pattern. Days are already materialised, and **some of them have bookings
on them**. The system offers exactly two outcomes per affected day: cancel the booking, or leave that
day in the old grid. Both are lossy — cancelling costs a customer their appointment for an
administrative reason they had no part in; keeping the day means the schedule the tenant just fixed
does not apply to precisely the days that matter, because those are the days with customers on them.

What this implies for a screen that does not yet exist in any adequate form:

- It is a **preview-then-confirm** operation, and the preview is a *diff*: what changes, what breaks,
  what it costs. The system already computes a fingerprint and refuses a stale confirm.
- **Per-booking decisions**, not a bulk switch. A person needs to see the customer and the time and
  choose.
- Moving a booking instead of cancelling it is `20-17`/`20-29` — **planned**. Designing this screen as
  though only cancel exists would bake in the lossy version permanently.
- Failures here are ordinary outcomes of correct use, and until today were indistinguishable from a
  crash: `22-20` mapped sixteen refusal codes that had been returning 500. *"The day changed while you
  were deciding"* needs a real screen, not a status code.

### 3.3 "Someone called, book them in" — **planned (`20-28`)**

The operator-side booking, and a different interaction from the visitor's: they have the customer on
the phone, they can see the whole grid, and they may be creating the customer as they go. Finding an
existing customer by a phone number typed mid-sentence is the core gesture.

### 3.4 "What happened at the visit" — **planned (`20-23`)**

Outcome and takings, entered on the same card as the booking. Whether an outcome survives a moved
appointment is an open question inside that item.

---

## 4. Tenant

The person who pays. Visits rarely, in a hurry, usually because something is wrong or something new
must be switched on. **Every screen they see is either onboarding or troubleshooting.** There is no
third mode, and treating these as ordinary settings pages is the mistake most worth undoing.

### 4.1 "I signed up — now what?" — first run — **partial, and the weakest flow in the product**

Between registering and having a working chat on their site lies: getting the script tag, installing
it, confirming it works, and inviting whoever will answer. `10-06` exists precisely because *the tenant
never learns how to install the widget*.

The design question is not "where does the snippet live". It is **how a non-technical shop owner finds
out it is working** — and what the product does for the one who cannot install it at all.

### 4.2 "Switch on the calendar" — **partial**

Module enablement exists (`19-03`, `22-11`); the paid version with a quota is `22-07` — **planned**. An
owner can also grant a module without payment (`22-17`, `adr/0098`) — API only, no screen.

For design: enabling a module is not a toggle, it is a **before/after**. What changes for the tenant,
what it costs, and what they must do next — none of which a switch conveys.

### 4.3 "Give my colleague access" — **built**

Invite, roles, permissions, seats. The free tier's seat count is itself an open item (`13-08`). The
recurring failure: permissions are shown as capabilities and understood as job titles.

### 4.4 "Am I paying the right amount?" — **partial**

Billing through ЮKassa exists on the write path. What a tenant can *see* about their own plan is thin.

### 4.5 "A customer says they got nothing" — troubleshooting — **partial**

Webhook deliveries, message delivery, verification failures. The data exists — delivery outcomes are
recorded — and the surface that lets a non-technical person answer *"did it send"* is largely absent.

---

## 5. Platform owner

The author, and later whoever runs support. A handful of people doing things that are **irreversible
and cross-tenant**. Volume is low; the cost of a mistake is high. Design for confirmation and
legibility, not for speed.

### 5.1 "Show me every tenant" — **built**

`GET /api/v1/owner/sites` — read-only, keyset-paged, cross-tenant. The one place in the codebase where
a caller's own `site_id` must be deliberately ignored.

### 5.2 "Give this prospect the calendar for a month" — **built as an API, no screen**

`22-17`: grant and revoke, with `GrantedByOwner` and a required `ExpiresAt`. **There is no owner-facing
screen at all** — it is an HTTP call today. It is also what lets a first client be onboarded before a
payment path exists, so it is not a nice-to-have.

A screen must carry what the ADR says plainly: **expiry binds chat only.** The module is never told a
grant lapsed. A screen presenting expiry as a clean end date would be lying.

### 5.3 "Fix this tenant's broken registration" — **partial**

The support case: a payment succeeded and provisioning did not. Revoke-and-re-enable is the remedy, and
it works on a tenant's own purchase as readily as on a grant — **an owner can undo something they did
not do.** That asymmetry has to be visible at the moment of acting.

### 5.4 "Unlink this channel identity" — **built as an API**

`14-12`. Cross-tenant write, gated only by a realm role. Same shape, same absence of a screen.

---

## What makes this interface hard, stated once

**One login, two products, and the customer must not be able to tell.** That is Stage 22's premise. The
console is one console; the calendar is a *module* a tenant switches on, and chat never learns the word
"calendar". An interface that reveals the seam — two navigations, two vocabularies, two places to look
— undoes what the architecture spent a whole stage buying.

**Three of the five roles are often the same human.** A one-chair salon owner is tenant, chat operator
and calendar operator, on a phone, between customers. A design assuming one role per person will be
right for the largest customers and wrong for the first ones.

**Permissions are a vocabulary, not a fence.** Screens appear and disappear by permission, and
"absent" is the designed behaviour for "not granted". So **a missing feature and a missing permission
look identical** — which is exactly how `22-14` was found: a person holding calendar permissions in two
tenants sees no calendar at all, and it reads as though nothing was ever granted.

**Errors are a design surface here, not an edge case.** The re-cut conflict, the lapsed grant, the
unverified phone, the stale confirm — each is an ordinary outcome of correct use, and each is currently
a status code in search of a screen.
