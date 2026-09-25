# 26-134 → ADR-0184 (option B) — implementation program

The scoping pass concluded ADR-0184 **cannot be one ticket**: it spans ago-chat, ago-calendar and
ago-console (+ago-android on the read side), deletes the live, wire-bearing `ago_calendar.customers`
table, and needs **three serialized EF migrations** (calendar lane, one at a time). A single ticket
would leave a gate red between "add person id" and "delete the copy" — the split rule 15 forbids. The
shape is **expand → migrate → contract**, each slice green on its own.

Author decisions on the open questions (2026-09-25): **O1** keep the phone on the calendar operational
record (needed for the verified-phone gate + per-phone rate limit; chat still owns the canonical channel
list) — yes. **O2** retire the calendar merge for now (one person id makes duplicates rare; revisit as a
chat-side merge only if wanted) — yes. **O3** move operator notes-about-person into chat **before**
deleting the copy, so notes never regress — yes. **O4** ago-android is a required fourth repo in the
read-side slices — yes.

## Ordered slices

**S0 = 26-124** *(ago-console; no migration; independent)* — VisitorHistoryPanel renders unconditionally
(the `hasChannelIdentity` gate is gone). Closes 26-124.

### EXPAND (additive; nothing deleted)
- **S1 = 26-136** *(ago-chat + ago-calendar; migration M1)* — the booking `Event` records `person_id` +
  `origin_conversation_id`; chat populates them from `conversation.VisitorId`/`.Id`, calendar mints a
  person id when none is supplied. Additive nullable wire fields. **Subsumes 26-112 C1.**
- **S2** *(ago-chat; no migration)* — chat exposes a Person read API (display name + contact channels by
  person id) for console-side display-merge.
- **S3** *(ago-calendar; no migration)* — calendar booking/contact read DTOs carry `person_id` (additive;
  old name/notes/phone fields stay for now).

### DISPLAY-MERGE (read side switches name source to chat; still additive)
- **S4** *(ago-console + ago-android)* — Записи/bookings/contacts show the person's real name (from chat
  via person id) and the two-way dialog↔booking link. **Closes 26-132 and 26-133.**

### CONTRACT (the wire-breaking deletes; safe once S1–S4 shipped)
- **S5** *(ago-calendar; migration M2)* — rule-8 facts (no-show count, verified/confirmed-phone, +phone per
  O1) move to a thin `person_id`-keyed operational record; the booking write gates on it in-transaction.
- **S6** *(ago-chat + ago-calendar; no migration)* — remove the `ContactCollected → customer` replication
  (consumer first, then publisher).
- **S7** *(ago-calendar + ago-console; no migration)* — retire the calendar-side merge (23-60) per O2.
- **S8** *(ago-calendar + ago-console + ago-android; migration M3)* — delete the `customers` person-copy;
  `Event` FK repoints to `person_id`; calendar stops serving name/notes (S4 already display-merges them).

### Phase 4 (separable follow-ons, each its own ticket)
- **S9** operator notes-about-person in chat *(ago-chat + ago-console; chat migration)* — per O3, land
  before S8 so notes never regress.
- **S10** `PersonRegistered` for no-chat-origin bookings *(ago-calendar publishes, ago-chat consumes)* —
  dormant today (public endpoint gated shut, no operator-create path); thin.
- **S11** person `creditworthy` + reliability in chat + console — the "set once, seen everywhere" aspiration.
- **S12** chat-side Person merge — only if O2 is later reversed.

## Migrations (rule 13 — serialized, calendar lane)
**M1** (S1: events gain the two ids) → **M2** (S5: operational record) → **M3** (S8: drop the copy). One
chat migration in S9, independent of the calendar lane. Never concurrent.

## Non-blocking review items
- `personal-data.md` rewrite to the two-store/one-identity shape (calendar becomes a thin operational record;
  person attributes consolidate in chat; erasure = delete one chat Person, cascade calendar record + events
  by id). Its own doc ticket, author-reviewed, not gating the code slices.
- Consent wording (adr/0147 / 24-05 / ago-business): copy-removal *narrows* the data flow, likely easing the
  question — still confirm the person-registry framing. Flag for review, non-blocking.

Full grounding (file:line evidence) is in the round-2 scoping report; the decision is ADR-0184.
