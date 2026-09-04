# the visibility rung is a property of the account, and chat's own contacts obey it

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-08` (the register entry for `visitor_contact_details`, so a masking change
  lands over a store the register knows about). `23-09` is not a dependency and may land in either
  order.
- **Decision**: `docs/design/decisions.md` §5, including the *the ladder is a property of the tenant*
  amendment (2026-09-04)

## Goal

A tenant can put contact surfaces on the middle rung — numbers masked, revealed on demand, and every
reveal recorded against a named operator — and that setting is **one setting for the account**, not
one per product. This item builds the setting, publishes it, and applies it to chat's own store.

## Why this exists at all: the ladder covered one store and not the other

§5's amendment. `20-12` (done 2026-08-31) built rung-two-ish behaviour over the calendar's
`customers`, gated on `Permission.CustomerRead`. Decision 4 creates — and `14-14` already created —
a **second** store of customer phone numbers: chat's `visitor_contact_details`, read by
`ListVisitorContactDetailsHandler` under `Permission.ConversationRead`, which every operator holds
because it is what the job is, and **not** the narrower assigned-operator check. So an operator can
read the contacts of any conversation in the tenant, and a tenant sold rung two would have got it for
bookings and not for callbacks — callbacks being decision 4's own headline case.

**So the rung is one setting on the account, and each product reads it and applies it to its own
store. No shared type crosses the product boundary; a shared rule does.**

## Where the setting lives, and the alternative rejected

On `ago-chat`'s `sites` row. `ago-chat` is the account side — `22-05` put the one role catalogue
there and publishes it outward (`adr/0093`), `RoleAssignmentsChanged` is the contract, and
`ago-calendar` already projects it (`IRoleAssignmentProjectionStore`,
`RoleAssignmentsChangedConsumer`, whose own remarks record that a chat `SiteId` *is* the calendar's
`TenantId`). This item reuses that established direction rather than inventing a second one.

Rejected: a setting in each product's own settings screen. It would let the two disagree, and a
tenant told "your staff cannot take your customer list" while one of two stores is wide open has been
sold something untrue.

## What this gives, said honestly

§5's own framing, and the sentence the item exists to keep honest: rung two gives **attribution, not
prevention**. Most exfiltration is casual, and a log stops casual. *"Technically cannot know" is a
far stronger claim than "does not have the permission"*, and it is not what this builds.

## Context to read first

- `docs/design/decisions.md` §5 in full, including why rung three must not be sold yet
- `docs/backlog/20-12-*.md` — what it built, and its reasoning for keeping the phone out of list rows
- `docs/design/flows.md` 4.3; `docs/design/ui-inventory.md` §3.4 (panel 7)
- `docs/architecture/authorization.md`, `docs/architecture/tenant-isolation.md`,
  `docs/architecture/messaging.md` (the outbox rule, and why a contract needs a version story)
- `Ago.Chat.Contracts/RoleAssignmentsChanged.cs` and `Ago.Chat.Contracts/SiteSettingsChanged.cs` —
  the two existing shapes, one crossing the product boundary and one not
- `docs/adr/0093-*`, `docs/adr/0100-*`

## Scope

- A **contact visibility** setting on `sites`, with two values today: `Visible` and
  `MaskedWithReveal`. One additive column, defaulting to `Visible` so every existing tenant keeps
  exactly the behaviour it has.
- **Rung three (`Never`) is not added, not even as an unreachable enum value.** §5: it must not be
  sold until the system can place the call itself, and a value present in the code is a value
  somebody will offer.
- A new integration event carrying the account's current rung, published **through the outbox** in
  the same transaction as the write (`CLAUDE.md` rule 4), consumed by chat's own cache invalidation
  and, in `23-12`, by the calendar. It carries the complete current value, never a delta — the same
  choice `RoleAssignmentsChanged` records for itself, and the reason its consumer can be idempotent.
- On `MaskedWithReveal`, `ListVisitorContactDetailsHandler` returns the value **masked in the read
  model**, not in the console, so the unmasked value never reaches the browser as part of a list.
- A reveal: one contact detail, one reveal, gated exactly as the list is
  (`Permission.ConversationRead`) and scoped by site the same way. It returns the value and writes a
  row.
- A **reveal record**: who revealed what, when, and which surface asked. Modelled on
  `webhook_deliveries` — same shape, same prune-job treatment, its own retention.
- **A tenant-facing read of that record.** A record nobody can read is not attribution.
- `ago-console`: the visitor aside's contact panel reveals on demand rather than rendering a value.
  **Masked and forbidden must not look the same** — the panel already renders `null` for a caller
  without `conversation:read` (`ui-inventory.md` §3.4), and that stays distinct.
- `authorization.md`, `tenant-isolation.md` and `data-model.md` gain the route, the column and the
  table. `personal-data.md` records that a reveal record is itself personal data **about an
  operator**.

## The rule this item must state and not implement

§5's amendment: **reveal counts belong in an audit view, never in the report a person is judged on.**
The counter exists to catch somebody copying the list before they leave. On a staff-comparison screen
it inverts: the operator who calls customers back reveals forty numbers and the one who does not
reveals two, and a manager reading that punishes the useful one — who then stops calling, to protect
their figure. Write that into the audit view's own description, and into `23-17`'s out-of-scope list.

## Out of scope

- The calendar's half — `23-12`, which consumes this event. It is a separate repository and therefore
  a separate branch and MR.
- Rung three, and any interface that implies it exists.
- Click-to-call or system-sent messages. They are what would make rung three real.
- Pairing reveals with confirmed callbacks. The denominator §5 asks for is the operator's own
  "I called and it is them" mark, which does not exist in chat at all — see `23-12`, which builds it
  where the concept already has a home, and the report.
- Changing what `Permission.ConversationRead` means. The permission still says "may read
  conversations"; the rung says *how* a contact inside one is shown.

## Done when

- [ ] A tenant on `Visible` sees today's behaviour, byte for byte — asserted, because this must not
      change the micro case, where the person reading the number **is** the tenant.
- [ ] A tenant on `MaskedWithReveal` gets masked values from the list read, and the unmasked value is
      not present anywhere in the list response.
- [ ] A reveal returns the value and writes exactly one record naming the operator.
- [ ] A caller without `ConversationRead` cannot reveal, and gets the same refusal the list gives.
- [ ] A caller of another tenant cannot reveal (a tenant-isolation test).
- [ ] The tenant can read the reveal record, and the screen says what it is for and what it is not.
- [ ] The event is published from the outbox in the write's own transaction, and a redelivery changes
      nothing (`messaging.md`).
- [ ] The four documents above carry the change.

## Open questions

None.
