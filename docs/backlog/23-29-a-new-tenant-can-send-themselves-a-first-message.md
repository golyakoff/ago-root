# a new tenant can send themselves a first message, and watch it arrive

- **Stage**: 23
- **Status**: ready — **with one question the author answers before implementation starts**, below
- **Depends on**: `23-06` (the installation signals this must not corrupt) and `10-06` (the install
  instructions this sits beside)
- **Decision**: the author, 2026-09-05, from Jivo's own post-registration screen: the empty queue
  should offer an **action**, not only a statement
- **Serves**: `flows.md` 4.1, which calls the tenant's first day the weakest flow in the product

## Goal

A tenant who has just registered sees, within a minute and without installing anything, a real
conversation appear in their own queue — because they sent it themselves.

## Why this is worth an item rather than a nicer empty state

Today the empty queue says *"Пока ничего не назначено. Новые диалоги появляются здесь автоматически."*
That is true and it is inert. A person who has registered thirty seconds ago cannot tell the
difference between **working and idle** and **not working at all**, and `23-06` shipped the diagnostic
half of that problem — *did the script arrive* — without the half that lets them produce a first
conversation on purpose.

The competitor's version is one button: *write to yourself*. The value is not the copy. It is that a
new tenant's first experience of the product is **seeing it work**, rather than reading a description
of what will happen when somebody else does something.

## The trap, verified, and it is the whole engineering content of this item

A "write to yourself" page hosted on **our** domain sends an `Origin` header that is not in the
tenant's `allowed_origins`. `AuthEndpoints`' visitor-session mint refuses it with `403` — and, worse,
calls `RecordRefusedOriginAsync`.

So the naive implementation makes the install screen `23-06` shipped this morning report a refused
origin **caused by us**. A feature built to reassure a new tenant would, in its first minute, make the
product accuse itself of being broken. That is not a detail to discover during implementation.

## The question for the author, and it is security-adjacent

**How does a tenant act as a visitor on their own site before that site exists?** Three shapes, and
none is obviously right:

1. **Add the first-run page's origin to the tenant's `allowed_origins` at registration.** Simplest.
   Costs: our domain then appears on the tenant's own install screen under *"your website address"*,
   which is confusing and slightly untrue, and it never gets removed.
2. **Exempt one designated first-run origin from the check, and record no refusal for it.** Keeps the
   tenant's own list clean. Costs: a carve-out in the one control that enforces per-site boundaries,
   which must be narrow enough that it cannot become a general bypass — and `17-01`'s history is the
   argument for treating that seriously rather than as a small flag.
3. **Do not use the widget path at all** — a console-side control that creates the conversation
   through an authenticated operator route. Costs: it proves nothing about installation, and the
   conversation it makes is not the one a visitor would make, so the reassurance is partly theatre.

**Option 2 is the one that delivers what the author asked for without lying to the tenant**, and it is
also the only one that touches a security boundary. Which ships is the author's call.

## Scope, once that is answered

- A first-run page a tenant reaches from the empty queue, carrying their own site key, on which the
  real widget runs.
- The empty queue offers it as an **action**, not a sentence — and only while the tenant has never had
  a conversation, so it disappears once the product is genuinely in use rather than lingering as
  clutter.
- **The resulting conversation is real.** It lands in their queue, is answerable, and counts. That is
  the point; sandboxing it would reproduce the theatre of option 3.
- **`23-06`'s signals stay honest.** A first-run session must not record a refused origin, and must not
  be counted as a sighting of the tenant's *own site* — otherwise the install screen says the script
  arrived when it never did, which is the failure `23-06` exists to prevent, inverted.

## Out of scope

- **Rewriting the queue's ordinary empty state.** This is the first-run case; a tenant with a working
  installation and a quiet hour sees the existing wording.
- **Onboarding beyond this.** No tour, no checklist, no progress bar.
- **Copying Jivo's wording.** Their text is theirs. The shape of the idea is what the author asked for.

## Done when

- [ ] A tenant who has just registered can, from the empty queue, send themselves a message and see it
      arrive as a real conversation.
- [ ] No refused origin is recorded for the first-run page, asserted by a test — the trap above, held
      shut.
- [ ] The install screen still says *not seen* until the tenant's own site is genuinely seen, asserted
      by a test that runs a first-run session first.
- [ ] The action disappears once the tenant has had any conversation.
- [ ] Whichever of the three shapes ships, the reasoning is in an ADR — option 2 in particular is a
      deliberate hole in a boundary control and must not land as an undocumented flag.
