# Personal data

What personal data this system holds, where it lives, why it exists, and how it is removed. Written
2026-08-25, as the prerequisite artifact for `roadmap.md`'s Stage 16 — deletion and export cannot be
built correctly against a system nobody has inventoried.

This file states facts about the system and the constraints they imply. It is not legal advice and
does not decide AGO's legal position; that determination is recorded as an open question in the
private `ago-business` repository and needs a lawyer, exactly the way `ago-business`'s own channel
research already gates Meta's Business API behind one.

## The shape of the problem

Almost none of the personal data here is AGO's own. The operator profile — an email address, a
display name, a password hash — is the small part, and the part whose fields AGO chooses. The bulk is
`messages.body`: free text typed by a visitor on somebody else's website. A support conversation
systematically collects "my name is Ivan, call me on +7…" because that is what support *is*; no field
choice or setting removes it, and the product would not work if it did. Attachments are the same
surface with a higher ceiling — a visitor can send a photo of a receipt, a contract, or an identity
document.

Two consequences follow, and they point in opposite directions.

**Minimisation is real but it works on retention, not on fields.** Dropping a profile field changes
little; not keeping conversations forever changes a lot. That makes the history window and the pruning
mechanism (`backlog/15-04`) the strongest privacy levers in the backlog, which is not how either was
originally framed. **Decided in shape 2026-08-25** (`adr/0031`): history is time-boxed, per tier, and
archived rather than deleted — which means the liability moves to the archive rather than ending, and
the published policy has to say so. The window's length waits on `15-05`'s measurement. It is also
why an operator avatar has deliberately **not** been added: an image of a person's face is a further
category of data plus another upload path with its own deletion, quota and moderation surface, for a
benefit initials already provide (author's decision, 2026-08-25).

**Erasure is nevertheless tractable here, by earlier design luck.** Message content lives in exactly
two places. `MessageAccepted` deliberately carries no body ("a consumer that needs it reads
`GetConversationHistory` instead"), and webhook deliveries deliberately carry none either ("never a
message body", `backlog/6-05`). So the outbox and the delivery log hold no copies of the text — the
usual reason erasure in an event-driven system is intractable does not apply.

## Where it lives

| Store | Personal data | Why it is there | Removal path |
|---|---|---|---|
| `messages.body` (Postgres) | Free text; anything a visitor or operator typed | The product | Row deletion, or partition drop (`15-04`) |
| MinIO objects + thumbnails | Attachment bytes; anything a visitor uploaded | The product (`file-storage.md`) | Object deletion; `5-04`'s sweeper already deletes orphans |
| Keycloak database | Email, first/last name, password hash, sessions | Authentication (`adr/0022`, `adr/0028`); email is required, not optional — `10-01` gates accounts on verification and `10-05` adds password reset | Keycloak user deletion (needs `15-01`'s persistent store to be meaningful) |
| `sites.name`, `allowed_origins` | The customer's business identity, not a natural person's | Tenancy, CORS (`5-01`) | Row deletion |
| `visitors.token_hash` | A pseudonymous identifier — not a name, but it singles out a returning person | Recognising a returning visitor (`vision.md`) | Row deletion |
| Redis | Rate-limit buckets, including one keyed by client IP (`RegisterSiteHandler`); presence; connection registry | Abuse control (`3-05`), realtime (`3-01`) | Expires on its own TTL; never a source of truth (`caching.md`) |
| Edge access logs | Client IP per request | NGINX's own logging (`edge.md`) | Log retention — **not currently defined anywhere** |
| Traces / metrics | Unverified — spans may or may not carry identifiers or content | Observability (`7-01`, `7-02`) | Unverified; `backlog/16-05` is the audit |
| Retention archive | Expired conversation history, in `16-03`'s export format | `adr/0031`: expired history is archived rather than deleted, retrievable as a file on request | Object deletion — and the store's class must permit it, which `adr/0031` records as a selection constraint |
| Backups | Copies of all of the above | Recoverability (`15-02`) | Retention window only — see below |

Two stores that carry **no** personal data, deliberately, and should stay that way: `outbox.payload`
and `webhook_deliveries.payload`, both body-free by contract. `operators` holds no name or email
either — identity lives in Keycloak and is joined by `external_subject_id` (`authorization.md`), so
the application database never duplicates it. A change that adds a name column to `operators`, or a
body to an integration event, is not a small change; it converts erasure from a two-place problem
into a five-place one.

## Standing constraints

These are constraints on decisions the backlog has already opened, and they exist here so they are
applied rather than rediscovered per item.

**Data residency.** Russian law requires personal data of Russian citizens to be processed in
databases located in Russia. The deployment already is (`adr/0026`, a Russian VPS) — but that was a
cost and latency decision, not a data-protection one, and nothing recorded it as a constraint until
now. It binds three open vendor questions directly: `10-05`'s email provider, `15-02`'s off-node
backup destination, and any future object-storage or SMS vendor (`20-05`, `14-03`). Each of those
moves personal data across the boundary if answered carelessly. `15-06`'s container registry does
not: images carry no personal data.

**Deletion versus backups.** A restore returns what was deleted. The resolution here is a bounded
backup retention window, after which deletion is complete because no copy survives — written into the
privacy policy honestly rather than claimed as immediate (author's decision, 2026-08-25). The
alternative considered and rejected was a deletion journal replayed after every restore: more precise,
but the journal is itself a list of people who asked to be forgotten, which is a worse thing to hold
than the short window it removes. `15-02` must set its retention to a number this policy can state.

**Who answers to whom.** Working direction, to be confirmed by the lawyer and recorded in an ADR by
`backlog/16-04`: AGO is the controller for its own account holders' data (they registered with AGO),
and a processor acting on the tenant's instruction for visitors' conversation data (the visitor was
the shop's customer, not AGO's). That split is what makes tenant-initiated export and deletion a
product requirement rather than a courtesy, and it is why the widget carries a processing notice the
tenant configures (`16-04`) — AGO supplies the mechanism, the tenant owns the text and its accuracy.

## What is not decided here

The legal questions — notification to the regulator, the published policy and offer text, the
processing clause in the tenant agreement, and whether any given incident is notifiable and on what
deadline — belong in `ago-business` and to a lawyer. What this file commits to is the engineering
side: knowing where the data is, being able to remove it, being able to hand it over, and not
quietly widening the list above without noticing.
