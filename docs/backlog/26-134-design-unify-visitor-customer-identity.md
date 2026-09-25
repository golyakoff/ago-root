# 26-134 · Design: should visitor/customer identity be a shared resource across chat & calendar (finish what adr/0027/0093 started)?

- **Stage**: 26 — an ADR-level design/analysis pass (no code). Reconsiders a boundary the author has hit
  repeatedly in practice.
- **Status**: ready — the author wants a genuine reconsideration; `26-133` (the copy-not-link bug fix) is
  frozen pending the outcome, because the fix's shape depends on it.
- **Found**: 2026-09-25 — recurring pain: "a chat visitor is not the same as a calendar customer", surfaced
  again by `26-132` (the booking name lost across the chat→calendar boundary).

## The real question
`adr/0027`/`adr/0093` decided **"domains stay apart, but tenancy and identity unify."** That principle looks
applied to **operators/tenancy** but NOT to **visitors/customers** — chat has its own visitor/contact, the
calendar its own customer, and they are reconciled only by event replication (and, per `26-132`, sometimes
not at all). So: **should a person's identity (visitor in chat, customer in the calendar) be ONE shared
resource that every product references, rather than duplicated per product?** Is the current split a
mis-application of adr/0027's own "identity unifies" ruling?

## The pass must deliver (evidence first, then options, then a recommendation)
1. **Evidence of the pain**: catalogue every place the chat-visitor ≠ calendar-customer split causes
   friction or data loss today — `26-132` (name/email dropped), the `ContactCollected` replication
   (`ContactCollectedConsumer`, `ContactCollectedCustomerStore`, keyed on `source_contact_id`), the
   calendar `customers` table vs chat `visitors`/`visitor_contact_details`, any duplicate/near-duplicate
   modelling, and how `26-112`'s `origin_conversation_id` link relates. Cite files.
2. **Restate the boundary rules that constrain the answer**: `adr/0012` (platform ships as NuGet, no shared
   data — so identity is NOT platform infra), `adr/0027`/`adr/0093` (domains apart, identity/tenancy unify),
   `adr/0065` (module seam). Chat is a **product**, not the platform — so "use the platform's contacts" must
   be read as "one product owns identity and exposes it", not "put contacts in Ago.Platform".
3. **Options, each with cost + migration + what breaks**:
   - Status quo (replicate by event; copy per product) — cheapest, keeps the pain.
   - **Chat owns the person as the shared identity; the calendar REFERENCES it** (reads via a contract/query,
     stops keeping its own `customers` copy, or keeps only a thin FK) — makes "chat user == calendar user"
     by construction; the likely direction if adr/0027's identity-unification is meant to reach contacts.
   - A dedicated shared identity capability both products depend on.
   - Assess each against the dependency rule, the NuGet/no-shared-data constraint, per-product deploy/erasure
     (`16-02`/`personal-data.md`), and the migration cost with zero real tenants (cheap now).
4. **Recommendation + a draft ADR** (amending/supersede-relationship to adr/0027/0093 stated), and how
   `26-132`/`26-133` collapse into it (the name-loss fix likely becomes "reference the shared identity",
   not "copy").

## Out of scope
- Any implementation. This decides the direction; implementation tickets follow the author's approval.

## Done when
- [ ] A design doc with the evidence, the options+costs, a recommendation, and a draft ADR — enough for the
      author to decide whether to unify visitor/customer identity, and if so, how.
