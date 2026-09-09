# erasing a tenant reaches both databases, and the second half is proved rather than assumed

- **Stage**: 22
- **Status**: done — `ago-chat#226`, `ago-calendar#50`
- **Depends on**: `22-03`, `22-11` (the registration channel this reaches the module over), `24-13`
  (the erasure receipt this extends)
- **Decision**: `docs/adr/0149-*` — accepted, with one stated divergence, see Outcome.
- **Split out of `22-08`** on 2026-09-07 (rule 15). Its own promise, its own gate.

## Goal

Erasing a tenant removes their rows from both databases, and the system can show that the second half
happened rather than that a message was sent about it.

## What is actually true today, verified 2026-09-07

- **Chat's half is complete and careful.** `SiteErasureJob` stamps every conversation, refuses to
  delete the site row until they have actually drained (`HasAnyConversationAsync`), deletes the site's
  archive objects, invalidates both cache keys, deletes Keycloak users last because that is the step
  most likely to fail, and keeps a receipt in `erasure_records` (`24-13`) that it marks `Failed` on a
  throw rather than leaving it looking pending. **The pattern this item needs already exists on the
  chat side**: a gate that waits for a fact to be *observed* before the irreversible step runs.
- **The calendar has no erasure at all.** Nothing anywhere deletes a `Tenant`. Everything under it
  cascades (`customers`, `events`, `workers`, `operators`, `pending_phone_verifications`,
  `chat_module_registrations` and the rest of `Stage20CreateCalendarSchema`'s nine foreign keys) — but
  only if something deletes the row, and nothing does.
- **The calendar holds no object storage.** Its only infrastructure projects are Postgres, Redis and
  Time; there is no `IFileStorage` caller. So its erasure is a row delete, with no equivalent of
  `24-09`'s archive rewrite. `personal-data.md` predicted this ("erasure there is *easier*, because a
  person is a row rather than a substring of free text") and it is correct.
- **The one residue, already argued elsewhere and not to be re-litigated here**: the calendar's
  `outbox.payload` carries a `customer_id` and is never pruned. `personal-data.md`'s own row says
  deleting the lead card "leaves every already-staged `BookingConfirmed` pointing at an id that no
  longer resolves — which is the correct outcome for an erasure, and is only correct because the
  payload carries the id and not a copy of the person." Same argument at tenant scope. Cite it; do not
  redesign it.

### The hole this item was written after finding

**A site erased after its calendar add-on was revoked erases half of a person's data and reports
success.** Verified by reading both handlers:

1. Chat's `RevokeModuleForSiteHandler` **deletes** the `EnabledModule` row. That row is the only place
   the per-site `EntryPoint` and `Credential` live (`HttpModuleGateway` has no `BaseAddress` —
   "a module's entry point is a per-site, per-module value read from the registry at call time").
2. It calls the calendar's `RevokeChatModuleRegistration`, whose handler deletes the
   `chat_module_registrations` row **and nothing else**. Its own remarks are explicit that the point is
   to make a credential stop working immediately.
3. So after a revoke: the tenant's `customers` (a phone number, a name, notes, a no-show history —
   `personal-data.md` calls it "the most directly identifying store either product has"), `events`,
   `workers` and `operators` all stand, chat has no address to reach them at, and no record that they
   exist.
4. A later `POST /api/v1/sites/{siteId}/erase` completes normally, writes a `Completed` receipt, and
   the calendar keeps everything.

