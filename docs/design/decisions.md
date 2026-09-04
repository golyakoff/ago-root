# What was decided before stage 23 was sliced

Nine questions came out of checking `flows.md`'s stories against the backend. Each needed the author
before it needed a branch. All nine were answered on 2026-09-04, in conversation, and this is the
record — the reasoning matters more than the verdict, because the verdicts are short and the reasons
are what a future item has to stay consistent with.

**These are decisions, not proposals.** An item that contradicts one here is wrong until this file
changes.

---

## 1. An operator's display name is stored, and refreshed at every sign-in

**The question.** `ago-chat`'s `Operator` carries `ExternalSubjectId` and no name or email, so
`/operators/{id}/seat` and `/operators/{id}/remove` take an id nothing in the product can show. It
blocks the team screen, the transfer-target picker, and named rows in every report.

**Found while deciding**: the console *already* knows its own user's name —
`operatorDisplayName.ts` reads `profile.name → preferred_username → sub`, and the `openid profile
email` scope is already requested. The gap is other people's names, not names as such.

**Decided.** Store name and email on the `operators` row, captured from the token's claims at invite
redemption, **and rewrite them at every sign-in**. Rejected: querying Keycloak from `ago-chat` (a new
synchronous dependency from a product host to the identity provider, for a problem we do not have),
and keeping operators anonymous (which makes "manage your team" unsellable).

**Why the refresh.** It costs a few lines and removes the only serious objection to storing a copy —
that it goes stale when somebody changes their name.

**Consequence to carry**: a new personal-data field. `personal-data.md` gains it.

---

## 2. Capacity gates automatic assignment only. A person may take as much as they like

**The question.** `JoinConversationAsync` reaches `AssignConversationHandler` with
`holdsCapacityClaim: false`, and `adr/0033` preserved that asymmetry deliberately, filing the
reversal as follow-up. Does a deliberate claim charge capacity?

