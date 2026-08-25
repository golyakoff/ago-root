# Subscription lifecycle: renewal, failure, cancellation, and mid-cycle changes

- **Stage**: 13
- **Status**: ready — the four policy questions were answered 2026-08-25 (`ago-business`'s
  `decisions/0006`); what was missing was policy, and it is no longer missing
- **Depends on**: `13-02-yookassa-subscription-checkout-and-webhook.md` (the stored `payment_method_id`
  and the checkout/webhook mechanism this item's recurring-charge job and cancellation/downgrade
  endpoints both build on)

## Goal

Once this item's open questions are answered, it builds everything that happens to a subscription
*after* the first successful payment `13-02` already handles: the recurring monthly re-charge against the
stored `payment_method_id`, what happens when that charge fails, what happens when a site explicitly
cancels, and what happens when a site changes its seat count mid-cycle. None of this is built yet, and
none of it *can* be built correctly without the author's decision on each question below — this is not
missing implementation effort, it is missing policy. Writing a plausible-sounding default for any of them
would be exactly the failure mode `CLAUDE.md` warns against for a portfolio project a reviewer will read
as evidence of how the author thinks: a real business would need these stated and deliberate, not guessed.

## Context to read first

`docs/backlog/13-02-yookassa-subscription-checkout-and-webhook.md` in full — the checkout/webhook
mechanism, the `payment_method_id` this item's recurring job charges against, and the local
pending/succeeded/failed state shape this item extends with whatever additional states its own policy
answers require (e.g. `past_due`, `canceled` — not decided here, see Open questions).
`docs/architecture/resilience.md`'s "Where each boundary is, and what protects it" table and its
"Patterns we deliberately do not use" section — a recurring-charge job calling ЮKassa is exactly the
"boundary with something that can fail independently of us" shape this document already has a vocabulary
for (timeout, retry, circuit breaker where a fallback exists); whichever policy the author picks below,
its *mechanical* implementation reuses `Ago.Platform.Resilience` (`6-01`) rather than inventing new retry
machinery. `docs/architecture/messaging.md`'s outbox/dispatcher pattern — if the chosen policy involves a
scheduled recurring-charge job (near-certain regardless of which answer below is picked), it runs in
`Ago.Chat.Worker` alongside `2-06`'s `PartitionMaintenanceJob` — a `PeriodicTimer`-driven background job is
already a proven shape in this codebase, not a new one to design.

## The questions, none of which are answered anywhere in this repository or in the business context this
stage was planned against

- **Failed recurring charge**: when a scheduled re-charge against the stored `payment_method_id` fails
  (card expired, insufficient funds, ЮKassa declines), what happens? Candidates a real business would
  choose between, named for concreteness, not as a recommendation — this item takes no position:
  - Immediate downgrade to free the moment a charge fails.
  - A grace period (some number of days) during which the paid tier's entitlements still apply while
    retries continue, before downgrading.
  - A retry/dunning schedule — how many attempts, what backoff, whether the site is notified between
    attempts (and if so, how — this codebase has no email-sending infrastructure anywhere, `10-01`'s own
    explicit deferral; a notification story would need one, itself new scope).
  None of these is named in `roadmap.md`, and the business context given for planning this stage does not
  answer it either — it names ЮKassa's autopay *mechanism* as decided, not what this system does when that
  mechanism reports failure.
