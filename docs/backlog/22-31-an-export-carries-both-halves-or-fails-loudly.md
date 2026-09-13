# a tenant's export carries both halves, or fails loudly

- **Stage**: 22
- **Status**: ready — build as written; the transport question below is answered (2026-09-13).
- **Depends on**: `16-03` (the export machinery this extends), `22-30` (whichever answer its Open
  question takes about reaching a module after a revoke — this item needs the same reach)
- **Decision**: `docs/adr/0149-*` — **Accepted** (rules 1–3; its own "two parameters" section is
  superseded by `adr/0166` for `22-08`, unrelated to this item). Its third rule, that chat never parses
  a module's data, is what decides the archive's shape here. `docs/adr/0072-*` is the format this
  extends.
- **Split out of `22-08`** on 2026-09-07 (rule 15).

## Goal

A tenant who asks for their data gets everything AGO holds for them, from both databases, in one
archive — or an export that failed and says which half was missing. Never a quietly partial one.

## What is actually true today, verified 2026-09-07

- **Chat's export is built and good.** `SiteExportJob` claims a pending export, streams row by row
  onto a bounded temp file and uploads it presigned; `SiteExportArchiveWriter` writes
  `manifest.json` (with an explicit `formatVersion`) plus `site.json`, `operators.jsonl`,
  `visitors.jsonl`, `channel_identities.jsonl`, `conversations.jsonl`, `messages.jsonl`,
  `attachments.jsonl`, `notes.jsonl`, `tags.jsonl` and `conversation_tags.jsonl`. `adr/0072` is the
  format decision.
- **The calendar has no export of any kind.** A tenant's `customers`, `events`, `workers`, `services`
  and schedule exist in one database and leave it by no route at all.
- **So today an export is silently partial**, and silence is the specific failure this item names: the
  archive looks complete, has a manifest, and does not say that a whole product's worth of the
  tenant's data is not in it.
- **`24-11` shipped the narrower scopes** — per-conversation and per-visitor export, synchronous,
  reusing `16-03`'s format. All of it is chat-only. That matters for the section below.

## This is the tenant's export. It is not a subject access request, and the item must not blur them

The two want the same machinery at different scopes and are governed by different rules. Stating it
here because it is the mistake this item is most likely to make while looking finished:

| | Tenant export (`16-03`, this item) | A visitor's own request (`24-11`) |
|---|---|---|
| Who asks | the account holder, about their own account | a person, about themselves |
| Scope | every row belonging to the tenant | that person's rows only |
| Why | portability — taking their asset with them | a right they hold over AGO and the tenant |
| Crosses to the calendar? | **yes, this item** | **no, and it cannot yet** |

The last cell is the load-bearing one. `personal-data.md` records it plainly: the two products share
no key for the same human — "a `customers` row in one database and a `visitors` row plus message text
in another, with nothing linking them" — so a person-scoped export across both **cannot be executed as
one operation**. This item builds the tenant-scoped crossing and must not be read as having built the
other. Anything that would join a `visitors` row to a `customers` row is a product decision about
identity that nobody has taken, and taking it accidentally inside an export job is the worst place to
take it.

## The design, and why the module's half is opaque

Chat asks each module for that tenant's data over the credentialed per-site channel, and the answer
lands in the archive as **one opaque member the module produced**, with its own internal format and
its own format version, listed in `manifest.json`. Chat never parses it.

That is not fastidiousness, it is the invariant the whole product boundary rests on: there is no
`calendar` literal and no `using Ago.Calendar` anywhere in `Ago.Chat.*`, and an architecture test
enforces it. An export writer that emitted `workers.jsonl` would be the moment chat learned what a
module *is* — the boundary crossing arriving through a data format instead of a project reference,
which is exactly the failure `ModuleKey`'s own remarks describe for an enum.

The manifest gains a `modules` array: for each, its key, whether it was included, its own format
version, and the byte count. A reader of the archive can then tell "no calendar data" apart from "this
tenant has no calendar", which today's manifest could not express.

## Scope

- A module-side export operation on the same channel `22-11`'s registration calls use, returning that
  tenant's data as one artifact.
- `SiteExportArchiveWriter` embeds it as an opaque member and records it in `manifest.json`.
- **Failure is loud.** If a module the site is known to have cannot be reached, refuses, or returns
  something the archive cannot embed, the export is marked `Failed` with the module named — the same
  `TryMarkFailedAsync` path the job already has for its own errors. There is no partial-success state,
  because a partial export that presents itself as complete is worse than no export at all: it is the
  one a tenant forwards to somebody as the answer.
- The calendar's export honours the same rules chat's does: `adr/0072`'s presigned-link decay, and no
  buffering a tenant's whole history in memory.
- `file-storage.md` and `personal-data.md` updated: the export archive is a new place a tenant's
  calendar data exists, with the same lifetime the chat archive already has.

## Out of scope

- **A person-scoped export across both products.** Above. It needs a linking decision first.
- Changing `adr/0072`'s format or the expiry of the presigned link.
- The export archive's own pruning. `24-09` explicitly left it out of erasure's reach ("different
  artifact, different purpose, different lifetime — and pruning it is a retention decision rather than
  an erasure one"), and that is unchanged; this item makes the artifact bigger, not longer-lived.
- Suspension (`22-08`), erasure (`22-30`), reconciliation (`22-32`).

## Done when

- [ ] An export of a tenant with the calendar add-on contains the calendar's half, and `manifest.json`
      names it — proven by opening the archive.
- [ ] An export of a tenant whose calendar cannot be reached is `Failed`, naming the module, and no
      archive is published. Proven by making the module unreachable.
- [ ] `manifest.json` distinguishes "this tenant has no calendar" from "the calendar's half is
      missing".
- [ ] Nothing in `Ago.Chat.*` reads a field of the module's half — asserted by the existing
      architecture guard, which must still pass with no new exemption.
- [ ] The difference between this and a visitor's own request is written where the next person will
      read it: `personal-data.md`, and `24-11`'s own file.

## Answered, 2026-09-13

**The module's half arrives as bytes over the existing channel** — the same one `22-11`'s registration
already uses — and chat copies them straight into the archive. The author chose this over standing up
object storage for the calendar purely to serve this one item: the calendar has none today, and this
item is not the reason to build it.

That means `ResilientModuleGateway`'s timeouts, sized for a visitor message, now also have to carry a
whole tenant's calendar history in one call — the operational cost this section named as option A's
price. Two things this decision commits the implementation to:

- **The export path needs its own timeout/size budget on this channel**, not the visitor-message one
  reused as-is — a large tenant's calendar history is a different shape of payload than a chat message,
  and sizing it the same way as `20-07`'s module-flow steps would be the mistake worth avoiding.
- **If a tenant's calendar half ever gets too large for one call to carry reliably, that is a real
  problem to hit and solve then** — with actual numbers from a real export, rather than building
  object storage speculatively now for a case that may never arrive. This is a deliberate "revisit
  when it hurts" choice, not an oversight - stated here so it reads as one.
