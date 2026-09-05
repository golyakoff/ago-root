# The processing instruction: the facts, sourced and dated

`152-ФЗ` art. 6 ч. 3 requires the instruction under which one party processes personal data on
another's behalf to state specific things. **Every one of them is a fact about this system that only
these repositories know.** This file is those facts, each with the file it came from and the date it
was checked, so that whoever drafts the clause in the tenant agreement drafts from the system rather
than from a description of it.

Written 2026-09-05 by `24-06`, against `ago-chat` at `badecaf`, `ago-deploy` at `d27d92d`,
`ago-calendar` at `cf77c7f`, `ago-widget` at `27a94c4` and this repository's `main` at `bee0f16` —
the local checkouts as of that date.

**This is not legal text and it is not legal advice.** The agreement's clause, the published policy,
the offer and the regulator notification belong to `ago-business` and to a lawyer
(`personal-data.md`, "What is not decided here"; `roadmap.md` Stage 24's own framing). Statutory
citations here are for orientation only: which element a given fact satisfies, and whether it
satisfies it at all, is the lawyer's determination. What this file commits to is that **the facts are
true on the date beside them**.

**Where the honest answer is "we could not produce that today", it says so and the gap carries a
backlog number.** An instruction that overstates what the system does is the failure this whole item
exists to prevent — a clause that is wrong in the direction nobody checks. The eight gaps are listed
in *Gaps* below; none of them is fixed here, by design (`24-06`'s own Out-of-scope).

**The register is `personal-data.md`.** This file does not duplicate it. It answers seven questions
*from* it, adds the facts the register did not hold (what leaves the deployment, and what evidence
could be produced), and corrects it where this pass found it stale — see *What this changed in
`personal-data.md`* at the end.

## Scope of this file

AGO Chat, and AGO Calendar where the register already covers it. The two products are separate
deployments with separate databases (`adr/0027`), separate tenants and therefore separate
instructions: **one tenant agreement's clause cannot cover both**, and this file marks every Calendar
fact as such rather than blending them.

---

## Element 5 first: where the data physically is

Answered first because `24-06`'s own Open questions say so — it is the element most likely to produce
a finding rather than a citation, and the finding is real.

### What is established

**One machine holds every primary store.** `adr/0026` (2026-08-24) put the deployment on a single VPS:
Postgres (both `ago_chat` and `keycloak`), Redis, RabbitMQ, MinIO and Keycloak all run on it as
containers under k3s. Nothing in `ago-deploy/k8s/` places a stateful workload anywhere else, and the
backup set (`adr/0050`) is exactly those two databases plus the MinIO objects — which is the same
statement from the other direction. The node's address is never written in a public repository; it is
`<node-ip>` here as everywhere (`repositories.md`).

**The provider and the advertised region.** Fornex, "Cloud NVMe 6" (4 vCPU / 6 GB / 80 GB NVMe),
**Russia location**, Ubuntu 24.04 LTS — `adr/0026`'s own "Post-decision update", repeated in
`runbooks/public-deploy.md:55`. Fornex is a **Spain-registered** provider operating a Russia-region
line; that is stated in the same ADR and it matters, because the corporate domicile of the provider
and the physical location of the machine are two different facts and only the second one is about
where data sits.

**Backups do not cross a boundary the deployment does not already cross** (`adr/0050`, 2026-08-25):
one encrypted artifact per run, staged on the node, pulled over existing SSH to the author's own
machine, encrypted to a key the node does not hold. No vendor, no third-party storage. Redis and
RabbitMQ are deliberately **not** in the backup set.

**Transactional email does not leave the machine either** (`adr/0040`'s amendment; `secrets.md`
A, `KEYCLOAK_SMTP_PASSWORD`): Keycloak talks to the node's own Postfix across the cluster bridge, with
no SMTP AUTH and no TLS, because the hop never leaves the machine. There is no sending provider and
therefore no credential — the empty password is a decision, not an omission.

**The container registry is out of scope by `personal-data.md`'s own rule** — "the rule binds
destinations, not images" — and images carry no personal data (`adr/0047`, GHCR).

### The finding

**Nothing in any repository evidences that the machine is physically in Russia. The claim rests on a
purchase-page label.** `adr/0026` records what the author bought; `public-deploy.md` repeats it. There
is no traceroute, no geolocation check, no provider statement, no contract clause, and no invoice
recorded anywhere in these repositories. `personal-data.md` already flagged its own art. 18 п. 5
citation as "here for orientation, not as a reading" — what it did not say is that **the fact
underneath the citation was never established either**. It was assumed from the tier name.

**Updated 2026-09-05, later the same day: a RIPE registry lookup of the node's address returns
`country: RU`, `netname: RU-FORNEX`, holder Fornex Hosting S.L.** That is third-party evidence a
reviewer can check without our cooperation, and it is a real improvement on a tariff name — it also
dissolves the apparent contradiction above, since a Spain-registered entity holding a block registered
as Russian is ordinary rather than suspicious. It is still not the fact the statute asks about: a RIPE
`country` field records where a block is registered as being used, not where a machine physically
stands. The position is now *likely true, partly evidenced, still undocumented* — and `24-07` is
narrowed to obtaining one provider confirmation rather than to an open investigation.

That is not a formality. Everything else in this file is checkable by reading a file; this one is not,
and it is the element where being confidently wrong costs the most.

**Second, smaller, and in the same shape: the backup destination's location is recorded nowhere.**
`adr/0050` says "the author's own machine" and nothing about where that machine is. Every artifact
ever taken lives there, holding both databases and the MinIO objects. Only the author can answer it.

→ **Gap `24-07`.**

### What leaves the deployment anyway, and this is the part the register never held

Six external channel providers and one LLM vendor can receive message text or a direct identifier.
Verified 2026-09-05 by reading the adapters and their DI registration, not from documentation.

| Destination | What reaches it | When | Source |
|---|---|---|---|
| **MAX** (`14-02`) | Message text, attachments, the provider's own chat id | Per site, once a `channel_credentials` row for `ChannelKind.Max` exists | `MaxChannelAdapter`, `ChatModule.cs:364` |
| **Telegram** (`14-07`) | Same | Same, `ChannelKind.Telegram` | `TelegramChannelAdapter`, `ChatModule.cs:425` |
| **VK** (`14-08`) | Same | Same, `ChannelKind.Vk` | `VkChannelAdapter`, `ChatModule.cs:452` |
| **Avito** (`14-11`) | Same | Same, `ChannelKind.Avito` | `AvitoChannelAdapter`, `ChatModule.cs:476` |
| **WhatsApp / Meta** (`14-10`) | Same | Same, `ChannelKind.WhatsApp` | `WhatsAppChannelAdapter`, `ChatModule.cs:499` |
| **The visitor's own mail provider** (`14-09`) | Message text, attachments, the visitor's email address | Same, `ChannelKind.Email` — RFC 5321/5322 direct, no vendor in between | `EmailChannelAdapter`, `ChatModule.cs:518` |
| **YandexGPT** (`19-01` reply draft, `19-02` categorisation) | **The conversation's own message history**, as prompt context | **Only if AGO configures its own credentials** — see below | `YandexGptReplyDraftClient`, `YandexGptConversationCategorizerClient`, `ChatModule.cs:672`/`725` |
| **An SMS gateway** (`14-03`, `14-15`) | Nothing, today | **No adapter exists.** The only `IPhoneVerificationSender` registered is `UnconfiguredPhoneVerificationSender` (`ChatModule.cs:943`), and no SMS infrastructure project exists in `ago-chat` | `IPhoneVerificationSender`; `src/` listing |

Four facts about that table that change how it reads:

1. **A channel is the tenant's own act.** Nothing reaches a provider until that tenant stores a
   credential for it. The adapters are registered unconditionally; the *route* is per site. So these
   transfers are made on the controller's own configuration — which is exactly the shape an
   instruction can describe, and exactly the shape that has to be described rather than left implicit.
2. **Telegram's outbound path leaves Russia deliberately.** `adr/0070` (2026-08-28) measured 8 of 15
   direct requests to `api.telegram.org` from the node failing with no TCP connection at all, and
   routes the adapter's calls through a VLESS relay instead — **the author's own personal endpoint, not
   AGO infrastructure**, which that ADR names as an accepted gap "worth revisiting before any real
   paying tenant depends on Telegram specifically". Message text on the Telegram channel therefore
   traverses a hop that belongs to a private individual rather than to AGO or to the tenant.
3. **The two AI features are gated by AGO's credentials, deployment-wide, with no per-tenant switch.**
   `ChatModule` registers the real client only when an API key and folder id are present, and the
   `Unconfigured*` implementation otherwise. **Neither key is set in the demo overlay** — no
   `Categorization__`/`ReplyDraft__` or Yandex key appears anywhere in `ago-deploy/k8s/`, checked
   2026-09-05 — so no conversation reaches YandexGPT today. But the switch is AGO's, not the tenant's:
   the day AGO sets that key, every tenant's closed conversations start being sent to an LLM vendor for
   categorisation, and every tenant's operators can draft replies from one. A processor adding a
   processing purpose and a sub-processor on its own initiative is precisely what an instruction is
   supposed to constrain, and there is no per-site control to point at.
4. **Nothing here says what any of those providers retain.** That is not answerable from these
   repositories at all — it is each provider's own terms.

→ **Gap `24-08`** (the register gains these destinations, with per-vendor retention where it can be
established).

---

## Element 1 — the list of personal data

**Answer: `docs/architecture/personal-data.md`'s table, in full.** That file is what it is for; it
carries 30-odd rows, each with what is held, who controls it, how long, what removes it, and the file
the fact came from. It was verified against code, migrations and manifests on 2026-08-25 (`16-01`),
extended 2026-08-26 against real traffic on a running cluster (`16-05`), extended 2026-08-25 for AGO
Calendar (`20-01`), and corrected 2026-09-04 (`23-08`, `visitor_contact_details`).

For drafting, the shape matters more than the list, and it is stated in that file's own "The shape of
the problem":

- **The bulk of the data is free text nobody chose the fields of.** `messages.body` is what a visitor
  typed on somebody else's website; a support conversation systematically collects "my name is Ivan,
  call me on +7…" because that is what support is. No field choice removes it.
- **Attachments are the same surface with a higher ceiling** — a receipt, a contract, an identity
  document.
- **`messages.content`/`messages.actions` (`14-06`) cannot be described at all.** An opaque JSON
  payload written by whichever product produced the message; AGO Chat stores and renders it and never
  reads inside (`adr/0061`). The register says so plainly, and an instruction has to as well rather
  than implying a schema exists.
- **Two structured direct identifiers exist by design**: `channel_identities.external_address` (a
  phone number for SMS, a provider chat id otherwise — `14-01`) and `visitor_contact_details` (`14-14`,
  a phone or email an operator typed because a visitor said it out loud).
- **AGO Calendar is a different kind of product on this axis** and its instruction cannot reuse this
  one's wording: a phone number is `customers`' single mandatory field, and `events` is a behavioural
  record about a named person (`20-01`).

Checked 2026-09-05: the register's rows still match the migration list in `ago-chat`, with the
corrections recorded at the end of this file.

## Element 2 — the list of actions performed on it

The statute's own vocabulary is a list of operations. Mapped to mechanisms that exist, 2026-09-05:

| Operation | Does this system do it | The mechanism |
|---|---|---|
| Collection, recording | Yes | The widget and the six channel adapters; `SendVisitorMessageHandler`, `SendOperatorMessageHandler` |
| Systematisation, accumulation | Yes | Postgres, partitioned by retention class and tenant hash (`Stage13Repartition…`, `Stage15RepartitionMessagesByTenantHash`) |
| Storage | Yes | The stores in `personal-data.md`'s table |
| Amendment, updating | Yes, narrowly | `OperatorRepository.RefreshIdentityAsync` rewrites an operator's name/email at sign-in (`23-02`); notes, tags and contact details are editable. **Message bodies are immutable** — nothing updates one |
| Retrieval, use | Yes | The read stores (`adr/0004`, Dapper), the console, the analytics reports |
| Transfer / provision / access | Yes | Webhooks to the tenant's own endpoint (body-free by contract); the six channel providers; the LLM vendor if configured. See the table under Element 5 |
| Depersonalisation | **No mechanism.** | Nothing anonymises. The one place a value is hashed is a Redis rate-limit key (`20-03`/`20-10`), and `personal-data.md` says explicitly that this is pseudonymisation, not anonymisation, because the input space is enumerable |
| Blocking | **No mechanism.** | See the gap below |
| Deletion, destruction | Yes, partly | See the deletion table below |

**Deletion, in detail** — the jobs that actually run, all in `Ago.Chat.Worker`, all registered in its
`Program.cs` (verified 2026-09-05):

| Job | What it removes | Window |
|---|---|---|
| `ConversationErasureJob` (`16-02`, extended `23-08`) | One conversation: MinIO objects first, then messages in batches, notes, tags, the visitor's contact details, the row | On request |
| `SiteErasureJob` (`16-02`) | A whole site, cascading; and the Keycloak users, where that credential is configured | On request |
| `MessagePartitionPruneJob` (`13-06`) | A whole month's partition for one retention class, **only after `MessageArchiveGate` confirms an archive object exists**; plus the attachments those rows referenced | Per tier (`adr/0031`); `15-04`'s operational default is 3 months |
| `MessageArchiveJob` (`13-06`) | Moves, does not remove — writes the `.zip` the prune job waits on | — |
| `AttachmentOrphanSweepJob` (`5-04`) | Objects whose row never got a `message_id` | Continuous |
| `DemoTenantExpiryJob` (`8-07`) | A minted demo tenant entirely, including its Keycloak user | ~1 day |
| `OutboxPruneJob` (`15-04`) | Published `outbox` rows | **24 hours** |
| `InboxPruneJob` (`15-04`) | `inbox` idempotency rows | **24 hours** |
| `WebhookDeliveryPruneJob` (`15-04`) | `webhook_deliveries`, including `response_snippet` | **30 days** |
| `CronJob/log-retention` (`adr/0057`, `ago-deploy`) | Rotated container logs, including the edge access log and therefore client IPs | **14 days** |
| Prometheus TSDB / Jaeger ring (`adr/0057`) | Metrics / traces | 14 days or 768MB / 10 000 traces |
| Redis TTL | Rate-limit buckets, presence, the connection registry | Seconds to ~1 hour |

Three things that table does **not** cover, each stated in `personal-data.md` and each load-bearing
for an instruction:

- ~~**`message_archives` and its `.zip` objects are indefinite, and `ConversationErasureJob` does not
  reach them.**~~ **Closed by `24-09`.** Its own remarks used to still say "nothing archives today" —
  true when `16-02` was written and false since `13-06` shipped. `ConversationErasureJob` now rewrites
  every archive object the site has to drop the erased conversation's own lines, and `SiteErasureJob`
  deletes the object outright once a whole site's conversations have all been drained this way
  (`docs/adr/0108-*`; `personal-data.md`'s own `message_archives` row).
- **The tenant export archive** (`exports/site/{siteId}/{exportId}.zip`, `16-03`) is never pruned and
  is not reached by erasure either (`personal-data.md`'s own row).
- **RabbitMQ's leaked `deliver-to-connections.{node}` queues hold message text indefinitely** — durable,
  never deleted, one per replaced pod (`personal-data.md`'s own row; `NodeDeliveryConsumer`'s own
  remarks call the leak "accepted, not solved"). Not in the backup set, deliberately (`adr/0050`), so
  it does not propagate — but it is a place message text lives that nothing removes.

**Blocking is the operation with no mechanism at all.** A controller instructed to *suspend*
processing of one person's data — stop using it, without destroying it — has nothing to invoke.
`conversations.erasure_requested_at` (`Stage16AddErasureRequestedAt`) queues a deletion; there is no
state between "processed normally" and "gone". Naming it matters because an instruction that lists
the operations will list this one. → **Gap `24-10`.**

## Element 3 — the purposes of processing

Per store, because they are not one purpose and some are not obvious. Sourced from the item each store
arrived in; checked 2026-09-05.

| Store | Purpose |
|---|---|
| `messages.*`, `attachments`, `conversations` | Carrying and displaying the support conversation the tenant chose to run — the product itself |
| `messages.content`/`actions` (`14-06`) | Rendering a module's structured step (a booking, a choice) inside the same transcript, without AGO Chat reading its meaning (`adr/0061`) |
| `visitors` | Recognising a returning browser across conversations. Holds no identifier by design |
| `channel_identities` (`14-01`) | **Routing.** The external address is how an inbound message finds the right conversation; it is not optional and not a contact list |
| `visitor_contact_details` (`14-14`, `23-09`/`23-10`) | The tenant's own asset — a way to call the person back. Deliberately *not* a routing key and deliberately on no timer (`decisions.md` §4) |
| `conversation_notes` (`18-04`) | An operator's private working context. Structurally unreachable from any visitor-facing read path (`NoteLeakProofTests`) |
| `tags`, `conversation_tags` (`18-04`, `19-02`) | Categorising a conversation for the tenant's own reporting |
| `conversation_assignments` (`23-03`) | The tenant's workload numbers. Holds no personal data and deliberately survives a visitor's erasure (`decisions.md` §2) |
| `operators` (`23-02`) | Identifying who is answering, to the tenant and in the transcript. AGO is **controller** for this data (`adr/0076`) |
| Keycloak's user store | Authenticating account holders |
| `webhook_deliveries` | Supportability — "a webhook system without a delivery log is unsupportable" (`6-03`) |
| `outbox`, `inbox` | Exactly-once-effect delivery of integration events. Body-free by contract |
| Redis buckets keyed by client IP or hashed phone | Abuse limiting on the two unauthenticated public write surfaces |
| Edge access logs | Operating the service; the only component that sees the whole request line |
| Traces, metrics, logs | Diagnosing the system. Audited 2026-08-26 (`16-05`) for what they actually carry |
| Backups | Recovery. 30-day window (`adr/0050`), chosen so deletion can be honestly described as complete after it |
| `customers`, `events`, `workers` (**AGO Calendar**) | The booking itself, and the lead card the tenant keeps deliberately — including a no-show history |

## Element 4 — the duty of confidentiality

What actually keeps one tenant's data away from another, and away from people:

**Between tenants.** `tenant-isolation.md` is the classification, re-derived 2026-09-04 by a scripted
scan (`tools/tenant-isolation-scan/`, run twice with byte-identical output) against `ago-chat`'s
`main`: 112 use-case entry points, 75 permission-gated and 37 exempt with a stated reason each; 109
routes and hub methods carrying tenant data; **2 genuinely cross-tenant reads and 3 cross-tenant
writes in the whole codebase**, all reachable only through the platform-owner policy. A build-time
guard (`TenantScopeTests`) fails when a use case is neither gated nor explicitly exempt, in both
directions. Its own limit is stated rather than glossed: it detects a *missing* check, never a check
made against the wrong site — `17-01`'s real cross-tenant hole would not have tripped it, and
ownership comparisons are covered by per-branch tests instead (`authorization.md`).

**Between operators of one tenant.** RBAC (`adr/0016`), with the two widenings the register records
explicitly: `18-07` lets an operator read a past conversation of a channel-identified visitor they are
currently assigned to, and `20-12` (Calendar) put a customer's phone behind `customer:read` so a
tenant can have an operator who works the queue and never sees a phone number.

**People at AGO.** The honest answer is short and is a fact rather than a policy: **the platform-owner
realm role is granted to nobody in any repository** — the realm import defines it and grants it to no
one, deliberately, because that file is public (`authorization.md`); the real grant is a manual action
in Keycloak. And the node's SSH key lives on one machine, `~/.ssh/ago-vps-ed25519`, with password
authentication and root login off (`secrets.md` E, `17-05`). There is one Postgres role, not two, and
`secrets.md` says so and says why the split is not done.

**Secrets.** `secrets.md` (`17-03`) is the inventory: what exists, who holds it, what rotating it
costs, and the method by which the list was built so a reader can re-run it. It carries one open
finding, stated there specifically rather than obliquely, and this file does not restate it — the
project's rule is that an open weakness is fixed first and published as history afterwards.

**Two things a drafting lawyer will ask for and this project does not have:**

- **A record of the persons admitted to processing.** Today the answer is "one", which is why nothing
  records it, which is exactly how it stops being true silently.
- **Evidence of who read what — closed `24-12`, and worth reading for what it does *not* close.** Every
  isolation control above is *preventive*; until `24-12` the only audit table in `ago-chat` was
  `module_grant_audit` (`Stage22AddModuleGrantAudit`, 2026-09-04), covering a platform owner granting a
  module — not a single read of a single person's data. `access_records` now covers the reads that cross
  a boundary: the operator's cross-conversation history read and the platform owner's five cross-tenant
  surfaces. **It does not cover an operator opening a conversation they are a party to**, deliberately —
  that is the ordinary work the product exists for, and recording it would be a second copy of the
  busiest table's traffic. And it does not cover **AGO Calendar's `customer:read`** at all, which is a
  different repository on a different database and needs its own answer (`adr/0113`).

`secrets.md` also has a hole this pass found: **`CHANNELS_CREDENTIAL_ENCRYPTION_KEY`, the key that
encrypts every tenant's channel credentials at rest, is consumed by all three host manifests as a
`$(VAR)` substitution from `infra-credentials` and appears nowhere in that inventory** (checked
2026-09-05). The value is held correctly; the register of it is incomplete, and the file's own sweep 2
is exactly the sweep that would find it. → **Gap `24-14`.**

## Element 6 — producing evidence on request

Stated as *what could be produced today*, not what could be built.

**Could be produced today, from mechanisms that exist and have run:**

| Asked for | What exists | Source |
|---|---|---|
| Everything held for one tenant | A per-site export archive: conversations, messages, attachments by presigned URL, operators, visitors, channel identities, site configuration — `POST /api/v1/sites/{siteId}/exports` | `SiteExportJob`, `SiteExportArchiveWriter`, `adr/0072` |
| Deletion of one conversation, or one whole tenant | `POST /api/v1/conversations/{id}/erase`, `POST /api/v1/sites/{siteId}/erase` | `ConversationsEndpoints.cs:138`, `SitesEndpoints.cs:46` |
| The inventory of what is held and where | `personal-data.md`, every row cited | this repository |
| The isolation classification, reproducibly | `tenant-isolation.md` plus the two scripts that produced its counts | `tools/tenant-isolation-scan/` |
| Retention windows, and that something enforces them | `adr/0057`, `adr/0031`, `adr/0050`, plus the jobs listed under Element 2 | `ago-chat`, `ago-deploy` |
| That a backup restores | A verified restore procedure that has been run | `adr/0050`, `runbooks/backup-and-restore.md` |
| The decision record for any of the above | 90-odd ADRs | `docs/adr/` |
| Everything held for one person, scoped to a `visitors` row | One conversation, or every conversation the same `visitors` row has, plus that visitor's contact details and channel identities — `POST /api/v1/conversations/{id}/exports` and `.../visitor-export`. **Closed `24-11`, and the limit travels with it**: this promises completeness for one `visitors` row and never that two rows are the same human — nothing in this schema makes that link, and a tenant told otherwise would under-answer a real access request without knowing it (`adr/0109`) | `ExportConversationHandler`, `ExportVisitorHandler`, `PersonExportArchiveWriter`, `adr/0109` |
| Who reached a person's data across a boundary, and when | An `access_records` row per boundary-crossing read: the operator's cross-conversation history read and the platform owner's five cross-tenant surfaces, each with actor, kind, time and the resource reached. **Closed `24-12`, with two limits stated rather than discovered.** The set of recorded surfaces is *named*, not derived from a rule, so a sixth surface is an argument for widening it rather than proof it was covered; and `customer:read` in **AGO Calendar** is not covered at all — a different repository on a different database, which needs its own mechanism or a written decision that it does not | `AccessRecordRepository.cs`, `adr/0113`, `personal-data.md` |
| That an erasure ran, six months later | An `erasure_records` receipt per erasure request: scope, requesting operator, timestamps, per-step counts, and `Failed` with its reason where a cycle did not finish. **Closed `24-13`, and closed with a stated limit rather than fully**: the receipt names the tenant and the operator and *never* the erased person (`adr/0112`), so it proves that an erasure ran for the right site at the right time — it cannot answer *which visitor* from this table alone, and a conversation erased under a whole-site cascade leaves only the site's aggregate count. Correlating a receipt to a named person's request needs the tenant's own record of that request. **And `Completed` means reachable-now, not gone from backups**: `adr/0050`'s thirty-day window still applies | `ErasureRecordQuery.cs`, `adr/0112`, `personal-data.md` |

**Could not be produced today. These are the findings.**

- **Documentary evidence of where the database physically is.** → **Gap `24-07`.**
- **What a channel provider or the LLM vendor retains** once data reaches them. Not answerable from
  these repositories at all. → part of **Gap `24-08`.**

## Element 7 — security measures

Facts, with sources. This section deliberately describes **what exists**, not where the system is soft:
an open weakness in this project is fixed first and published as history afterwards, and any that are
already public are in `secrets.md`, `edge.md` and `personal-data.md` under their own headings.

- **Transport.** TLS at the edge, terminated by NGINX Gateway Fabric configured through the Gateway
  API, certificates issued and renewed automatically by cert-manager with an alert when renewal stops
  (`edge.md`; `adr/0014`, `adr/0045`).
- **Edge limits, live and verified rather than intended.** 30 requests/s per IP with burst 60, keyed on
  `$binary_remote_addr` across the whole Gateway, confirmed by a real 150-request burst returning
  `503`s; a 1 MiB request-body ceiling, confirmed with a real 2 MB body returning `413`
  (`edge.md`, `k8s/overlays/demo/gateway.yaml`).
- **Access-log format is a security decision, and was made.** The Gateway logs `$uri` — the normalised
  path with the query string already stripped — rather than the full request line, in **both** overlays,
  because a browser's SignalR client has nowhere to put a bearer token on a WebSocket upgrade except
  the query string (`17-02`, `edge.md`). The residual limit on nginx's *error* log is stated in
  `edge.md` and in `personal-data.md`; it is not restated here.
- **Network segmentation behind the edge** (`adr/0054`, demo overlay): the four static-file sites reach
  DNS and nothing else; the four stateful backends accept connections only from workloads with a reason
  to open one. Demo overlay only, and `edge.md` says why — "unenforced policy reads as protection".
- **Application-level limits** per tenant and per operation, in code where they can be tested rather
  than in an ingress annotation (`caching.md`; `edge.md`'s "what the edge must not be responsible for").
- **Authentication and authorization**: OIDC through Keycloak for operators; a signed, short-lived,
  renewable token for visitors with no server-side copy (`adr/0034`, `adr/0048`, `adr/0067`); RBAC
  with a build-time tenant-scope guard (`authorization.md`, `tenant-isolation.md`).
- **Secrets** are held in one Kubernetes Secret per overlay, generated from a `.env` that exists only
  on the deploying machine; no `.env` is tracked in any repository, confirmed by `git ls-files` and
  `git check-ignore` (`secrets.md` A). Tenants' webhook signing secrets and channel credentials are
  stored encrypted (`adr/0024`; `Channels__CredentialEncryptionKey`).
- **Backups are encrypted to a key the node does not hold**, with no escrow — `adr/0050` states the
  cost of that plainly, which is the same reason it is a real measure.
- **Telemetry was audited against real traffic, not read off the code** (`16-05`, 2026-08-26): 28 span
  attributes, 47 metric labels, 1.19 M captured log lines, searched for emails, tokens, client IPs and
  message bodies. One real leak was found later by carrying the audit's *premise* forward rather than
  its conclusion — a channel that authenticates in a URL path — and closed with a test that fails,
  printing the token, if the fix is unwired (`TelegramTraceUrlRedaction`).
- **Architectural guards run in CI**, not as convention: layering tests, the tenant-scope rule, and the
  module-key literal rule (`0-02`, `17-01`, `20-07`).

**What is not established here**: whether this set corresponds to any particular required protection
level. That is a determination about a threat model and a classification, and it is a lawyer's and the
author's, not this file's.

---

## Gaps

Every one of these is a gap rather than an oversight: in each case something was built correctly for
the question it was asked, and a different question was never asked of it.

| Item | Title | Why it is a gap |
|---|---|---|
| `24-07` | the node's location is a label, not evidence | `adr/0026` recorded a purchase; nothing was ever asked to *verify* a location, because until `16-01` residency was "a happy accident" and afterwards it was cited for orientation |
| `24-08` | the register says nothing about what leaves the deployment | `personal-data.md` was written 2026-08-25/26 and inventories *stores*; the six channel adapters and both AI features shipped afterwards, and its residency table still lists channel vendors as an unanswered question |
| `24-09` | ~~an erasure request cannot reach an archived message~~ — **closed** | `16-02` shipped before `13-06` and said so in its own remarks; the archive arrived and nothing closed the seam until this item did (`docs/adr/0108-*`) |
| `24-10` | a controller can erase, and cannot block | Erasure was scoped; blocking was never asked for, because the product question ("delete my data") and the statutory operation list are not the same list |
| ~~`24-11`~~ | one person's data, exported | `16-03` was scoped as *tenant* portability. Subject access is a different granularity and nobody noticed the two were both needed. **Closed 2026-09-05** (`adr/0109`) |
| `24-12` | nothing records who read a person's data | Every control built is preventive by design and each was correct for its own item; evidential logging was never any item's goal |
| `24-13` | an erasure leaves no record that it happened | `16-02` deliberately rejected a deletion *journal* (it would be a list of people who asked to be forgotten) and never separated that from a per-erasure receipt, which is a different artifact |
| `24-14` | the secrets register is missing the channel-credential key | `17-03` and `14-01`'s credential storage landed within days of each other; the inventory's own reproducible sweep would find it today |

## What only the author, or the running system, can answer

Listed rather than guessed. `24-06` had no access to any live system and used none.

- **Where the Fornex machine physically is**, beyond the tier label — and whether any document from the
  provider says so (`24-07`).
- **Where the backup machine is**, and where its copies live (`24-07`).
- **Where the Telegram relay egresses**, in the sense that matters for a transfer question. `adr/0070`
  names it as the author's own endpoint and does not state its location.
- **Whether the demo Keycloak realm's seeded demo passwords still hold** — since `15-01` the import
  only seeds on first boot, so this is live state changed through `runbooks/realm-operations.md`
  (`secrets.md` B).
- **Whether anyone currently holds the `platform-owner` realm role**, which is a manual grant in
  Keycloak and appears in no repository (`authorization.md`).
- **The demo node's kubelet log-rotation settings**, still unverified against the live machine
  (`personal-data.md`, "What is unestablished").
- **Whether AGO has configured a YandexGPT key anywhere outside `ago-deploy`.** From the repositories,
  the answer is no.

## The one element that is a decision, not a fact

**Which datasets the instruction covers at all is a decision, and it belongs to the author and the
lawyer.** `adr/0076` decided the engineering side's position — AGO is controller for its own account
holders and processor on the tenant's instruction for visitors' conversation data — and says in its
own text that it has no lawyer's signature and is *superseded, not edited*, if the confirmation lands
differently. `roadmap.md` Stage 24 already names the operator as the role that split does not resolve:
they registered with AGO, but the party to AGO's contract is their employer.

Nothing in this file resolves that, and the facts above do not depend on it — they describe the same
system whichever way it lands. But an instruction cannot be drafted before it is decided, because the
instruction is precisely the document that says which data AGO handles on somebody else's behalf.

## What this changed in `personal-data.md`

Three corrections, all made in the same change as this file, all in the direction of the register
having claimed *less* removal than the system performs:

1. **The `outbox.payload` row said "Forever … no `DELETE FROM outbox` exists anywhere in either backend
   repo".** `15-04` shipped `OutboxPruneJob` — a 24-hour window on published rows, registered in
   `Ago.Chat.Worker/Program.cs:243`.
2. **The `webhook_deliveries.*` rows said "Forever / Nothing automatic".** `WebhookDeliveryPruneJob`
   prunes them at 30 days, including `response_snippet` (`Program.cs:249`).
3. **"Retention, stated plainly" said "no outbox trim, no inbox trim, no webhook-delivery trim".** All
   three exist; `InboxPruneJob` is the third (24 hours, `Program.cs:255`).

Plus a pointer from the residency section here, and a pointer from that file to this one, so the two do
not drift — the same mechanism `personal-data.md`'s own "Keeping this true" section uses.

What was **not** changed, deliberately: the destinations table under Element 5 is not folded into the
register's own rows, because each row there needs a "How long" and a "What removes it" column that only
the vendor can answer. That is `24-08`, not a paragraph here.
