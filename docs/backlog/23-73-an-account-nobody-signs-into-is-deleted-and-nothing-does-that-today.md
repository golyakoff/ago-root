# an account nobody signs into is deleted, and nothing does that today

- **Stage**: 23
- **Status**: ready — **and it is a question before it is work**
- **Depends on**: `13-03`'s subscription lifecycle for the paid half. Nothing for the unpaid half,
  because nothing exists.
- **Decision**: the tier grid, 2026-09-07 (`ago-business` `0012`). The mechanism is undecided and the
  questions below are the author's.

## What the grid asks for

- **Free tier: the account is deleted if nobody has signed in for three months.**
- **Paid tier: no inactivity deletion at all while payment continues**, and one further month before
  deletion after payment stops.

## What exists today

Nothing. There is no account-level deletion on any timer, in any ADR, in any item. `18-06` auto-closes
inactive *conversations*, which is a different thing about a different object. `13-03` has `PastDue`
and `Lapsed` and neither deletes anything.

So this is entirely new, and it is **automated destruction of a paying-or-not customer's data**, which
is the most consequential kind of feature this product can grow.

## The questions, and they are the author's

**1. What counts as activity?** The grid says *«не заходили»* — nobody signed in. Taken literally that
is a sign-in by an operator or administrator.

**The failure mode is the one that matters.** A shop installs the widget, it works, visitors write and
get answers by e-mail or phone, and nobody opens the console for three months. Under a literal reading
we delete a **live customer-facing service and somebody else's conversations with it.** That is the
most likely way this feature meets a real user.

Three readings, and they are different products:

- **Sign-in only**, as written. Simplest, and the hazard above is real.
- **Sign-in or any traffic** — a visitor writing counts. An account nobody uses at all is deleted; an
  account somebody's customers still use is not. Costs a second signal.
- **Sign-in, but never while the widget is installed and reachable.** Narrowest, hardest to check, and
  closest to "delete what is actually abandoned".

**2. Is anybody told before it happens?** Deleting without warning and deleting quietly are the same
thing to whoever it happens to. **We send no mail outside this deployment at all** (`23-70`), so a
warning is not a checkbox — it is the mail decision, arriving here first.

**3. What exactly is deleted?** *"The account"* is a site, its operators, conversations, contacts,
attachments and acceptance records. `adr/0111` says an acceptance record survives the erasure of its
own subject, so **"delete everything" is not available as an answer.** And the grid itself says the
customer base is kept *always* on the free tier — which cannot both be true if the account is deleted.
That contradiction is inside the grid rather than in this item, and it has to be resolved before
anything is built.

## Where this is likely to go wrong

- **A timer that deletes is one bug away from deleting the wrong thing.** Whatever it is, it must be
  reversible for a window, or it must be preceded by something that is.
- **`24-09` already names an erasure that cannot reach an archived message.** This inherits that gap
  rather than fixing it.
- **The paid grace month is not the same mechanism** and should not be built as though it were: one is
  "nobody came back", the other is "payment stopped", and `13-03` already owns the second half.

## Done when

- [ ] The author has answered what counts as activity, and the answer is recorded.
- [ ] Whether and how a tenant is warned is decided, with the mail question named rather than assumed.
- [ ] What is deleted and what survives is stated, and does not contradict `adr/0111` or the grid's own
      promise that the customer base is kept.
- [ ] Whatever is built is shown not deleting an account whose widget is in active use.
