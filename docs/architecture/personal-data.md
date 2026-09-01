# Personal data

What personal data this system holds, where it lives, under whose control, for how long, and what
removes it. Written 2026-08-25 as the prerequisite artifact for `roadmap.md`'s Stage 16 — deletion and
export cannot be built correctly against a system nobody has inventoried — and **verified against the
code, the migrations and the manifests on 2026-08-25 by `16-01`**, which corrected two rows that were
wrong and added six stores the first pass did not list.

**Extended 2026-08-26 by `16-05`, which closed the rows this file marked unverified.** Logs, traces
and metrics were audited against real traffic on a running cluster rather than read off the code, and
all three now have a stated retention enforced by something that runs (`adr/0057`). The audit's own
summary, its two near-misses and what it could not reach are in `backlog/16-05`; what a leak of any of
it would require is in `runbooks/personal-data-incident.md`.

**Extended 2026-08-25 by `20-01` to cover a second product.** AGO Calendar has its own database
(`adr/0027`) and its own personal data, and it is a different *kind*: AGO Chat's identifying data is
mostly incidental — a visitor happening to type their phone number into a support message — while a
booking product asks for a phone number as its one mandatory field and keeps a named lead card with
notes and a no-show history. That is a deliberate product decision, not a leak, and it means the
minimisation argument below ("minimisation works on retention, not on fields") holds for AGO Chat and
holds less well here: the field *is* the product. Its three rows are in the table, marked
**AGO Calendar**.

Every row below cites where the fact came from. That is the point of the file: a personal-data map
assembled from memory is exactly the artifact that gets a residency answer wrong. Where a fact could
not be established from this workspace it says so rather than guessing a plausible value — see
*What is unestablished*.

This file states facts about the system and the constraints they imply. It is **not legal advice** and
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

**Erasure is nevertheless tractable here, by earlier design luck — but less tractable than the first
draft of this file claimed.** Message content at rest in the application's own database lives in
exactly two places, `messages.body` and the object store — the widget caches no bodies in the browser,
only ids and a sequence number. `MessageAccepted` deliberately
carries no body ("a consumer that needs it reads `GetConversationHistory` instead" — verified: its
record has seven fields and none is the text, `Ago.Chat.Contracts/MessageAccepted.cs`), and webhook
deliveries deliberately carry none either (verified: the payload is built once as
`WebhookEventPayload(EventType, ConversationId, OccurredAt)`,
`DispatchWebhooksForEventHandler.cs:65`). So the outbox and the delivery log hold no copies of the
text — the usual reason erasure in an event-driven system is intractable does not apply *to those two*.

What `16-01` found is that it does apply, in a narrow and bounded way, **to the broker**. The realtime
fan-out path serialises a full `MessageDto` — body included — into `NodeDelivery.PayloadJson` and
publishes it as an ordinary event (`Ago.Platform.Realtime/NodeFanoutPublisher.cs`), and
`RabbitMqEventPublisher` marks every message `Persistent = true` onto durable queues
(`RabbitMqEventPublisher.cs:46`, `RabbitMqEventConsumer.cs:39-46`) backed by a PVC
(`ago-deploy/k8s/base/rabbitmq.yaml`). In steady state those messages are consumed within
milliseconds and gone. The bounded exception is in the table below.

## Where it lives

Ordered roughly by how much a person would mind. "Control" means who can physically reach the bytes,
not who is legally answerable for them — that second question is `16-04`'s and a lawyer's.