- **Explicit cancellation**: when a site cancels, does the paid tier's entitlements end immediately, or
  does the site keep paid-tier access until the period it already paid for ends (the common "paid until
  period end" SaaS convention, but a convention is not a decision this project has made)? This also
  determines whether a cancellation needs its own scheduled "downgrade at period end" job, or is a single
  immediate write.
- **Mid-cycle upgrade/downgrade**: if a site raises or lowers its seat count partway through a billing
  period, does the new price apply immediately with a prorated charge/credit for the remainder of the
  period, or does the change take effect at the next renewal with no proration? This also determines
  whether `13-02`'s checkout-session endpoint needs a second, different code path for "change an existing
  subscription" versus "create a new one" — a real design fork this item cannot size until the proration
  question is answered.
- **Downgrade below current operator count**: if a site's live operator count exceeds the seat count it is
  downgrading to (e.g. 5 operators, downgrading from Growth to Starter's 3-seat ceiling), what happens?
  Candidates named for concreteness only: block the downgrade until the site removes operators itself (but
  `13-01` explicitly named "remove an operator" as an unbuilt flow — this would create a dependency on
  scope that does not exist yet); let the downgrade proceed and simply block *new* invites until the count
  is back under the new limit (no existing operator is forcibly removed); something else. Not decided.

## Scope, once unblocked

Cannot be sized precisely until the questions above are answered, because the answers change the shape of
what gets built (a scheduled job with retries vs. a single immediate write; a new "grace period" status vs.
two states; a proration calculator vs. none). Once answered, this item is expected to include at minimum:
a `Ago.Chat.Worker` recurring-charge job reusing `Ago.Platform.Resilience` against ЮKassa's charge API for
a stored `payment_method_id`; whatever new `sites`/subscription-row status the chosen failure policy needs;
a cancellation endpoint; and — only if the mid-cycle proration question resolves toward "immediate,
prorated" — a proration calculator and a second checkout-session code path. An ADR is expected regardless
of which answers are chosen, matching this project's own "a decision worth arguing about becomes an ADR"
rule (`CLAUDE.md`) — a subscription-lifecycle policy is exactly that kind of decision.

## Out of scope

- The multi-identity/multi-site loophole (`13-01`) and attachment/history/site-count caps (`13-05`) — both
  named, both separately blocked, neither is this item's question to resolve.
- Refunds — a related but distinct policy question this item does not fold in; real, separate scope if
  ever wanted.

## Done when

Not yet defined — this item's own Scope cannot be written precisely until the questions above are
answered; writing checkable Done-when statements against unstated policy would itself be inventing the
policy by the back door. Once the author answers, whoever picks this item back up writes a Scope and
Done-when section with the same rigor `13-01`/`13-02` used, and updates this item's Status.

## The policy, decided 2026-08-25

Recorded in full, with reasoning, in the private `ago-business` repository as
`decisions/0006`. Restated here because an item a session picks up must be buildable from this file.

**A failed recurring charge** puts the subscription in `past_due` with **full access retained** while
retries run for roughly a week; if none succeeds, the account drops to Free. The commonest cause of a
declined charge is a reissued or expired card rather than a refusal to pay, and this is a support
product — cutting a shop off on the first failure darkens its line to its own customers, who did
nothing. The exact retry schedule inside that window is this item's own choice; state it when built.

**An explicit cancellation** turns off auto-renewal and leaves the paid tier running until the end of
the period already paid for. No refund. Mechanically a flag the recurring-charge job honours.

**A mid-cycle change** is asymmetric on purpose: **upgrades apply immediately** and the difference for
the remainder of the period is charged at once; **downgrades apply at the next renewal**, with no
credit for unused time. This removes credit accounting entirely — ЮKassa has no balance concept, so a
refund-the-difference policy would mean building and reconciling our own. The asymmetry costs the
customer nothing: an upgrade is wanted *now* because someone was hired today, while a downgrade
deferred simply means keeping the tier already paid for until it lapses.

**More operators than paid seats** puts the account in an over-seats state in which **nothing is
deleted and nobody is chosen for the customer**: every operator account and all its data stay intact,
but only the owner and as many operators as are paid for can sign in, and the owner decides which.
Both rejected alternatives are worse in kind rather than in degree — disabling "the newest" or any
other rule means making an arbitrary decision about somebody else's staff, and a person loses access
mid-shift because an owner pressed a button; allowing the downgrade while merely blocking new invites
means charging for fewer seats than are in use, which retires per-seat pricing as a concept.

**This last one is one behaviour covering two paths, and that is the reason it is shaped this way.**
The same collision arises without any downgrade at all: an account that drops to Free after a failed
payment has one seat and may have six operators. There, "do not apply it until the customer complies"
is impossible — they are not answering, which is why the charge failed. Some automatic behaviour is
unavoidable, so the only real question was whether it destroys anything. This one does not.

## Consequences for other items

- **`13-01` gains seat assignment and operator removal.** Choosing who holds a seat needs a surface,
  and removing an operator does not exist anywhere today. It is needed regardless of billing — people
  leave — so this is a dependency being named rather than scope being invented.
- **Two new subscription states** beyond `13-02`'s: `past_due`, and over-seats. Whether over-seats is a
  state on the subscription or a derived condition is an implementation choice, not a policy one.
- **No credit or refund machinery is built.** That is a direct saving and a direct consequence of the
  mid-cycle decision.
- A Free account after non-payment keeps its history: retention class is stamped at write time
  (`adr/0031`), so returning to a paid tier restores seats, not data — the data never went anywhere.

## Open questions

None. The four that blocked this item are answered above.
