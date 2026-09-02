# Who confirms a booking that started in a conversation

- **Stage**: 20 (and 12/14 — it is an authorisation question before it is a Calendar one)
- **Status**: done (`ago-calendar#21`, `ago-calendar-console#20`, `adr/0088`, merged 2026-09-02) — see
  Outcome below
- **Depends on**: `20-07` — the contract and the transport. This question only becomes answerable once
  a booking can actually originate inside a conversation.
- **Tension with**: `adr/0027`, deliberately and explicitly.

## The question

`adr/0065` lets a visitor start a booking inside a chat conversation, and lets an operator intervene
at any moment. `adr/0027` says AGO Calendar defines **its own `Operator`**, in its own repository, with
its own table, and that it is **never the same database row** as `Ago.Chat.Domain.Operator` — the two
unified only through Keycloak, each product resolving the same `sub` against its own `operators` row.

Both are right on their own. Together they leave one thing unanswered: **a chat operator looking at a
booking card in a conversation they are handling.** If they can act on it — confirm, reschedule,
cancel — then Calendar is authorising an identity that has no `operators` row of its own in Calendar.
If they cannot, the operator is holding a conversation about a booking they are powerless to change,
and `adr/0065`'s "the operator may always intervene" is true of the message and false of the thing the
message is about.

## Why this is its own item and not a paragraph in `20-07`

It is not a contract-shape question. `20-07` can ship a working booking flow with **no** operator
actions on the card at all, and that flow would be honest and useful. This item decides an
authorisation policy that spans two products and touches a recorded decision, which is exactly the
kind of thing this project turns into an ADR rather than an implementation detail.

**Correction, 2026-09-02**: this item's own claim above was checked before deciding and is stale.
`authorization.md`'s own "Done when nothing here is open anymore" checklist is now fully `[x]` — every
item it once tracked has shipped. The file's one genuinely open item (a console UI for managing custom
per-tenant roles in `ago-console`) is real but unrelated to this question; nothing in that file names
or blocks the chat-operator/Calendar-identity tension this item is actually about. This question was
never downstream of an existing open decision — it is a new one, raised for the first time by `20-08`
itself. Decided below without waiting on anything else.

## Relation to `21-02`

`21-02` merges the two products' operator queues into one screen. This item is narrower and comes
first: it asks what a chat operator may *do* to a booking, not where they see it. A unified queue that
shows a booking nobody in that screen is allowed to act on would be a worse outcome than two queues,
so the authority question is the one to settle before the presentation question.

## The shapes worth weighing

- **Calendar grants nothing.** The card is read-only for a chat operator; acting on it means opening
  Calendar's own console. Cheapest, and honest about the product split — at the cost of making the
  conversation a dead end exactly when it matters.
- **Calendar grants a narrow, module-scoped permission**, declared by the module and stored by Chat as
  an opaque string. Keeps `adr/0027`'s two rows separate — the chat operator never becomes a Calendar
  `Operator`; Calendar simply accepts a named capability for a Keycloak `sub` it recognises.
- **The tenant links the two identities explicitly**: one person, two `operators` rows, one in each
  product, connected only through Keycloak — exactly `adr/0027`'s own mechanism, applied a second
  time. Preserves the ADR literally, at the cost of the tenant having to do something.

## Decided (2026-09-02): a real Calendar `Operator`, invited by email — `adr/0088`

**The first answer here was the narrow capability, and it was wrong.** It was chosen on the argument
that it costs a tenant nothing to set up, while explicit linking asks a shop owner to perform a linking
step. The author challenged it: *if a table is needed either way, the cheapness argument disappears —
do the honest thing.* Checking against the real code showed the challenge was right, and the original
argument had a hole in it — recorded here because the hole is the useful part:

- The capability's "no setup cost" held **only if the grant were blanket**. A deliberate grant needs
  somebody to grant it, which means an endpoint and a screen — precisely the cost it was meant to avoid.
- The capability needs **entirely new machinery**: `20-12`'s `Role`/`RoleAssignment`/`PermissionChecker`
  are each keyed on an `Operator` row, so a capability grant would need a parallel table, its own check
  and its own screen.
- Explicit linking **reuses everything already built**. `Operator.ExternalSubjectId` and
  `LinkExternalIdentity` exist. `OperatorIdentityClaimsTransformation` already resolves a Keycloak `sub`
  to a Calendar operator on every authenticated request. Roles, permissions and the Access screen came
  with `20-12`. The one real gap: `Operator.Create` has exactly one caller today
  (`RegisterTenantHandler`, for the account owner), so a tenant cannot add a second operator at all.

So the shape that looked more expensive is the cheaper one, and it is the one with real accountability.
The onboarding objection is real but is a **user-interface** problem, and it is solved below rather than
designed around.

## The interface, designed rather than left to implementation

The tenant never encounters "linking", "subject", or "a second account". They encounter the
invite-a-teammate flow every SaaS product already taught them.

**On the Access screen** (`ago-calendar-console`'s `AccessPage.tsx`, built by `20-12` — this extends it,
it does not add a screen):

- A new control, *"Invite a colleague"* — two fields, display name and email address. Nothing else.
- The operators table gains a status column: **Invited** (no `ExternalSubjectId` yet) or **Active**. An
  invited row still shows its role checkboxes, so the owner can decide someone's permissions before they
  ever sign in.