A **lapsed** grant is a different and milder case: the row still exists (`EnabledModuleReadStore.GetAllForSiteAsync`
deliberately applies no `expires_at` filter, for `23-14`'s support case), so the address survives. This
item must read the unfiltered set: **a lapsed grant still means the calendar holds this tenant's data.**

## Scope

- **The calendar gains a tenant erasure**: an operation, authenticated the way `22-11`'s registration
  calls already are, that removes the tenancy row and everything under it — and, separately, can be
  *asked* whether anything remains for a tenant id. The second half is the point: the answer to "did
  it work" must be a read of the calendar's own database, not an acknowledgement of a message.
- **Chat's `SiteErasureJob` gains a second gate**, beside the conversations one it already has: the
  site row is not deleted until every module the site is known to have answers *nothing left*.
- **Ordering is load-bearing, not cosmetic** — the same class of reason that method's own remarks
  already give for reading archive keys and Keycloak subjects before the delete. Modules first, chat's
  own row last: `EnabledModule` cascades with `sites`, so the moment the site row goes, the address of
  every module holding that tenant's data goes with it and the erasure can never be finished or even
  described.
- **A module that cannot be reached never auto-completes.** After a stated window the receipt is
  marked `Failed`, naming the module and the tenant, and a `Failed` receipt is retryable and visible.
  Erasure has a clock on it in the outside world; "still pending on day twenty-five" has to be
  something a person can see.
- **The revoke hole is closed here**, because this item's promise is false without it. Which way it is
  closed is the Open question below.
- `personal-data.md`'s AGO Calendar rows gain a real answer in their "What removes it" column, which
  today says "Row deletion; `ON DELETE CASCADE` from `tenants`. Nothing automatic."

## Out of scope

- **A *person's* erasure across both products.** `personal-data.md` already records why it cannot be
  one operation: "the two products share no key… the same human is a `customers` row in one database
  and a `visitors` row plus message text in another, with nothing linking them." Named here so nobody
  assumes this item covered it. A cross-product subject erasure needs a linking decision first, and
  that is a product question, not this item's.
- **`24-09`'s archive erasure.** Chat's half is correct and shipped; the calendar has no object
  storage, so nothing here reaches an archive and nothing here makes it worse. Checked, stated, moved
  past.
- Suspension (`22-08`), export (`22-31`), reconciliation (`22-32`).
- Pruning the calendar's outbox — see above; `15-04`'s equivalent is the item that would.

## Done when

- [x] Erasing a tenant with a calendar add-on leaves no `tenants`, `customers`, `events`, `workers` or
      `operators` row for them, **proven by erasing one and querying the calendar's database**, not by
      reading the job.
- [x] The chat-side site row is still standing at the moment the calendar's half is confirmed —
      asserted, because the reverse ordering is the failure that cannot be recovered from.
- [x] A module that does not answer leaves the receipt `Failed` with the module named, and the site
      row undeleted. Proven by making the module unreachable.
- [x] The same erasure works for a tenant whose grant has **lapsed**, and for a tenant whose add-on was
      **revoked** — the two cases the Open question below separates.
- [x] `personal-data.md`'s AGO Calendar rows name what removes them.

## Outcome

The recommended answer to the Open question was taken: **revoke tombstones instead of deleting.**
`EnabledModule.RevokedAt` is stamped so a later erasure can still find the module; the module-side
revoke call still runs first so `22-11`'s guarantee (the credential dies immediately) is intact, and
every existing read of "is this enabled" gained a `revoked_at is null` filter so nothing behaves
differently today except the one new caller that needs the history.

**One deliberate divergence from `adr/0149`'s literal wording, written up rather than silently
reinterpreted**: erasure reaches a module over the deployment-wide provisioning secret, not the
per-site call credential the ADR's prose names — because that per-site credential is exactly what a
revoked or never-registered tenant lacks, which is the hole this item closes. The ADR's intent ("the
module proves it") is honoured unchanged.

The one-hour unreachable-module bound is a stated implementer's bound, not a measured SLA — named as
such per `CLAUDE.md`'s ban on inventing production figures. `(SiteId, ModuleKey)` still has no
uniqueness constraint (a pre-existing gap, not introduced here); reads are filtered so nothing
behaves differently today, and the gap is named rather than folded in silently.

## Open questions — resolved, see Outcome above

- **After a tenant cancels the calendar add-on, who is responsible for their booking data — and can
  the automatic erasure path still reach it?** Three answers, all defensible, and today's behaviour is
  the first one by accident rather than by choice:
  - **It survives, and chat forgets.** Today. Resubscribing restores everything, which is kind; but
    erasure and export both silently miss it, which is the hole above. Not tenable once a real tenant
    exists.
  - **It survives, and chat keeps a tombstone.** The `EnabledModule` row is stamped revoked rather than
    deleted, so the entry point survives as the channel of record for lifecycle operations even though
    it no longer routes anything. Cost: a schema change, a new state on a row `adr/0098` deliberately
    kept stateless, and a decision about the credential — the calendar's revoke deletes its own
    registration, so chat would either have to stop doing that (weakening `22-11`'s "a revoked secret
    stops working now") or re-register at erasure time with the provisioning secret, which is
    `decisions.md` §6's amendment arriving earlier than planned.
  - **Revoke deletes, after a stated grace period.** A clean lifecycle with no orphans. Rejected here
    rather than offered as equal: `22-07` already decided that a billing action deactivates and never
    destroys — "nothing a shop typed is destroyed by a billing action" — and this would be exactly
    that, at whole-product scale. It is listed because a reader will think of it and deserves to see
    why it lost.
  - The second is the recommendation. It is the only one where the promise in this item's Goal is true
    for every tenant rather than for the convenient ones.

- **How long is "cannot be reached" before a receipt is marked `Failed`?** A commercial judgement
  about how long an erasure may take before somebody is told it is stuck, not a technical one. It
  should be well inside whatever window the tenant was promised, and the item should state the number
  rather than inherit it.