| Store | What is held | Control | How long | What removes it | Verified from |
|---|---|---|---|---|---|
| `messages.body` (Postgres) | Free text; anything a visitor or operator typed | AGO, on its own node (`adr/0026`) | **Per tier, per `adr/0031`/`13-06`.** The class a message was written under (`retention_class`, immutable) determines its window; `15-04`'s operational default (3 months) holds until `15-05` measures a real number and `13-05` records it per tier. Once past the window **the row moves to the archive below, not to nothing** | Row deletion via `ON DELETE CASCADE` (a live conversation still deleted this way); at the retention horizon, `MessagePartitionPruneJob` `DROP`s the whole month's partition for that class **only after `MessageArchiveJob` has confirmed a matching archive object exists** (`MessageArchiveGate`) | `AgoChatDbContextModelSnapshot.cs`; `Stage13RepartitionMessagesByRetentionClass.cs`; `MessagePartitionPruneJob.cs`; `MessageArchiveGate.cs` |
| `messages.content` / `messages.actions` (Postgres, `14-06`) | **Whatever a product put there, and AGO Chat cannot say what that is.** An opaque JSON document plus a list of choice labels, written by whichever product produced the message. AGO Chat stores, sequences, delivers and renders it and never reads inside — which is the whole point (`adr/0061`), and which is also why this row cannot describe its contents the way every other row here does. **The rule for producers, and it is a rule rather than a control**: put nothing in a payload you would not put in `messages.body`. The two columns sit on the same row, are erased by the same delete, and are exported by the same read — but a payload is *worse* than a body for erasure, because a body can at least be swept for a substring and a payload has no schema anyone here knows. `14-06` does not enforce this and cannot: enforcement would mean AGO Chat validating a schema it must not own | AGO, on its own node. Never leaves the deployment as a side effect — the webhook payload carries no message content at all (`api-design.md`), and this changes nothing about that | **Per tier, per `adr/0031`/`13-06`**, exactly like `messages.body` above, and by the same mechanism — it is the same row | Row deletion; `ON DELETE CASCADE` from `conversations`, and from `sites` through it. Partition drop, confirmed-archive-gated, exactly as `messages.body` above. **Nothing can selectively redact inside a payload**, so `16-02`'s erasure deletes the row or nothing | `Stage14AddStructuredMessageContent.cs`; `Ago.Chat.Domain/MessagePayload.cs`; `adr/0061` |
| `attachments` rows + the MinIO objects they point at | Attachment bytes — a photo, a document, a screenshot — plus content type and size | AGO | **Follows the owning message's window, per `13-06`/`adr/0031`'s Decision 4** — an attachment is swept in the same call that drops the one partition whose rows referenced it (`MessagePartitionPruneQuery.ListReferencedAttachmentIdsAsync`, read before the drop; a date-range predicate alone cannot substitute — a site that changes tier mid-month has attachments belonging to two different partitions in the same calendar month, see `adr/0074`). Before that, unchanged: **Forever, no retention job** | `DeleteAttachmentHandler` deletes the object *and* the thumbnail; `5-04`'s sweeper deletes only objects whose row never got a `message_id`; `MessagePartitionPruneJob`'s own sweep (`13-06`) deletes an expired attachment's object and thumbnail via `AttachmentRetentionSweepQuery`, reusing that same delete-then-clean-up-storage shape. **The pre-existing gap is unchanged**: deleting a conversation directly still cascades `attachments` rows and leaves MinIO objects behind | `DeleteAttachmentHandler.cs:55-95`; `AttachmentOrphanSweepJob`; `MessagePartitionPruneJob.cs`; `AttachmentRetentionSweepQuery.cs`; `Stage5AddAttachments.cs` cascade FKs |
| `message_archives` (Postgres manifest) + the archive `.zip` objects in object storage, prefix `archive/messages/{siteId}/{class}/{period}.zip` | **A copy** of every message and attachment reference (metadata + a presigned download URL, never bytes) from one site's one retention-class partition for one month, in `16-03`'s own export format | AGO, same store as every other object-storage entry (no distinct storage class/bucket yet — `15-02`'s own open vendor question, unchanged) | **Indefinite** — the destination once the live row's own window ends, not itself time-boxed. `adr/0031`: "archiving moves the liability, it does not end it" | `message_archives` row deletion (cascades with the site; nothing does this on its own timeline yet — `16-02`'s own erasure must be extended to reach it, per `adr/0031`'s own Consequences); the underlying object is never deleted by anything in this codebase today. **The attachment links inside an old archive go dead once `MessagePartitionPruneJob`'s own sweep deletes the underlying attachment object** — sooner than `16-03`'s own export, whose links merely expire on schedule; a real, stated limitation | `MessageArchiveWriter.cs`; `MessageArchiveJob.cs`; `MessageArchiveRepository.cs`; `Stage13AddMessageArchives.cs` |
| Keycloak's user store | Email (required — `verifyEmail: true`), username, first/last name, password hash, sessions. **Also, verified 2026-08-25**: `username_login_failure` carries an attempted username and `last_ip_failure`, and `offline_user_session` carries offline sessions — both in this same database | AGO | Until the account is deleted. **New since 2026-08-25**: it now survives restarts. Nothing prunes the login-failure or offline-session tables | Keycloak user deletion | `adr/0036`; `k8s/base/keycloak-realm-import.json`; `psql` against the live `keycloak` database (`15-02`) |
| `visitors` | `id`, `site_id`, `first_seen_at`, `last_seen_at` — **and nothing else** | AGO | Forever | Row deletion; cascades from `sites` | `Stage1CreateChatSchema.cs:69-86`, `Visitor.cs` |
| `channel_identities` (`14-01`, AGO Inbox) | `external_address` — **a phone number for `Sms`**, or a provider-issued chat id for the others — bound to a `visitor_id`, plus first/last-seen. The first structured direct identifier in AGO Chat's own database: `visitors` above holds none by design, and this table exists precisely to hold one. Held from the first inbound message; nothing about it is optional, because it is the routing key | AGO | **Forever.** No pruning exists | Row deletion; `ON DELETE CASCADE` from `visitors` and from `sites`. Nothing automatic | `Stage14AddChannelIdentities.cs`; `Ago.Chat.Domain/ChannelIdentity.cs`; `adr/0055` |
| `conversations` | The visitor↔operator pairing, timestamps, unread counters. **`18-12`, added**: an optional traffic source — the referring page's host, plus whichever of `utm_source`/`utm_medium`/`utm_campaign` the landing page's own URL carried — captured once, from the browser, at conversation start, and never revisited (`Conversation.Source`/`TrafficSource.cs`). **Incidental PII, the same class `messages.body`'s own row above names**: a referrer or landing URL can occasionally carry a personalised path segment or an identifying query-string value that neither the widget nor this system parses for meaning — it is stored as opaque text, bounded to `TrafficSource.MaxLength` (512 characters) per field, the same length-cap discipline `messages.body` already applies to its own write path. It is also **unverified**: a client-supplied header, never confirmed against a second source — the console's own report copy says so. `null` for every conversation created before this shipped; no backfill | AGO | **Forever, and this stays adequate — the field rides the row's existing rule rather than needing one of its own.** Unlike `messages.body`, which earned a bespoke per-tier window (`adr/0031`/`13-06`) because it is this system's highest-volume, highest-sensitivity free-text store, these four columns are ordinary nullable columns on a row that already carries exactly one retention rule — forever, cascades from `sites` — for every field on it (the pairing, the timestamps, the counters). Four more nullable columns on the same row do not create a second retention surface to reason about; they are erased, exported and cascaded exactly when the rest of the row already is | Row deletion; cascades from `sites` | schema snapshot; `Stage18AddConversationTrafficSource.cs`; `Ago.Chat.Domain/TrafficSource.cs` |
| `conversation_notes` (`18-04`) | An operator's private annotation about a visitor - personal data about the visitor, written by someone else, never by the visitor's own hand. Structurally unreachable from any visitor-facing read path (`ConversationNote`'s own remarks, proven by `NoteLeakProofTests`) | AGO | Follows the owning conversation - no independent retention window of its own | Row deletion; `ON DELETE CASCADE` from `conversations`. `16-02`'s erasure explicitly drains it first (`ConversationErasureQuery.DeleteNotesForConversationAsync`) rather than relying only on the cascade, so the deletion is observable in the erasure job's own count | `Stage18AddConversationNotesAndTags.cs`; `ConversationNote.cs`; `NoteLeakProofTests.cs` |
| `tags` / `conversation_tags` (`18-04`) | Labels an operator applies to a conversation - a short site-chosen word, not free text about a visitor, and not itself personal data the way a note is; included here because it is still tenant-authored content that reaches `16-02`/`16-03` | AGO | Tag definitions: forever, per site. `conversation_tags` pairings: follow the owning conversation | Row deletion; both cascade from `conversations`/`sites`. `16-02`'s erasure drains `conversation_tags` explicitly (`DeleteTagsForConversationAsync`) before the conversation row goes; a site's own `tags` vocabulary reaches the existing site-level erasure cascade, unchanged | `Stage18AddConversationNotesAndTags.cs`; `Tag.cs` |
| Minted demo tenants (`8-07`) | Whatever a viewer typed into their own demo, in the same tables as any other tenant - plus a Keycloak user with a synthetic `@demo.invalid` address (RFC 2606, unroutable) that nothing sends to | AGO | **About a day**, then removed automatically - the only data in this system with a bounded life that is actually enforced | `DemoTenantExpiryJob`: MinIO objects, then `DELETE FROM sites` (cascading to every table above), then the Keycloak user. **Does not reach**: `outbox` rows, backups until `15-02`'s window, node queues, traces, logs, Redis entries, or message-archive objects in object storage - the `message_archives` row cascades with the site, but the archived `.zip` stays orphaned in storage, the same MinIO-object-outlives-its-row gap the attachments row above already names - `adr/0058` has the full table | `adr/0058`; `DemoTenantExpiryJob`; `DemoTenantLifecycleTests` |
| `sites.name`, `sites.allowed_origins` | The customer's business identity, not a natural person's — though a sole trader's business name often is their name | AGO | Forever | Row deletion | `Stage10AddSiteName.cs`, schema snapshot |
| `operators` | `id`, `site_id`, `status`, `capacity`, `active_chats`, `external_subject_id`. **No name, no email** — identity is joined from Keycloak by subject | AGO | Forever | Row deletion | schema snapshot; `authorization.md` |
| Redis | Rate-limit buckets — one keyed by **client IP** (`register-site:ip:{ip}`); presence sets and the connection registry, keyed by principal | AGO | Bucket TTL is `ceil(capacity / refill_per_second) + 1` seconds — **≈3601 s (~1 h) for the IP bucket at its default capacity 10, refill 10/3600**. Registry entries: 30 s | Redis expiry. **But**: the deployment mounts a PVC at `/data` and passes no `command:`, so `redis:7-alpine`'s built-in RDB save points apply and the keyspace is written to disk. Expiry survives a reload, so nothing comes back alive — the snapshot file itself is never separately erased | `RegisterSiteHandler.cs:52-67`, `RegisterSiteRateLimitOptions.cs`, `RedisRateLimiter.cs` (Lua `ttl` line), `ConnectionRegistryOptions.cs:12`, `k8s/base/redis.yaml`, `docker/docker-compose.yml:45-51` |
| RabbitMQ, `deliver-to-connections.{node}` queues | **Message bodies**, inside `NodeDelivery.PayloadJson` | AGO | Milliseconds in steady state. **The exception**: the node id is the pod name (`HOSTNAME`), the queue is `durable, autoDelete: false`, and nothing deletes it — so each pod replacement leaves a queue behind, holding whatever was in flight when the pod died, indefinitely. Publishing to a dead node stops within the registry's 30 s TTL, which bounds *how much*, not *how long* | Nothing automatic. `NodeDeliveryConsumer`'s own remarks already call the queue leak "accepted, not solved… nothing in this project has a queue-retention policy yet" — what was not recorded anywhere is that the leaked queue can contain message text | `NodeFanoutPublisher.cs`, `MessageDto.cs`, `NodeTopics.cs`, `ServiceCollectionExtensions.ResolveNodeId`, `RabbitMqEventConsumer.cs:41-46`, `NodeDeliveryConsumer.cs:15-23`, `k8s/base/rabbitmq.yaml` |
| RabbitMQ dead-letter queues (`*.dlq`) | The full envelope of a poisoned message — including a `NodeDelivery` body, for `deliver-to-connections.{node}.dlq` | AGO | **Indefinitely.** Durable, no TTL, no consumer, no purge job | Nothing automatic | `RabbitMqEventConsumer.cs:59-61`, `NodeDeliveryConsumer.cs:47` |
| `outbox.payload` | Body-free by contract — ids, kinds, sequences, trace context | AGO | **Forever.** Rows are stamped `published_at` and never deleted | Nothing automatic | schema snapshot; no `DELETE FROM outbox` exists anywhere in either backend repo |
| `webhook_deliveries.payload` | Body-free by contract | AGO | Forever | Nothing automatic | `DispatchWebhooksForEventHandler.cs:61-67` |
| `webhook_deliveries.response_snippet` | Up to 2000 characters of **the tenant's own server's response body**, whatever it happens to contain | AGO | Forever | Nothing automatic | `WebhookDelivery.MaxResponseSnippetLength`, `HttpWebhookDeliveryClient.cs:176-183` |
| The visitor's own browser | `localStorage`: the signed visitor token (7-day `exp`), the visitor id, the current conversation id, a last-seen sequence per conversation. **No message bodies** | The visitor's device | The token expires after 7 days — but it is renewed at the point of use (`17-07`+`17-08`, `adr/0048`), so a returning visitor's `exp` slides forward indefinitely and the shorter number buys no deletion here; **the `localStorage` entries themselves never expire at all** — the widget has no clear path and no "forget me" control | The visitor clearing site data. Nothing in the product | `ago-widget/src/storage.ts`, `JwtTokenService.VisitorTokenLifetime`, `adr/0034`, `adr/0048` |
| The operator's own browser | `sessionStorage`: the OIDC tokens for scope `openid profile email`, so the ID token carries email and name | The operator's device | Cleared when the tab closes — `oidc-client-ts` with `WebStorageStateStore(sessionStorage)`, chosen deliberately over `localStorage` | Closing the tab; signing out | `ago-console/src/auth/userManager.ts:15-26` |
| Traces (Jaeger) | **Audited 2026-08-26 (`16-05`) against real traffic, not read off the code.** 28 distinct span-attribute keys across the three services. Ids, routes, connection ids, topic names, outbox ids — plus two nobody in this project wrote: `db.query.text`, the **full SQL statement text** on every database span (parameterised, so no values), and `url.full` on every outbound HTTP call, whose host and path are **tenant-configured** because the only outbound call is a webhook. **No message body, no email, no token, no client IP.** The inbound query string is `Redacted` by the ASP.NET Core instrumentation (`17-02`) and the outbound one by the .NET runtime's own URI redaction (`16-05`, guarded by a test); `db.npgsql.data_source` carries the connection string with the **password stripped by Npgsql** | AGO | **Bounded by count, not by time: 10000 traces**, evicted oldest-first by Jaeger's own in-memory ring (`adr/0057`). At the current probe-dominated trace rate that is on the order of an hour. Still in-memory only, so also destroyed by a pod restart | The ring evicting it; a pod restart | Jaeger's own query API, read after driving real traffic through the local cluster; `k8s/base/jaeger.yaml` |
| Metrics (Prometheus) | **Audited 2026-08-26 (`16-05`)**: 47 label names, **none person-shaped** — no client address (`network_peer_address`/`server_address` come from *outbound* HttpClient instrumentation and hold the cluster's own addresses), no email, no id belonging to a person. One label grows without bound: `node`, whose value is the API pod's `HOSTNAME`, plus the `deliver-to-connections.<node>` topic label derived from it — a cost and stability problem, not a privacy one | AGO | **14 days, or 768MB, whichever binds first** (`adr/0057`), enforced by Prometheus's own TSDB retention | TSDB retention | Prometheus's own label API on the local cluster; `k8s/base/prometheus.yaml` |
| Application logs | **Audited 2026-08-26 (`16-05`) by reading 1.19 M captured lines off the running local cluster, not by grepping the source.** Every hand-written `Log*()` call in `Ago.Chat.*` interpolates ids, counts, statuses and object keys — but that grep was never the whole story: >99% of the volume is **framework** categories nobody had configured (ASP.NET Core request logging, EF Core's full SQL statement text). Searched for and **not found**: any email-shaped string, any JWT-shaped string, any client IP (the only addresses present are the pods' own). SignalR's hub-failure log prints the method *signature*, not its argument values | AGO, via the container runtime | **14 days** for rotated files (16-day ceiling — `adr/0057` explains why a policy should quote that one), enforced by `CronJob/log-retention` in `ago-deploy`; the file a live container is still writing to is bounded by size (kubelet), not by age — `adr/0057` states that limit plainly | The CronJob; kubelet's rotation | `kubectl logs` from all three hosts on the local cluster; `adr/0057` |
| Edge access logs | Client IP per request. No query string since `17-02`; nginx's **error** log still carries one and cannot be configured not to | AGO | **14 days** (16-day ceiling), the same mechanism as application logs — these lines are container stdout like any other (`adr/0057`) | `CronJob/log-retention`, demonstrated deleting a rotated file from the Gateway's own log directory | `edge.md`; `17-02`; `ago-deploy/k8s/base/log-retention.yaml` |
| `customers` (**AGO Calendar**'s own Postgres, `20-01`) | **A phone number — the customer's only mandatory field — plus an optional name, free-text operator notes, and a no-show count.** The most directly identifying store either product has: unlike `visitors`, this row is *meant* to name a person, and unlike `messages.body` the identifier is structured and exact | AGO, on its own node | **Forever.** No pruning exists, and none is designed | Row deletion; `ON DELETE CASCADE` from `tenants`. Nothing automatic | `Stage20CreateCalendarSchema.cs`; `Ago.Calendar.Domain/Customer.cs` |
| `pending_phone_verifications` (**AGO Calendar**, `20-10`) | **A raw phone number in the clear**, plus a hashed code, a hashed bearer proof token, and their own separate expiries. The one place in either product's own Postgres that holds a phone number without an accompanying name or booking history — this table exists purely to prove a stranger's browser controls a number, before any lead card is ever created. Written by the public, unauthenticated booking widget's own verification flow (`20-10`), independent of `ago-chat`'s identically-shaped `pending_phone_verifications` (`14-15`) - different database, different repository, `adr/0027` | AGO, on its own node | **Forever today — no pruning exists.** A confirmed-and-booked row's code/proof are already spent (hashed, single-use, short-lived by their own `expires_at`/`proof_expires_at`), so the residual risk is a stale row's own phone number, not a replayable secret; still a real gap the same shape `ago-chat`'s own `14-15` table has, not yet closed for either product | Row deletion; `ON DELETE CASCADE` from `tenants`. Nothing automatic | `Stage20AddPendingPhoneVerifications.cs`; `Ago.Calendar.Domain/PendingPhoneVerification.cs` |
| `events` (**AGO Calendar**) | Not content, but a **behavioural record about a named person**: which worker they saw, for what service, when, and whether they turned up. `customer_id` is retained on cancelled and no-show rows deliberately, because the lead card exists to keep exactly that history | AGO | Forever | Row deletion; cascades from `tenants` | `Stage20CreateCalendarSchema.cs`; `Ago.Calendar.Domain/Event.cs` |
| `operators` (**AGO Calendar**) | `id`, `tenant_id`, `display_name`, `external_subject_id?`. **A display name, unlike AGO Chat's `operators`, which holds none** — worth noticing rather than discovering later: the two products' operator tables are not the same shape, and this one names a person | AGO | Forever | Row deletion | `Stage20CreateCalendarSchema.cs`; `Ago.Calendar.Domain/Operator.cs` |
| `workers` (**AGO Calendar**, `20-13`) | **Personal data about the tenant's own staff, not a customer's.** `last_name`/`first_name` (required), `middle_name` (optional) — a real name, unlike the bare `display_name` this row held before `20-13`. `display_name` itself is what the public booking surface and every console list actually render; the three name fields never leave the console, per the author's own instruction when `20-13` was scoped ("Показываем 'отображаемое имя'") | AGO | Forever. No pruning exists | Row deletion; `ON DELETE CASCADE` from `tenants`. **`20-13`'s own deletion endpoint refuses to remove a worker with any booking history** (`PendingConfirmation`/`Booked`/`NoShow`), so in practice a worker who was ever booked is deactivated, not erased — the same shape `Customer` rows already have for the same reason (the lead card's own history) | `Stage20AddWorkerNameFieldsAndTimestamps.cs`; `Ago.Calendar.Domain/Worker.cs` |
| `outbox.payload` (**AGO Calendar**'s own Postgres, `20-04`) | **A `customer_id`, and nothing else about a person.** `BookingConfirmed` carries ids plus the booking's own instants; it deliberately carries no phone number and no name, because an integration event crosses a broker to consumers this product does not control and `20-05` resolves the phone from the id at send time. A customer id is still personal data - it singles somebody out - so this row exists rather than being waved through as "just ids", which is how AGO Chat's equivalent row is worded and is the wording this one deliberately does not copy | AGO, on its own node. Reaches RabbitMQ once published; **nothing consumes it yet** (`20-05` is the first) | **Forever.** Rows are stamped `published_at` and never deleted - the same gap AGO Chat's outbox has, inherited rather than re-created, and the same one `15-04`'s pruning would close for both | Nothing automatic. **Note the asymmetry with `customers`**: deleting a lead card cascades its `events`, and leaves every already-staged `BookingConfirmed` pointing at an id that no longer resolves - which is the correct outcome for an erasure, and is only correct because the payload carries the id and not a copy of the person | `Ago.Calendar.Contracts/BookingConfirmed.cs`; `BookingConfirmedMapper`; `ConfirmationSweepTests.TheStagedEventCarriesWhatTwentyFiveNeeds_AndNoPhoneNumber` |
| Redis rate-limit buckets (**AGO Calendar**, `20-03`, widened `20-10`) | **A SHA-256 of `tenant_id:phone`** (the `20-03` booking-attempt bucket), plus, since `20-10`, an identically-hashed phone bucket and a hashed **calling IP** bucket for the phone-verification endpoint itself — one per phone number or IP address that has attempted to initiate a verification. Written by the unauthenticated booking endpoint and the unauthenticated verification endpoint, the only public write surfaces either product has. The value holds a token count and a timestamp, nothing about the person. **Pseudonymised, not anonymised, and the distinction is the point**: the input space of phone numbers (and, for IPv4, addresses) is small enough to enumerate, so a hash is still personal data — what it buys is that neither value is readable by eye in `KEYS` output, a slow-log line or a memory dump, and that two tenants' buckets for one person are unlinkable to a reader of the key space. Neither is **ever** written in clear, which `ThePhoneNeverAppearsInARateLimitKey` holds as an assertion for the `20-03` bucket — `20-10`'s own two buckets hash the same way in the code (`InitiatePhoneVerificationHandler.PhoneBucket`/`IpBucket`) but have no dedicated test of their own yet, a real, narrow gap named here rather than assumed covered | AGO, on its own node. Redis is **not** in the backup set (`adr/0050`), so no copy of this leaves the node | **Minutes.** The token bucket sets its own TTL, `ceil(capacity / refill_per_second) + 1` seconds — with `20-03`'s defaults that is about an hour for the phone bucket and a minute for the calendar one; `20-10`'s own buckets follow the identical shape at its own configured capacity/refill. The shortest-lived personal data in either product, and the only one that expires without anybody building a job | The key's own TTL; a Redis restart, since nothing here is persisted | `BookEventHandler.PhoneBucket`; `Ago.Calendar.Application/UseCases/PhoneVerification/InitiatePhoneVerificationHandler.cs`; `Ago.Platform.Caching.Redis/RedisRateLimiter.cs`'s Lua script |
| Backups | One encrypted artifact per run holding both Postgres databases, the roles, the MinIO objects and the overlay's `.env`. **Not** Redis and **not** RabbitMQ — see below | AGO. Staged on the node (newest 7 runs), collected onto the author's own machine, which is where the backup actually is. No third party holds a copy; nothing leaves Russia (`adr/0050`) | **30 days** on the collected copies — a choice, not a derivation, and it must be set to whatever the published privacy policy states | The window expiring, enforced by `backup-pull.sh` on every run | `adr/0050`, `runbooks/backup-and-restore.md` |
| `export_requests` (`16-03`) | Metadata only — `id`, `site_id`, `requested_by` (operator id), `status`, `object_key?`, `failure_reason?`, timestamps. **No personal content**: the row tracks that an export happened and where its artifact landed, never a copy of what the artifact contains | AGO | Forever. No pruning exists | Row deletion; `ON DELETE CASCADE` from `sites` | `Stage16AddExportRequests.cs`; `ExportRequestRepository.cs` |
| Tenant export archive (MinIO, `16-03`) | The same stores this table lists for a site, as of the moment the export ran — conversations, messages, attachments (referenced by presigned URL, not embedded — `adr/0072`), operators, visitors, channel identities, site configuration. A full copy, one file per tenant per export, at `exports/site/{siteId}/{exportId}.zip` | AGO, on its own node | **Forever.** No expiry job exists — only the *embedded attachment links* inside it decay, after 7 days (`adr/0072`); the archive object itself is not pruned | Nothing automatic today. Not yet reachable by `16-02`'s erasure (see below) | `SiteExportJob.cs`; `SiteExportArchiveWriter.cs`; `adr/0072` |
| Retention archive | **Shipped in `13-06`** — see the `message_archives` row above for the real shape (object key, retention, what removes it). This row is kept only as the historical pointer from `adr/0031`'s own original text | AGO | See `message_archives` above | See `message_archives` above | `adr/0031`; `adr/0074` |

### `18-07` widens who can read `messages.body`

Every row in the table above describes *where* data is held; this is a note on a new *who*.
`GetVisitorHistoryHandler`'s cross-conversation rule (`authorization.md`'s own "A new way to read
someone else's conversation") lets an operator read a past, `Closed` conversation's `messages.body`
by proving they are assigned to a different, live conversation with the same channel-identified
visitor — the first case in this codebase where a message becomes visible to an operator who was
never a party to the conversation that contains it. Scoped, not open-ended: gated on the visitor
having a `channel_identity` at all (a widget visitor's history is structurally unreachable, `14-01`'s
model) and on the requesting operator holding a live assignment with that same visitor, proven by a
test that a different operator at the same site cannot pull it for a conversation they are not on.
`16-02`'s erasure guarantees are unaffected by this widening: erasing a conversation or a site removes
the rows this handler reads from the same cascade as every other read path, so there is nothing new
to delete, only a new way the same rows could have been read before they were.

### `20-12` widens who can read `customers`

Another note on a new *who*, this time in **AGO Calendar** rather than AGO Chat. Before this item,
nothing in the product gated a read of a customer's phone number by permission at all: the pending-
bookings queue (`20-04`) carried no phone number in its own row, by a deliberate PII-minimisation
choice that queue's own read model documented, and no report existed that listed customer data at all.
`20-12` opens two new read paths onto the row `personal-data.md` already inventories above
(`customers`, "the most directly identifying store either product has"), both gated on the same
permission, `Permission.CustomerRead`:

- **The pending-bookings queue** (`GetPendingBookingsForTenantHandler`) now includes each row's phone
  number, but only in the response returned to an operator who holds `customer:read` in that tenant -
  checked per request, since the queue is shared and unassigned across every operator (`IPendingBookingReadStore`'s
  own remarks). An operator without the permission still sees the queue and can still act on it
  (`booking:reject` is the read gate, unchanged); the phone field is simply absent from their copy of
  the row, not blanked - `PendingBookingReadStore`'s own SQL never joins to `customers` at all for that
  caller, so `20-04`'s original minimisation argument stays true for exactly the operators it was
  written for.
- **A tenant contacts report** (`GetTenantContactsHandler`, `ContactsReadStore`) lists every customer
  row for the tenant - phone, display name, notes, no-show count, first/last-seen - for an operator who
  holds `customer:read`. Nothing scoped this narrower existed before; the nearest precedent
  (`ago-chat`'s `18-08` operator analytics) aggregates counts and holds no personal data at all.

**Who holds `customer:read` is no longer fixed to "every operator".** `20-01`'s v1 seeded exactly one
role holding every permission including `customer:read`, so in practice every operator held it. `20-12`
makes a second, narrower role reachable from the console (`CreateRoleHandler`, any permission subset -
`Role.Create` was already general) and a way to move an operator onto or off a role
(`GrantOperatorRoleHandler`/`RevokeOperatorRoleHandler`, calling `Operator.Grant`/`Operator.Revoke`) -
so a tenant can now have an operator who works the queue and cannot see a customer's phone, name or
notes at all. One operator per tenant is exempted from ever losing that permission entirely: the
account owner (`Operator.IsAccountOwner`, set only for the first operator a tenant's own provisioning
transaction creates) is refused by the aggregate itself - not by a console convention - if a role
change would leave them with no role granting `customer:read`
(`AccountOwnerRoleException`, proven by `OperatorAccountOwnerTests` and, over HTTP, by
`AccessControlEndpointTests`).

No new personal data exists as a result of this item and no retention or erasure story changes: both
new read paths return columns `customers` already held (this file's own table row above), through
`ON DELETE CASCADE` chains that are unaffected by who is permitted to read them. What widened is
*visibility*, not *storage* - the same distinction `18-07`'s own entry above draws for `messages.body`.

### Two corrections `16-01` made to the first draft

**There is no `visitors.token_hash`.** Both this file and `data-model.md` described a column that was
never built. `visitors` is `id`, `site_id`, `first_seen_at`, `last_seen_at` — verified against the
Stage 1 migration, the EF model snapshot and `Visitor.cs`, and the string `token_hash` does not occur
anywhere in `ago-chat`. The visitor token is a stateless signed JWT carrying `sub` (visitor id),
`site_id` and `kind`; the server keeps no copy of it, and the browser is the only place it is stored.
This *strengthens* the minimisation story and *weakens* one erasure story: there is no server-side
handle to revoke, which is exactly the gap `adr/0034` decided to leave open ("no deny-list, because
there is no caller").

**Attachments never carry the visitor's filename.** `POST /api/v1/conversations/{id}/attachments`
takes `(ContentType, SizeBytes)` and nothing else; the object key is
`site/{siteId}/conv/{conversationId}/{attachmentId}{ext}` with the extension looked up from the
server's own allow-list, never from the client. So `receipt-for-ivan-petrov.pdf` never enters the
system at all. `file-storage.md` step 1 said the client sends a filename; it was corrected in the same
change as this file. **Preserve this**: a "show the original filename" feature would add a new personal
-data field to the schema, the wire and any export.

## Retention, stated plainly

Worth its own heading because the table's "How long" column has one dominant value.

**Nothing in this system is ever deleted automatically, anywhere, except by a TTL in Redis, by the
attachment orphan sweep, and — since `16-05`/`adr/0057` — by the telemetry retention below.** No
message pruning, no partition drop, no outbox trim, no inbox trim, no webhook-delivery trim, no queue
purge. Every
"Removal path" in the table above that is not a TTL is *a thing a human or a future item would have to
run*. `15-04` and `adr/0031` are where that changes; `16-02` is where per-person erasure arrives.

**The telemetry exception, added 2026-08-26 by `16-05` (`adr/0057`).** Container logs — including the
edge access log, and therefore client IPs — are kept **14 days**, enforced by a daily `CronJob` in
`ago-deploy` that deletes rotated container-log files, plus a kubelet size bound on the file a live
container is still writing to. Prometheus keeps **14 days or 768MB**, whichever binds first, enforced
by its own TSDB retention. Jaeger keeps **10000 traces**, evicted oldest-first by its own in-memory
ring — a count rather than a duration, because that store offers no TTL. These are the first three
"How long" values in this file that are enforced by something that runs rather than by a hope, and
they are the only ones outside Redis. Note what that does *not* say: none of it touches the database,
the object store, the broker or the backups.

**AGO Calendar is the same, and `16-02` now has two databases to erase from, not one.** `20-01` built
its schema with no retention job and no pruning, exactly like AGO Chat's, which is consistent rather
than good. The one structural difference worth carrying into `16-02`: erasure there is *easier*,
because a person is a row (`customers`) rather than a substring of free text — deleting the lead card
and cascading `events` is a complete answer for that tenant, with no full-text sweep needed. What
makes it harder is that the two products share no key: the same human is a `customers` row in one
database and a `visitors` row plus message text in another, with nothing linking them, so a
cross-product erasure request cannot be executed as one operation. Named here so `16-02` does not
discover it mid-implementation.

Two stores carry **no** personal data, deliberately, and should stay that way: `outbox.payload` and
`webhook_deliveries.payload`, both body-free by contract and both now stated as such in
`messaging.md` and `api-design.md` so that a later change has to argue with a written rule rather than
merely fail to notice one. `operators` holds no name or email either. A change that adds a name column
to `operators`, or a body to an integration event, is not a small change: it converts erasure from a
two-place problem into a five-place one, and it converts an append-only table that is currently
retained forever into a personal-data store that is retained forever.

## Standing constraints

These are constraints on decisions the backlog has already opened. They exist here so they are applied
rather than rediscovered per item.

### Data residency

**The constraint, stated so it can be checked rather than recalled.**

Russian law requires that recording, systematisation, accumulation, storage, amendment and retrieval
of personal data of Russian citizens be carried out using databases located in Russia — the
localisation rule, commonly cited as 152-ФЗ art. 18 п. 5. That citation is here for orientation, not
as a reading: *the precise reach of the rule — whether a given vendor arrangement is "processing in a
database" or a permitted onward transfer, and what an operator must notify and when — is a lawyer's
determination, not this file's* (`16-04`).

What this file does assert, because they are facts about this system rather than readings of a statute:

1. **The primary stores are in Russia today.** `adr/0026` put the deployment on a Russian VPS, for cost
   and latency. Nothing recorded it as a data-protection constraint until now, so it was a happy
   accident; from 2026-08-25 it is a constraint.
2. **Therefore the default answer for any new destination is "in Russia", and moving one out is a
   decision that must be made explicitly, in writing, with the legal question asked first** — not a
   side effect of picking whichever vendor had the nicer API.
3. **The rule binds destinations, not images.** `15-06`'s container registry is out of scope: images
   carry no personal data.

**What it binds, and what each item must now answer before it chooses:**

| Item | The vendor question | What crosses the boundary if answered carelessly |
|---|---|---|
| `10-05` transactional email | Which sending provider | Every account holder's email address, plus the content of verification and password-reset mail |
| ~~`15-02` backup and verified restore~~ — **answered 2026-08-25, `adr/0050`**: the destination is the author's own machine over existing SSH, encrypted to a key the node does not hold. No vendor, no boundary crossed | — | — |
| `20-05` / `14-03` SMS and channel vendors | Which gateway | Phone numbers, and message text on any channel that carries it |
| `adr/0031`'s archive store | Where expired history is archived | Whole conversation transcripts |
| Any future object-storage vendor | Where attachment bytes live | Documents and photographs visitors uploaded |

`10-05` and `15-02` each carried this constraint in their own Open questions as of 2026-08-25.
`15-02` has since been answered and it did not cross the boundary at all — the backup never leaves
machines the author owns. `10-05` was answered the same way and for related reasons (`adr/0040`'s
amendment: self-hosted Postfix, not a sending provider). Two out of two so far; the rows still open
above are the ones where that will be harder.

**A related trap, named because it is easy to walk into:** `adr/0034` declined a registration CAPTCHA
partly because Google's reCAPTCHA "would attach a Google call to the sign-up path just as `16-01` is
about to write down a data-residency constraint". That reasoning generalises — a third-party script on
a page where a person is typing their details is a transfer, whatever it is called.

### Deletion versus backups

A restore returns what was deleted. The resolution here is a bounded backup retention window, after
which deletion is complete because no copy survives — written into the privacy policy honestly rather
than claimed as immediate (author's decision, 2026-08-25). The alternative considered and rejected was
a deletion journal replayed after every restore: more precise, but the journal is itself a list of
people who asked to be forgotten, which is a worse thing to hold than the short window it removes.
`15-02` must set its retention to a number the policy can state. **It set 30 days** (`adr/0050`),
labelled there as a choice rather than a derivation precisely because the policy does not exist yet;
it lives in one variable so that aligning it later is one edit.

`16-01` adds one item to that reasoning: the window has to cover **RabbitMQ's PVC and the leaked node
queues too**, not only Postgres and MinIO, because that is where the map found message text outside
the two places everyone thinks about.

**`15-02` answered that in the opposite direction, and the reasoning is worth keeping here rather than
only in `adr/0050`.** RabbitMQ is **not** backed up — so no window has to cover it, because no copy is
made. Backing it up would have taken the message text stranded in the leaked
`deliver-to-connections.{node}` queues and replicated it into every daily artifact, extending its life
to the backup retention window and turning a bounded leak into a distributed one. The queues remain a
real problem; copying them was not the way to manage it. The same argument excluded Redis: its RDB
snapshot carries a rate-limit bucket keyed by client IP, and not copying it is the privacy-preferable
answer as well as the operationally correct one.

What *is* covered by the window: both Postgres databases (so `messages.body`, and Keycloak's accounts
and credentials) and the MinIO objects. That is the full set of places a person's data can outlive its
own deletion by 30 days, and it is small enough to state in a policy.

### Who answers to whom

**Recorded as a decision in `adr/0076` (`16-04`), not merely a direction any more.** AGO is the
controller for its own account holders' data (they registered with AGO), and a processor acting on the
tenant's instruction for visitors' conversation data (the visitor was the shop's customer, not AGO's).
That split is what makes tenant-initiated export and deletion (`16-02`/`16-03`) a product requirement
rather than a courtesy, and it is why the widget carries a processing notice the tenant configures
(`16-04`, shipped) — AGO supplies the mechanism, the tenant owns the text and its accuracy, and AGO
never authors a default. The lawyer's confirmation of this split is still the open item — `adr/0076`
says so plainly, and is superseded rather than edited if that confirmation lands differently; see "What
is not decided here" below, unchanged by this ADR.

## What is unestablished

Written down rather than guessed, because a map is most dangerous where it is confident and wrong.

- ~~**What Keycloak's brute-force protection stores, and where.**~~ **Established 2026-08-25 by
  `15-02`**, with `psql` against the live deployment, because a backup cannot be scoped against a
  guess. The `keycloak` database — persistent since `adr/0036`, and therefore in every backup — holds
  a `username_login_failure` table whose columns are `realm_id`, `username`, `failed_login_not_before`,
  `last_failure`, `last_ip_failure`, `num_failures`. So **an attempted username and the IP it was
  attempted from are durable personal data in this system**, not an in-memory cache. It holds 0 rows
  today, which is a fact about today and not about the design. Nothing prunes it; the table's own row
  belongs in this file's inventory if that ever stops being 0.
- **Whether *online* Keycloak sessions are persisted** is still not asserted. What was established:
  `offline_user_session` and `offline_client_session` exist in that database and `offline_user_session`
  held 3 rows. Whether the ordinary session cache is also written there in this version and
  configuration was not separately checked — same method, ten more minutes, and it changes nothing
  about the backup's scope since the whole database is copied either way.
- ~~**What trace spans actually carry.**~~ **Established 2026-08-26 by `16-05`**, off a running
  cluster's Jaeger rather than from the code — see the Traces row. Nothing person-shaped; two
  attributes the project never wrote (`db.query.text`, `url.full`) that a future change could turn
  into a leak, which is why there is now a test.
- ~~**Whether Prometheus label cardinality includes anything person-shaped.**~~ **Established
  2026-08-26 by `16-05`** by enumerating all 47 label names and the values of every candidate. No.
  One label (`node`) does grow without bound, which is a cost problem and is recorded as such.
- ~~**What the node's own log rotation does**~~ — **established, and the answer was "nothing".** On
  the local Docker Desktop node, measured 2026-08-26: no rotation at all, a single 87.9 MB container
  log file after 2.5 days. `adr/0057` replaces the default with a chosen 14 days plus a size bound.
  **One residual remains, and it is a residual of the fix rather than of the audit**: the *live*
  container log file is bounded by size (kubelet) and not by age, so a very quiet container can hold
  lines older than 14 days until it grows enough to be rotated.
- **The demo node's kubelet log-rotation settings have not been verified against the live machine.**
  `16-05` was scoped away from the live cluster deliberately, so the `containerLogMaxSize` /
  `containerLogMaxFiles` values in `runbooks/public-deploy.md` are a documented node step that has not
  yet been applied or read back there. Until it is, the demo node is on kubelet's defaults.
- **nginx's error log still carries the query string**, and therefore a hub bearer token on a
  *failing* connect (`17-02` finding 3, unchanged by this item). It is now at least bounded by the
  same 14-day window as everything else, which is a smaller statement than "fixed".

## Keeping this true

An inventory that drifts is worse than none, because it will be trusted. Three places now name this
file, so that a change that widens the map is a change that has to think about it:

- `data-model.md` — "the file a schema change updates".
- `.claude/skills/db-migration` — step 5 of *Making the change*.
- `.claude/skills/messaging-contract` — step 1, on adding a field to a contract.

## What is not decided here

The legal questions — notification to the regulator, the published policy and offer text, the
processing clause in the tenant agreement, whether AGO is controller or processor for which dataset,
and whether any given incident is notifiable and on what deadline — belong in `ago-business` and to a
lawyer. What this file commits to is the engineering side: knowing where the data is, being able to
remove it, being able to hand it over, and not quietly widening the list above without noticing.