- Copy is about people and permissions, never about identity plumbing: the heading stays "Operators",
  the invite says "They will use the account they already sign in with."

**What happens underneath**, in order:

1. Invite creates an `Operator` row: display name, invited email, `ExternalSubjectId` null,
   `IsAccountOwner` false. The owner grants roles to it immediately if they want.
2. The invited person opens the Calendar console and signs in with the account they already have.
3. `OperatorIdentityClaimsTransformation` finds no operator for their `sub`, falls back to matching the
   token's email claim against invited rows, and calls the existing `LinkExternalIdentity`.
4. From then on the `sub` resolves directly, and nothing about that person's path is special ever again.

**The friction this genuinely has, stated rather than hidden**: the invited person must sign into the
Calendar console **once** before they can act on a booking card from the chat console. Until then their
`sub` resolves to nothing and the action is refused — never auto-provisioned, because this item's own
Done-when below forbids a chat-originated action from creating an `Operator` row as a side effect. The
Invited/Active status column exists so the owner can see exactly why. A smoother path (the chat console
catching that refusal and offering "activate your booking access") is a real improvement and is
deliberately **out of scope** rather than half-built.

**The failure mode worth designing for**: if the owner types an email that differs from the person's
Keycloak email, the link silently never happens. Mitigated by the visible Invited status, not by making
the match cleverer — a fuzzy identity match is a worse thing to own than a visible unresolved invite.

## Done when

- [x] An ADR decides it, states which of `adr/0027`'s guarantees still hold verbatim, and — if any
      does not — amends `adr/0027` rather than quietly contradicting it. — `adr/0088`, 2026-09-02.
- [x] A chat operator's authority over a booking card is proven by a test in **both** directions: what
      they may do, and what they are refused.
- [x] `authorization.md` is updated, since this is the second product to need an answer from it. — its
      own "A second product asks this file a question" section, 2026-09-02.
- [x] No path exists by which acting on a card in Chat creates or mutates a Calendar `Operator` row as
      a side effect — the failure mode `12-04` already caught once, in a different disguise. An action
      from a `sub` with no operator row is refused with a `403` (no claim, no exception, no
      auto-provisioning), proven by test rather than assumed.
- [x] A tenant can invite a second operator by name and email, grant them roles before they have ever
      signed in, and see Invited-versus-Active status — proven end to end, including the case where the
      invited email never matches anyone.
- [x] The email fallback in `OperatorIdentityClaimsTransformation` links exactly once and only for an
      invited row — the direct `sub` lookup always runs first, so a bound subject is never re-resolved
      by the fallback at all.
- [x] `personal-data.md`'s own `operators` (AGO Calendar) row records the new invited-email column — a
      direct identifier where that table previously held only a display name.

## Outcome

Built and merged 2026-09-02 (`ago-calendar#21`, `ago-calendar-console#20`, `adr/0088`). Independently
re-verified by the managing session: `ago-calendar` 540/540, all 5 assemblies confirmed present (Domain
194, Application 134, Architecture 18, Concurrency 19, Integration 175); `ago-calendar-console` 61/61
across 9 files; `dotnet format`/build/`npm run typecheck`/`lint`/`build` all clean, zero warnings.

**Fails-before independently re-proven by the managing session** on the collision guarantee — the one
most likely to be wrong in a way nothing else would catch: changed `FindInvitedByEmailAsync`'s
`candidates.Count == 1` to `>= 1`, confirmed `EmailFallback_TwoInvitedRowsSharingAnAddress_LinksNeither`
failed by linking an arbitrary one of the two rows. Restored byte-identical, full suite re-confirmed.

**Both email collisions refused rather than resolved cleverly**, as `adr/0088` chose: two invited rows
sharing an address link neither; an already-active operator can never be a candidate at all, because the
query filters `ExternalSubjectId == null`; and a `sub` once bound is never re-resolved by the fallback,
because the direct lookup always runs first, every request.

**`adr/0083`'s account-owner invariant confirmed unaffected** — invited operators are always created
with `isAccountOwner: false`, so `Grant`/`Revoke`'s invariant never fires for them, and the pre-existing
`OperatorAccountOwnerTests` still pass.

**The UI requirement held literally**: verified by direct source read that "link", "subject" and "second
account" appear nowhere in rendered copy — the only occurrences are inside a doc comment explaining
their absence.

**One thing the design got slightly wrong, found by implementing it**: this item and `adr/0088` both say
the invited person must "sign into the Calendar console" before acting. There is no distinct login
endpoint — every authenticated request runs the same claims transformation, so the link completes on
whichever authenticated call their browser makes first. Architecturally identical in effect (linking only
ever completes a pre-existing, deliberately-created invite; it never fabricates a row), but "sign-in" and
"first authenticated action" are the same event in this codebase, and the design language implied they
were two.

## Open questions

- **Whether the same answer covers the reverse direction**: a Calendar operator replying to the
  visitor through the conversation the booking came from. Probably yes, probably by the same
  mechanism, but the asymmetry has not been examined.
- **What a visitor may do to a booking from the conversation** once an operator is involved. Chat's
  own escape-to-a-human rule says the module cannot lock the visitor out of reaching a person; it says
  nothing about whether the visitor can still cancel from the card.