**Found while deciding**: capacity is **a constant**, not a formula — an `int` column set at creation
(`capacity: 5` for a site's first operator), which nothing recomputes and no screen changes. Live:
22 operators at 5, one at 10. `active_chats` is a denormalised counter on the same row; the claim is
one `UPDATE ... WHERE active_chats < capacity`. The auto-assigner picks **least-active-first** among
`Online` operators with room — so it balances load, it does not merely cap it.

**Decided**, and the model is the author's:

- **Capacity stops the auto-assigner, never the human.** Its meaning is now exactly *how many the
  system will hand you without asking*.
- **A manual claim increments `active_chats` and does not check it.** The counter rises past capacity
  freely. Without this the eager operator keeps looking freest and keeps receiving automatic
  assignments on top of what they took — double-loaded by their own initiative.
- **Nobody took it within a penalty period → assign anyway**, to the least-active online operator,
  capacity ignored. **A waiting customer is worse than uneven load**, and that is the business
  interest the rule serves.
- **Penalty period: 2 minutes, configurable per site.** A one-chair salon and a five-operator service
  have different tolerances; a constant would choose for them.
- **If nobody is online there is nobody to force it onto** — that case is `14-04`'s offline
  auto-reply, not this rule.
- **A waiting conversation shows its age**, not just "waiting". That is the tenant's number and the
  operator's only signal that it is time to take one beyond capacity.

**Record where a conversation came from** — assigned automatically, taken deliberately, or forced by
the penalty. Three different facts about a person's behaviour, indistinguishable today. One column
now; unrecoverable later.

**A metric is a recorded number, not a judgement.** How volume is weighed against speed when
evaluating somebody is the author's own formula and is not the product's business. The product
counts.

**Store ownership intervals, not counters.** Added 2026-09-04, after the counter version of this
decision turned out to be the wrong shape.

The reasoning that changed it: an operator who takes work beyond capacity trades a better
*concurrency* figure for a worse *response-time* one, and over the two the trade roughly balances —
so being forced or choosing to overload is not a punishment, provided both sides are visible. But a
daily average cannot show the trade: *slow because they were running seven at once* and *slow for no
reason* look identical in it. The author's own constraint — that the cost must be **proportionate**,
one more chat costing seconds rather than a quarter of an hour — is uncheckable without the load at
the moment.

So the product stores the raw fact and derives the rest:

- **An append-only interval per assignment**: which operator held which conversation, from when to
  when, and **how it came about** (assigned / taken / forced). One or two rows per conversation
  against dozens of messages.
- **Everything else is a query.** Concurrency at any instant is an interval-overlap; average times,
  longest pauses and the distribution of pauses by length all come from message timestamps, which
  **already exist** — `Message.CreatedAt` and `Sequence`, `Conversation.CreatedAt` and `ClosedAt`.
  This is not a data-collection project; the only missing piece is the assignment timeline, because
  `Conversation` holds one `OperatorId` — the current one — and a transfer erases the past.
- **No aggregates until they are needed.** Interval overlap gets expensive at scale, but that is a
  read concern: no write decision depends on it, so rule 8 is untouched, and a read model can be
  added when a report is measurably slow rather than in anticipation.

**A consequence worth stating, because it protects the tenant's reports**: timestamps are not personal
data, message *content* is. Build the statistics on times rather than text and an erasure request
takes the conversation without taking last month's numbers with it. `personal-data.md` gains that
distinction rather than discovering it at the first deletion.

---

## 3. The tenant is told whether their widget is working, and why not

**The question.** Story 4.1's tenant must distinguish *not installed* from *installed and quiet*
from *installed and broken*. `POST /api/v1/visitor-sessions` is stateless — it resolves the site by
public key and persists nothing — so today there is no evidence to give them.

**Decided.**

- **`last_seen_at` on the site, written at most once a minute** (a conditional `UPDATE`). Under any
  load that is one write per tenant per minute, not one per visitor.
- **The last refused origin is recorded too.** This is the half that closes the third state, and the
  common case is not a tenant spreading the script over extra sites — it is `www.` against the bare
  domain, `http` against `https`, or a staging subdomain. Then *everything* is refused, the widget is
  dead, and **`last_seen_at` never updates** — so without this the product says "we have never seen
  your site" to somebody whose script is installed and running. The two states would be
  indistinguishable, and the wrong one is the discouraging one.
- **A funnel, not a number: loads, opens, conversations.** One figure without a denominator reads as
  advertising. Three make the tenant see where they lose people.
- **Approximate is fine.** Nobody audits 273 against 271, so a batched flush that loses a few events
  on a pod restart is acceptable — reuse `BatchFlusherService` rather than building exact accounting.
  Write that in the item, or somebody will build precision nobody asked for.

**This block is encouragement, not reporting.** Real reports with filters and search come separately;
this is a small piece of "you are on the right track" on the tenant's own dashboard.

**Its failure mode is inverted, and lands on day one.** A new tenant sees `0 / 0 / 0` — three zeros
as their first impression, on exactly the day story 4.1 is about. So "nothing yet" is the block's
**normal first state**, and it must read as a next step:

- seen, numbers flowing → the funnel;
- seen, numbers zero → honest: it is installed and quiet, here is how long;
- **not seen at all** → not "zero loads" but "the script has not arrived yet", with what to do.

**Zeros are explained by context, and the advice must match which number is zero.** `first_seen_at`
(one column, written once) separates *just started* from *long ago and still nothing*. Then:

- **zero loads** → the script is not on the page, or its origin is refused. Recommending a channel
  here is actively harmful: the person goes off to connect Telegram instead of fixing the install.
- **loads, no opens** → they see it and do not open it. A channel will not help; this is placement,
  appearance and first line.
- **opens, no conversations** → they open and leave. *Here* channels, offline auto-reply and response
  time are the right advice.

Threshold for "recently": **7 days, in configuration**. And **only ever recommend what that tenant
can actually act on** — advice that ends at "available on another plan" reads as a sale, and the
whole point of the block is that it is on the tenant's side.

---

## 4. A visitor can leave a name and a phone, in a reusable control, unverified

**The question.** `RecordVisitorContactDetail` exists, but its route is `RequireOperatorIdentity`, so
a visitor cannot write one. Story 1.2's out-of-hours capture — the author's own annotation — needs
exactly that.

**The framing that settled it**: the phone **already arrives**, as free text in a message. People type
"call me on +7…" today, and that is personal data too — sitting in the conversation body where nobody
can find it and nobody can erase it on request. So the question is not whether to accept
visitor-supplied numbers, but whether to accept them in a shape that can be worked with. Structured
is a *reduction* of risk.

**Decided.**

- **One reusable control**, not a one-off for the night case. It serves: out-of-hours capture, the
  booking flow's name-and-phone step, "call me back" during working hours when everyone is busy, and
  an abandoned conversation.
- **Two modes, and the control does not decide which**: with verification and without.
- **No verification for a callback.** The principle: **verification is paid for by whoever benefits
  from it.** In booking the visitor benefits — the code protects *their* slot — so the effort is
  earned. For a callback only the tenant benefits, and the cost of a fake number is one wasted call.
  Making the visitor prove their identity for somebody else's benefit is how you lose them at the
  last step.
- **An unverified number is marked unverified.** One flag now, against a booking flow six months from
  now reading a contact from the profile and treating it as an identity nobody checked.
- **Retention: 90 days from last contact**, and gone with the conversation if that is erased sooner.

**The stated meaning of contact details changes and must change loudly.** Today they are documented
as "recorded by an operator, never used to contact the visitor automatically" — a visitor-supplied
callback number is the opposite. `personal-data.md` and an ADR, not a silent reuse of a field with
its meaning reversed. Consent is a requirement, not a UX detail.

---

## 5. Contact visibility is a ladder of three rungs. Build the second

**The question.** Two value propositions that look opposed: *your staff technically cannot take your
customer list* (mid-size, fears departing employees) against *I am the owner, the operator and the
tenant, and I want to see the number and call the person* (one-chair salon).

**They are not opposed** — it is one mechanism with a different setting, because what differs is who
holds the role. In the micro case the person seeing the number **is** the tenant. `20-12` (done,
2026-08-31) already built this on the calendar side: visibility gated on `CustomerRead`, and the
phone **absent** from list read models rather than merely hidden, so an operator's all-day screen
never holds it.

**Decided — the ladder, and be careful what is sold:**

1. **Everything visible.** Micro. Zero friction.
2. **Masked, revealed on demand, and the reveal is recorded.** Mid-size, and commercially the
   important rung. It gives **attribution, not prevention** — most exfiltration is casual, and a log
   stops casual. This is the one to build.
3. **Never visible.** Enterprise — **and it must not be sold until the system can place the call
   itself** (click-to-call, system-sent messages). Without that, rung three is not protection, it is
   an operator who cannot do the job.

**"Technically cannot know" is a far stronger claim than "does not have the permission."** A
permission is granted by an owner, and an owner under pressure grants it. Sell the impossibility only
where it is real.

**"I called and it is them" is a different fact from an SMS code**, and is recorded separately
(`verified by operator` vs `verified by code`). It lives only on rungs one and two — somebody who
cannot see a number cannot confirm it by calling, which is a useful test of whether the ladder is
being described honestly.

---

## 6. The owner grants a product from a runbook now, from the console later

**The question.** Both `PUT` and `DELETE /api/v1/owner/sites/{siteId}/modules` require the
deployment-wide provisioning secret in the request body (`adr/0095`), so a console grant screen would
put that secret into a browser form.

**Decided: runbook for now** — the first clients are a handful and `23-09` already assumes read-only
— **and chat holding the secret in its own configuration later**, so the screen becomes possible.

**Why the browser prompt is refused outright**: a secret a person carries in a clipboard stops being
a secret at about the third use.

**Why moving it into configuration is not a weakening**: the platform owner can read that secret from
the cluster anyway. Requiring them to paste it adds no protection to an identity already
authenticated by a realm role that no write in this codebase grants — it is not a second lock, it is
a second inconvenience. But it **moves responsibility**, so it is an amendment to `adr/0095`, made
openly.

**It becomes clearly right rather than merely convenient if `22-04` ever makes the secret per-site**:
chat would then hold a key to one tenant instead of a master key.

---

## 7. "Paying off" is not computed. Statistics are shown and interpreted

**The question.** Story 4.4 asks whether the product is making the tenant money, and whether it may
forecast.

**Decided: no valuation, and no forecast.** Rejected — including a proposal made in this very
conversation to ask the tenant for their average cheque and multiply. The author's reasoning, and it
is right: **we cannot know what an answer was worth.** Maybe the enquiry was the shop's own supplier.
Maybe the value is that somebody answers at all, around the clock, rather than that customers arrive.
A product that multiplies its way to a rouble figure is producing a fact-shaped thing resting on an
assumption it cannot check.

**What is shown instead**: statistics, with help reading them.

- **Never a bare number.** A figure alone means nothing; what makes it mean something is a pair —
  against last month, against another segment, or best of all **the same figure under different
  conditions**: *"conversations answered within 5 minutes reached a booking 34% of the time; those
  answered after 30 minutes, 8%."* That implies an action, and the tenant draws the conclusion
  themselves.
- **Dynamics, relative and absolute together.** Two bookings against three is "+50%" and is noise.
  Showing only the ratio congratulates a tenant on randomness — and the smallest tenants, the first
  ones, are where this bites.
- **A threshold below which the product refuses to conclude.** On nine conversations no percentage
  means anything; the block says "too little to compare yet" rather than printing 33%. This is the
  same first-day inversion as decision 3, and it is what separates a dashboard from a horoscope.

**Cuts that imply an action** rather than satisfy curiosity: response time against outcome; hour and
weekday (are nights being lost); channel; first contact against returning.

**Attribution claims only what can be traced.** A booking made in the widget after a conversation is
ours. A customer who phones a week later is not, and saying otherwise invites a check we would lose.
A smaller honest number renews the subscription; a larger arguable one ends it.

---

## 8. The product reaches the visitor. The visitor does not come looking

**The question.** Story 1.5: how does a visitor reach a booking they already made, given that a
`Customer` has no account and the verified phone *is* the identity?

**A proposal was rejected in conversation and the correction is the decision.** A signed link is
meaningless *in the widget* — the visitor is already in the window and has nowhere to put a link. It
is meaningful **in a message on their phone**, which is where they live after the tab closes. Right
mechanism, wrong place.

**Decided.**

- **The browser remembers.** The visitor token already lasts seven days; the widget distinguishes
  "you have a booking" from "you do not", and offers **cancel** and **reschedule**.
- **Those buttons compose a message and send it into the conversation**, where the ordinary machinery
  handles it. **A cancellation is a request, not a mutation** — the shop confirms. No new endpoint,
  no new trust boundary.
- **Reminders are a separate item, and a larger one**: at a week, a day and an hour, the cadence
  following the lead time. A day before asks *confirm*; an hour before says *do not forget*. Two
  different messages with two different jobs.
- **A link belongs in the reminder**, not in the widget.

**Four things the reminder item must carry:**

- **"Reply 1" needs inbound SMS**, which is a channel adapter, not a send. If only outbound exists,
  confirmation is a link in the same message instead.
- **SMS costs money — the first feature with a variable unit cost**, growing with a customer's
  success. Whose line item: included, capped, or the tenant's own gateway. Decide before a bill
  surprises somebody.
- **Cadence configurable per site**, like the penalty period.
- **A reminder must know about cancellation.** "Do not forget" for a cancelled booking is the worst
  message the system can send: it proves we are not keeping up.

---

## 9. Delivery outcomes are recorded for channels. Not for the widget

**The question.** Stories 2.2 and 4.5 want to know whether a message arrived. Nothing anywhere holds
per-message delivery state.

**The widget half is possible and deliberately not built.** A receipt could come from three places:
*stored* (known, but that is acceptance, not delivery), *written to the connection* (known, and a
socket write is not arrival — half-open sockets, backgrounded tabs, drops between write and receipt),
or *the browser acknowledged* (real delivery — and it needs a new protocol message plus a write per
message on the hottest, freshly repartitioned table).

Not built because the marginal value is small: **presence already exists** (polled every 10s), and if
the visitor is on the page the message arrived. The one case a receipt uniquely covers — present but
the connection broke — is rare and self-healing, since resume-by-sequence is what recovered all ten
lost messages when realtime was broken in `5-10`. Read receipts are a third thing again, with privacy
weight the visitor may not want.

**The channel half is built.** When a conversation arrives over SMS or Telegram, the operator's reply
**leaves our system**, and the provider says accepted, rejected or failed.
`DeliverChannelMessageHandler` **already receives that answer**, uses it to decide whether to ack the
broker, and throws it away.

What breaks without it: an SMS bounces — wrong number, blocklist, no credit at the gateway — the
operator sees their reply in the thread, the conversation looks answered, and the customer got
nothing. Nobody finds out, because a customer who was not answered does not complain, they leave.

Cheap: one table and a write per outbound channel message, at a fraction of widget volume, and
`webhook_deliveries` is the existing precedent for exactly this shape.

**And decision 8 makes it mandatory rather than nice.** We are about to send "confirm you are
coming". A reminder that failed and was not noticed returns as *"you never told me"*, and the no-show
is then ours.

**Stated limit**: this answers story 4.5 for channel conversations and **not** for widget ones, which
are the majority. Better a partial answer where we hold the fact than an invented one everywhere.
