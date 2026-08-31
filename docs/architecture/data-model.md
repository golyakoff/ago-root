# Data model

PostgreSQL is the only source of truth. Everything else is a cache, a queue, or a projection.

**This file covers two databases, not one.** Everything down to *Provider swap* is **AGO Chat**'s
schema; **AGO Calendar** has its own section near the end and its own separate database — no query in
either product can reach the other's tables (`adr/0027`), and no foreign key crosses between them.

*Why one file and not one per repository* (decided in `20-01`, since `ago-calendar` is the first
product that could have gone either way): every other architecture document here already spans both
products in place — `repositories.md` and `naming-and-structure.md` both gained `ago-calendar` rows in
`20-00` rather than sprouting per-repo copies — and `ago-root`'s stated job is to hold the rules and
decisions for the whole platform while the code lives elsewhere. Splitting this one file would make it
the first exception, and would put the two products' schemas where a reviewer comparing them cannot
see them side by side, which is exactly the comparison the platform claim invites. The cost is that
this page is now long and mixes two databases; the section heading below is the mitigation, not a
denial.

## Tables (initial shape - refined per stage)

- `sites` - the tenant. `id`, `public_key`, `allowed_origins[]`, `name` (**added in `10-02`** - a real
  gap that item's own scope anticipated: its Goal takes a site display name as a required
  registration input, but no such column existed before this stage. `text not null default ''`,
  additive/reversible - `Stage10AddSiteName`, `ago-chat`). **Shipped in `11-01`**: the `settings`
  placeholder named above was never actually built (the Stage 1 migration shipped `id`/`public_key`/
  `allowed_origins` only) - it is now two concrete columns, `widget_primary_color_hex text NULL` and
  `widget_position text NOT NULL DEFAULT 'bottom-right'`, added by `Stage11AddSiteWidgetConfig`
  (`Ago.Chat.Domain.WidgetConfig`, `adr/0029`'s two fixed fields). `widget_position` carries a `CHECK`
  constraint restricting it to `'bottom-right'`/`'bottom-left'` - cheap storage-level backstop for the
  `Position` enum, matching this table's own `Ago.Chat.Domain.Position`/`PositionConverter` mapping
  (kebab-case in the column, the CLR enum's own member names on the wire - the two boundaries are free
  to differ). **`widget_notice_text text NULL` and `widget_notice_url text NULL` added in `16-04`**
  (`Stage16AddSiteWidgetNotice`, additive/reversible, `adr/0076`) - the tenant's own processing notice
  and link, both `NULL` for every row that predates this column so the widget shows nothing rather than
  an AGO-authored default. No `CHECK` constraint, unlike `widget_position` just above: free text and a
  URL are not a closed set SQL can enumerate the way an enum is - `Ago.Chat.Domain.WidgetConfig`'s own
  constructor (length bound on the text, `https://`-only scheme check on the URL) is this value's only
  validation, the same boundary `offline_auto_reply_rules`' own free-text shape already draws below.
  **`created_at timestamptz NULL` added in `12-02`** (`Stage12AddSiteCreatedAt`,
  additive/reversible) - the same kind of real gap `name` records above: `12-02`'s owner overview needs
  a per-tenant creation time and this table had none, though `conversations`, `messages` and
  `attachments` all carry one. **Nullable with no default and no backfill, on purpose**: giving existing
  rows `DEFAULT now()` would stamp the demo tenant and every previously-registered site with the instant
  the migration ran and present that as fact. `null` means "not recorded"; the only writer is
  `RegisterSiteHandler`, from `IClock`.
  **`demo_expires_at timestamptz NULL` added in `8-07`** (`Stage8AddSiteDemoExpiry`,
  additive/reversible), with a partial index `ix_sites_demo_expiry` on `(demo_expires_at) WHERE
  demo_expires_at IS NOT NULL` - proportional to the demo tenants alive rather than to every tenant ever
  registered, the same shape `ix_conversations_waiting` has. Non-null is the *only* thing that makes a
  site a demo tenant: there is deliberately no second `is_demo` boolean, because two columns that must
  agree are two columns that can disagree, and this is the one the expiry sweeper reads. `null` for every
  ordinary tenant and for the seeded `8-05` demo sites, which are not created on demand and must never
  expire (`adr/0058`).
  **`offline_auto_reply_enabled boolean NOT NULL DEFAULT false`, `offline_auto_reply_fallback text
  NOT NULL DEFAULT ''` and `offline_auto_reply_rules text NULL` added in `14-04`**
  (`Stage14AddSiteOfflineAutoReply`, additive/reversible, `adr/0066`). Off with nothing to say is what
  every pre-existing row reads back as, from the column defaults - no backfill, and no behaviour change
  for a tenant who never opens the screen. The rules column holds a JSON array of `{keyword, reply}`
  in **`text`, not `jsonb`**, for the same reason `messages.actions` does (`14-06`): nothing queries
  *into* it - the only reader is the matcher, which needs the whole ordered list anyway - so everything
  `jsonb` buys is capability this value will never use. Not a `site_auto_reply_rules` child table
  either: a list capped at twenty entries, read and written as a unit, would buy a join on a
  per-message path and a second aggregate boundary inside `Site`. Order in the array is **behaviour,
  not presentation** - the matcher is first-rule-wins.
- `visitors` - `id`, `site_id`, `first_seen_at`, `last_seen_at`, and nothing else.
  **Corrected in `16-01`**: this bullet listed a `token_hash` column that was never built. There is no
  such column in `Stage1CreateChatSchema`, in the EF model snapshot, or in `Visitor.cs`, and the string
  does not occur anywhere in `ago-chat` - the visitor token is a stateless signed JWT (`sub`, `site_id`,
  `kind`) that the server issues and validates but never stores. The browser is the only place a copy
  exists. The practical consequences run in both directions and both are worth knowing before designing
  against this table: there is nothing here to leak, and there is also no server-side handle to revoke
  (`adr/0034`'s "no deny-list, because there is no caller").
  No name, email or contact detail by design - the row identifies a returning browser, not a named
  person. **Qualified 2026-08-25**: that is true of these columns and misleading about the dataset,
  since `messages` next to it holds whatever the visitor typed, which in a support product routinely
  includes their own name and phone number. See `personal-data.md` for what the system actually holds
  and where; an identifier that reliably singles out a returning individual is also not the same thing
  as anonymous data.
- `channel_identities` (**shipped in `14-01`**, AGO Inbox) - `id` (uuid v7), `site_id`, `kind`
  (`Max|Sms|Telegram|WhatsApp`, stored as the CLR member name), `external_address` (the raw identifier
  the channel uses for one correspondent - a phone number, a chat id), `visitor_id`, `first_seen_at`,
  `last_seen_at`. The answer to "which external chat-id or phone number corresponds to which visitor".
  Its own aggregate rather than columns on `visitors`, because one person can hold several at once (the
  same human on MAX and on SMS) and because the link is worth keeping after it is unlinked -
  `Ago.Chat.Domain.ChannelIdentity`'s own remarks and `adr/0055`.
  **The identity rule this table encodes** (`adr/0055`, and the thing to check any future change
  against): a widget visitor and an external-channel sender are **two `visitors` rows**, and nothing
  merges them by inference. Several `channel_identities` rows *may* point at one `visitor_id` - that is
  an ordinary many-to-one, and a future verified link is one `UPDATE` with no migration - but no code
  today ever writes that edge, and `ChannelIdentity` deliberately ships with no re-link method.
  Personal data: `external_address` is a phone number for `Sms`, so this table holds a direct identifier
  in a way `visitors` next to it does not - see `personal-data.md`.
- `channel_credentials` (**shipped in `14-02`**, AGO Inbox) - `id` (uuid v7), `site_id`, `kind`
  (`Max|Sms|Telegram|WhatsApp|Vk`, `ChannelIdentity`'s own vocabulary reused), `token_ciphertext` (the
  shop's own bot token, AES-256-GCM, reversible - it must be reproduced for every outbound call),
  `webhook_secret_hash` (the value AGO generated and handed the provider at registration, SHA-256,
  one-way - never reproduced, only ever verified against what a webhook delivery echoes back),
  `active`, `created_at`, `provider_account_id` (nullable text, **added `14-08`**: the provider-side
  identifier a token alone does not disclose - VK's own `group_id`, and now `14-10`'s WhatsApp
  `phone_number_id`; still `null` for MAX/Telegram, whose bot tokens are self-addressing).
  `ChannelCredential` (`Ago.Chat.Domain`), keyed by `(site_id, kind)` - channel-neutral, not
  `MaxBotCredential`, so `14-03`'s SMS aggregator key inherits this shape rather than re-deriving it
  (`adr/0069`). Encrypted under a dedicated `Channels:CredentialEncryptionKey`, distinct from
  `Webhooks:SecretEncryptionKey` - see `secrets.md`. Personal data: none - a bot token and a generated
  secret belong to the shop, not to any individual.
- `email_threads` (**shipped in `14-09`**, AGO Inbox) - `conversation_id` (uuid, primary key - a 1:1
  extension of `conversations`, not a synthetic id: nothing ever addresses one of these rows on its own,
  the only lookup is "the thread state for conversation X"), `root_message_id`/`last_inbound_message_id`
  (the first and most recent inbound email's own RFC 5322 `Message-ID` header value, verbatim - what
  `EmailChannelAdapter` reads back to build `In-Reply-To`/`References` on an operator's reply), `subject`
  (captured once, from the first inbound message). The one channel-specific table this stage has needed
  besides `channel_identities`/`channel_credentials`: no other channel replies to a chat id or phone
  number and needs any of a *specific earlier message's* own identifier read back later - email's own
  threading is client-side, driven entirely by these headers (`adr/0080`). Personal data: none directly -
  a `Message-ID` is an opaque identifier, not a phone number or address; `channel_identities.external_address`
  already carries the visitor's own email address for this channel, the same column `Sms`'s phone number
  uses.
- `operators` - `id`, `site_id`, `status` (`offline|online|away`), `capacity`, `active_chats`.
  **Shipped in `4-01`**: `active_chats` is not part of the `Operator` aggregate - EF maps it as a
  shadow property (`OperatorConfiguration`, `Ago.Chat.Infrastructure.Postgres`) purely so migrations
  see it; the only writer is the atomic compare-and-set
  `UPDATE operators SET active_chats = active_chats + 1 WHERE id = @id AND active_chats < capacity`
  (`concurrency.md`'s own statement, `OperatorCapacityStore`/`IOperatorCapacity`) and its symmetric
  release. Nothing ever loads `Operator` through EF's change tracker and saves it back, so there is
  no load-mutate-save path that could race the raw `UPDATE` - the shadow property is what makes that
  true by construction, not by convention.
  **Corrected in `6-09`**: the "symmetric release" above was, until then, a sentence this document
  asserted and no ordinary code path performed. `active_chats` went up on every automatic assignment
  and came back down only when an operator's *last connection anywhere* dropped (`4-04`'s
  `OperatorConversationReleaser`), so an operator who simply finished conversations one at a time
  ratcheted to zero usable capacity and the site's waiting queue stopped being served - found live by
  `7-04`'s `assignment-contention` run (`load/reports/2026-08-24-assignment-contention.md`), not by
  reading this page. The invariant the column now actually keeps, and the one to check any future
  change against: **`active_chats` equals the number of conversations currently `Assigned` to that
  operator whose `holds_capacity_claim` is true** - see the `conversations` bullet below and
  `adr/0033`.

  **Shipped in `13-03`.** Two new columns: `holds_seat` (`bool`, default `true` - every operator
  created today is created inside `13-01`'s own seat-limit check and therefore already fits) and
  `removed_at` (`timestamptz?`, `null` until a real "this person is gone" action, never cleared once
  set - there is no un-remove). Both are plain flags, not a value object - neither has any lifecycle
  beyond "on or off" / "set once", the same "one column, no object to bundle it into yet" judgement
  `sites.tier`/`sites.seat_limit` below already made for the analogous case. `13-01`'s own
  `operator_invites` seat-limit check (`OperatorInviteRedemptionRepository`'s `COUNT(*) FROM operators
  WHERE site_id = @siteId`) now adds `AND removed_at IS NULL` - without it, a removed operator counted
  against the seat limit forever, a real regression this item's own backlog named explicitly.
  `holds_seat` is deliberately not part of that filter: the invite check answers "how many operator
  rows does this site have", a different question from "how many currently hold an assigned seat".

  **The over-seats condition - `count(operators WHERE holds_seat AND removed_at IS NULL) >
  sites.seat_limit` - is a derived read, computed at request time, never a stored column.** A stored
  flag would need its own invalidation path fired from at least three independent write paths (a
  downgrade applying at renewal, an operator's own seat toggled, an operator removed) for a value a
  plain two-table read already computes correctly on demand - the same reasoning `13-01`'s own
  row-lock-vs-shadow-counter note gives for a different, low-frequency check below. Surfaced by
  `GetSeatAssignmentSummaryHandler` (`GET /api/v1/sites/{siteId}/operators/seat-assignment-summary`).
  Migration `Stage13AddSubscriptionLifecycleAndOperatorSeats`.

- `operator_invites` (**shipped in `13-01`**) - `id` (uuid v7), `site_id`, `role_id` (FK to that site's
  own `roles` row - `"Operator"` or `"Admin"`, `adr/0016`'s tenant-local role scoping), `code_hash`
  (SHA-256 of a `RandomNumberGenerator`-generated plaintext code shown to the inviting operator exactly
  once, at generation - the same entropy/generation reasoning `adr/0024`'s `IWebhookSecretGenerator`
  established for a different bearer value, hashed rather than encrypted because redemption only ever
  needs to *compare*, never reproduce, the inverse of `adr/0024`'s own webhook-secret case),
  `created_by_operator_id`, `created_at`, `expires_at` (seven days, a hardcoded default per this
  codebase's own "sane default, no per-site override yet" precedent - `caching.md`'s rate-limit
  buckets), `redeemed_at?`, `redeemed_by_operator_id?`, plus the same Postgres `xmin` optimistic-
  concurrency column `conversations`/`messages` already use - two concurrent redemption attempts
  against the identical code can both pass the pre-transaction "not yet redeemed" read, and `xmin` is
  what stops the second `SaveChangesAsync` from silently overwriting the first's already-committed row.
  `ux_operator_invites_code_hash` (unique) is how redemption looks a code up.

  `sites` gained two columns in the same wave: `tier` (`text`, default `'free'`) and `seat_limit`
  (`integer`, default `1`) - nothing in `13-01`'s own scope changes either away from its default; that
  is `13-02`'s job once a real payment exists to drive it.

  **The seat-limit check is a `SELECT ... FOR UPDATE` row lock on `sites`, not a denormalized counter
  like `active_chats` above it - a deliberate contrast, not an oversight.** `active_chats` uses an
  atomic `UPDATE ... WHERE ... < capacity` because operator *assignment* is a high-frequency, contended
  path where a per-row lock would itself become the bottleneck (`concurrency.md`'s own "Operator
  assignment - the contended path"). Operator *invitation* is the opposite: rare, low-contention, at
  most a handful of calls ever per site. `OperatorInviteRedemptionRepository` locks the `sites` row
  directly, then counts real `operators` rows inside that lock, rather than adding a second denormalized
  counter that would need its own symmetric decrement path - one that does not exist anywhere in this
  codebase yet (no operator-removal flow has been built; `13-01`'s Out of scope names this explicitly).
  Proven under real concurrency (`OperatorInviteSeatLimitConcurrencyTests`): a site with `seat_limit = 2`
  and one existing operator, twenty concurrently-redeemed invites racing for the one remaining seat -
  exactly one succeeds, the rest are rejected on capacity, and the invite each rejected attempt held
  stays redeemable afterward once a seat opens up (a capacity rejection rolls its transaction back
  before ever marking the invite consumed).

- `billing_subscriptions` (**shipped in `13-02`**) - `id`, `site_id`, `yookassa_payment_id` (unique),
  `requested_seats`, `tier`, `status` (`pending|succeeded|failed`), `payment_method_id?`, `created_at`.
  One row per checkout attempt, holding the in-flight state between checkout-session creation and
  webhook confirmation - `sites.tier`/`seat_limit` never change until the second moment actually
  happens (`Site.ActivateSubscription`, this item's own first real writer of those two columns). Named
  for what it becomes, not only what it starts as: `13-03`'s recurring-charge job is scoped to extend
  this same row via `payment_method_id`, not create a new one per cycle.

  **Extended in `13-03`.** `status` gains two values: `past_due` (a recurring re-charge failed;
  `sites.tier`/`seat_limit` stay exactly as they were - `decisions/0006`'s "full access retained") and
  `lapsed` (this row no longer entitles anything - reached either by exhausting a 7-day `past_due`
  retry window with no successful recharge, or by an explicit cancellation running out its own
  paid-through period; one terminal state for both, since from the site's own point of view the two
  end in the identical place). Six new columns: `current_period_end` (`timestamptz?`, `null` until the
  first payment succeeds, then advanced by a fixed 30-day period on every successful renewal - `13-02`'s
  own checkout had no prior period to measure from, `13-03`'s recurring charge does),
  `past_due_since` (`timestamptz?`, the anchor the 7-day retry window is measured from, set once on
  entering `past_due` and never moved by a later retry), `last_renewal_attempt_at` (`timestamptz?`,
  gates "no more than one retry attempt per calendar day" independently of `past_due_since`),
  `cancel_requested` (`bool`, default `false` - the recurring-charge job checks this before ever
  attempting a charge, so a cancelled-and-due row lapses with no charge attempt reaching ЮKassa),
  `pending_seat_count`/`pending_tier` (`int?`/`text?`, a mid-cycle downgrade recorded but not applied -
  `decisions/0006`'s "downgrades apply at the next renewal" - cleared and applied together the next
  time a renewal actually succeeds, whether on-time or a `past_due` retry). The row is extended in
  place across its whole lifetime, never replaced by a new row per billing cycle - an implementer's
  call this item's own backlog left open, decided in favour of one row per subscription since nothing
  in scope needs a queryable per-cycle history the `billing_webhook_events` ledger does not already
  give as an audit trail. Migration `Stage13AddSubscriptionLifecycleAndOperatorSeats`.

- `billing_webhook_events` (**shipped in `13-02`**) - `id`, `yookassa_payment_id`, `event_type`,
  `received_at`; unique on `(yookassa_payment_id, event_type)`. The idempotency ledger for ЮKassa's
  inbound webhook, adapted from `6-05`'s `(endpoint_id, message_id)` shape to this item's one-sender
  case - see `adr/0071`.

- `conversations` - `id`, `site_id`, `visitor_id`, `operator_id?`, `state`
  (`waiting|assigned|closed`), `last_sequence`, `visitor_unread_count`, `operator_unread_count`,
  `operator_last_read_sequence`, timestamps. Optimistic concurrency uses Postgres's built-in `xmin`
  system column (`1-04`), not an extra column of our own to keep in sync by hand - which is also what
  lets the unread counters (`2-05`) use a plain load-mutate-save through the aggregate instead of a
  raw atomic `UPDATE`: a losing concurrent save throws rather than silently overwriting the other
  side's increment, and the broker's own redelivery is the retry.
  `operator_last_read_sequence` (`5-15`) is what makes that counter clearable without losing a
  message: mark-read moves the watermark and subtracts what it covers rather than zeroing, and the
  increment skips anything at or below it, so a message arriving in the same instant as a mark-read is
  still counted whichever of the two saves wins the `xmin` race. There is no visitor-side twin -
  nothing reads `visitor_unread_count` yet (`5-15`'s own Decisions section). No index: the column is
  only ever read as part of an aggregate already located by primary key.
  `holds_capacity_claim` (`6-09`, `adr/0033`) is the receipt for one `operators.active_chats` slot:
  true only for a conversation the automatic assignment engine assigned after `TryClaimAsync` actually
  took a slot, in that same transaction. A conversation an operator picked up by hand
  (`AssignConversationHandler`, behind `OperatorHub.JoinConversationAsync`) takes no slot and carries
  no receipt, which is why closing one must not decrement anything. `Close` and `ReleaseToQueue`
  consume the receipt as part of the same `SaveChangesAsync` as the state transition, so under `xmin`
  a claim cannot be released twice for one close and cannot be released for a close that lost its
  race. Deliberately an ordinary mapped property rather than a shadow property like
  `operators.active_chats` right above: that column has a raw-SQL writer an EF load-mutate-save could
  race, and this one has exactly one writer, the aggregate itself. No index - it is read only as part
  of an aggregate already located by primary key, or of one `GetAssignedToOperatorAsync` already
  materialises.
  **Migration `Stage6AddConversationCapacityClaim` also repairs existing rows**, which a schema
  migration normally has no business doing: it declares every currently-`Assigned` conversation to
  hold a claim and resets each operator's `active_chats` to exactly that count. Both halves have to
  run together, and the reason they run at all is that the pre-`6-09` leak is already baked into every
  deployed database - shipping the fix alone would leave every existing environment exactly as jammed
  as it is, because nothing in the new code path ever revisits a conversation that was already closed.
- `messages` - `id` (uuid v7), `conversation_id`, `sequence`, `author_kind`, `author_id`, `body`,
  `created_at`, `delivered_at?`, `read_at?`, and - added by `14-06` - `content_kind?`,
  `content?`, `actions?`. See **Structured message content** below for why those three are
  `text` rather than `jsonb` and why they are three columns rather than one.
- `outbox` - `id`, `occurred_at`, `type`, `version`, `payload` (jsonb), `partition_key`,
  `correlation_id`, `published_at?`, `attempts`. See `adr/0005`. `version`/`correlation_id` were
  missing from the first cut - added once `2-04`'s dispatcher needed to reconstruct a complete
  `EventEnvelope` from a claimed row, since dropping `correlation_id` silently defeats its purpose.
- `inbox` - `message_id`, `consumer`, `processed_at`. The idempotency ledger for consumers.
- `roles` - `id`, `site_id`, `name`, `permissions` (`text[]`) - the RBAC model `adr/0016` added,
  built in `1-04`. No management API yet; `1-05`'s seed script and, **as of `10-02`**,
  `RegisterSiteHandler`'s bootstrap transaction (`Ago.Chat.Infrastructure.Postgres.SiteRegistrationRepository`)
  are the only writers - still no general role-management surface (`authorization.md`'s own note on
  this), just a second caller that seeds the same two fixed roles a real self-registered site needs
  instead of only a script-seeded demo one.
- `operator_roles` - `operator_id`, `role_id` - the join table; an operator can hold more than one
  role even though Stage 1 only ever grants the single seeded `"Operator"` role. **`10-02`**: a
  self-registered operator is granted both `"Operator"` and `"Admin"` immediately, the same
  `demo-admin` precedent `5-08`'s seed script already established, in the identical bootstrap
  transaction as `roles` above - `Site` + both `Role`s + `Operator` + both `operator_roles` rows
  commit together or not at all (`RegisterSiteHandler`'s own remarks on why this is deliberately
  wider than this file's usual "one aggregate per transaction" default, below).
- `attachments` (**shipped in `5-03`**) - `id` (uuid v7), `site_id`, `conversation_id`, `message_id?`,
  `object_key`, `content_type`, `size_bytes`, `state` (`pending|ready|deleted`), `created_at`,
  `thumbnail_key?` (**writer shipped in `5-04`** - `AttachmentThumbnailConsumer`; the column itself
  was reserved by `5-03`, unpopulated until then). Its own
  aggregate, not part of `Conversation` (`Ago.Chat.Domain.Attachment`'s own remarks) - it is created
  and later confirmed in its own transaction, never inside the message-write transaction
  (`MessageBatchWriter`, `4-05`), so folding it into `Conversation`'s aggregate boundary would break
  "one aggregate per transaction" the moment a HEAD-verify confirm needed to save without touching the
  conversation. `messages` gained a matching `attachment_id?` column the same change
  (`file-storage.md`: "message references the attachment, not the reverse" - that column is the real
  pointer a reader follows; `attachments.message_id?` is a denormalized second pointer that exists
  only so `5-04`'s orphan sweep can ask "which attachments were never linked to a message" with a
  plain `WHERE message_id IS NULL`, not an anti-join against `messages`). Neither column carries a
  foreign key to the other table - see Keys and indexes below.
- `conversation_notes` (**added in `18-04`**) - `id`, `conversation_id`, `author_id`, `body`
  (`varchar(4000)`), `created_at`. Its own table, deliberately not a `messages` row with a `Kind`
  discriminator - `18-04`'s own backlog item and `ConversationNote`'s own remarks give the full
  argument: the visitor-facing read path (`GetConversationHistoryHandler`'s visitor entry point,
  `ConversationReadStore.GetHistoryAsync`) has no predicate over `messages` at all today, so a note
  stored there would need a filter *added* to keep it from a visitor - filtered instead of
  structurally absent. A separate table with its own repository (`INoteRepository`, sharing no method
  with `IConversationRepository`/`IConversationReadStore`) means there is no predicate to forget,
  proven against a real Postgres by `NoteLeakProofTests`. `ix_conversation_notes_conversation` on
  `(conversation_id, created_at)` for the one real read shape (an operator's notes panel, oldest or
  newest first). Cascades on `conversation_id` - a note has no independent lifecycle once its
  conversation is gone.
- `tags` (**added in `18-04`**) - `id`, `site_id`, `name` (`varchar(60)`), `created_at`. A per-site
  vocabulary, not per-conversation - `site:configure`-gated creation, unique on `(site_id, name)`
  (`ix_tags_site_name`) so two operators cannot create two rows meaning the same word. Cascades on
  `site_id`, reaching the same site-level erasure cascade every other per-site table does.
- `conversation_tags` (**added in `18-04`**) - `conversation_id`, `tag_id`, no surrogate key - the
  pair itself is the identity, the same shape `operator_roles` above already uses for a join table
  with no attributes of its own. `ix_conversation_tags_tag_id` on `tag_id` alone (the reverse lookup
  "which conversations carry this tag", the direction the queue/admin-list filter actually queries;
  `(conversation_id, tag_id)` is already the primary key and covers the forward direction for free).
  Cascades on both `conversation_id` and `tag_id` - removing a conversation or deleting a tag from the
  vocabulary both clean up silently rather than leaving an orphaned pairing.

## Keys and indexes

- Ids are **UUID v7** (time-ordered). Random UUIDs fragment B-tree inserts; a bigint sequence leaks
  counts and complicates multi-writer scenarios. Any deviation needs an ADR.
- `messages` unique `(conversation_id, sequence)` - enforces per-conversation ordering at the storage
  level and turns duplicate delivery into a no-op insert.
- History reads use **keyset pagination**:
  `WHERE conversation_id = @id AND sequence < @cursor ORDER BY sequence DESC LIMIT @n`.
  `OFFSET` is banned - it degrades exactly where this project is supposed to shine.
- `conversations` partial index on `(site_id) WHERE state = 'waiting'` for the assignment queue.
  **Shipped in `4-01`** (`ix_conversations_waiting`) - this replaced, not added to, EF's own default
  foreign-key index on `site_id`; the only other query filtering by a bare `site_id` in the codebase
  today is `roles`, an unrelated table, so nothing lost coverage. `WaitingConversationClaimQuery`
  (`Ago.Chat.Worker`) is the first real reader, proven with two concurrently open transactions
  actually skipping each other's locked rows, not just asserted from the SQL text.
- `outbox` partial index on `(id) WHERE published_at IS NULL` - the dispatcher must never scan
  already-published rows.
- **Every table holding a tenant's data cascades from `sites`** - EF's default for a required
  relationship, which is what all of them are. `8-07` is the first thing to depend on that rather than
  merely benefit from it: `DemoTenantRepository.DeleteSiteAsync` is one `DELETE FROM sites`, and what it
  reaches is a property of this schema rather than of that method. A hand-ordered list of deletes would
  be a second, weaker copy of this graph that silently stops being complete the first time a table is
  added. `DemoTenantLifecycleTests` asserts emptiness table by table rather than trusting the cascade,
  which is the half that has to be independent.
- `channel_identities` unique `(site_id, kind, external_address)` (`ux_channel_identities_site_kind_address`,
  `14-01`) - both the lookup `IChannelIdentityRepository.FindAsync` serves and the storage-level backstop
  that stops two processes racing the same first inbound message from creating two visitors for one
  person. Same "the index is the backstop, not the primary mechanism" division `adr/0019` draws for
  `messages`: the primary mechanism is the application's resolve-then-create. All three columns are in
  the key deliberately - dropping the site would let one tenant resolve a number another tenant is
  talking to, dropping the channel would merge a Telegram id and an SMS number that happen to read
  alike. EF's default foreign-key index on `visitor_id` is kept (unlike `4-01`'s replacement of the one
  on `conversations.site_id`): "which channels is this visitor reachable on" is the natural inverse
  query, and this table is small next to `messages`.
- `channel_credentials` unique `(site_id, kind)` **filtered to `active`**
  (`ux_channel_credentials_site_kind_active`, `14-02`) - a plain unique index on the pair would mean a
  revoked credential permanently blocks registering its replacement, defeating revoke-and-recreate, the
  shape `webhook_endpoints` already established for its own endpoints. The Application-layer check
  (`RegisterChannelCredentialHandler` refuses a second active credential before calling
  `ChannelCredential.Register`) is the primary mechanism; this index is the storage-level backstop, the
  same division `adr/0019` draws for `messages` (`adr/0069`).
- `channel_credentials` unique `(kind, provider_account_id)` **filtered to `active AND
  provider_account_id IS NOT NULL`** (`ux_channel_credentials_kind_provideraccountid_active`, `14-10`) -
  a guarantee no channel needed until WhatsApp, whose inbound webhook resolves a delivery's tenant *by*
  `provider_account_id` (`IChannelCredentialRepository.GetActiveByProviderAccountIdAsync` - WhatsApp's
  own webhook is App-wide, not per-credential, so there is no `{credentialId}` path segment to route on
  the way MAX's/Telegram's/VK's own webhooks have). Without this index, two sites could both register the
  identical `phone_number_id` (a mistake this system does not otherwise prevent, since Meta's own
  uniqueness guarantee for that id is a fact about their platform, not a constraint this schema
  enforced), and an inbound delivery would route to whichever row a lookup happened to find first -
  silently misattributing one shop's visitor conversation to another. Partial for the identical reason
  the `(site_id, kind)` index above is: a revoked credential must never block re-registering the same
  number, and MAX's/Telegram's own rows (`provider_account_id` always `null`) must never collide with
  each other under a plain unique index on a column most rows leave unset.

## Partitioning

**Shipped in `13-06`** (`adr/0031`, decided 2026-08-25): `messages` is multi-level —
`PARTITION BY LIST (retention_class)` at the top, each class partitioned by month exactly as below.
The class is stamped from the tenant's tier when a message is written and never changes, so a tier
change moves no rows — proved with a real Postgres by a test that changes a site's tier and checks an
already-written row's class afterwards. Every unique constraint widens by that column again, extending
`adr/0019` rather than reopening it (`adr/0019`'s own addendum). Three classes exist today
(`RetentionClass.KnownClasses`, mirroring `SubscriptionTierBands`' three tiers): `messages_free`,
`messages_starter`, `messages_growth`, each carrying the monthly grid the rest of this section
describes. `13-06`'s own migration (`Stage13RepartitionMessagesByRetentionClass`) applied the identical
rename/create/copy/drop technique `2-06`'s own migration established, one level deeper — existing
rows' `retention_class` is a one-time approximation from the owning site's *current* tier at migration
time, stated as such rather than smoothed over. See `adr/0074` for the two things this item's
implementation surfaced that `adr/0031` itself did not specify (precise attachment expiry across a
mid-month tier change; retrieval as a direct read rather than a request/poll pipeline).

### Structured message content (`14-06`)

A message may carry a **kind**, an opaque **payload** and a list of **actions**, so that a product can
put something interactive into a conversation that renders on a widget, on Telegram and over SMS
alike. AGO Chat never interprets the payload - `adr/0061` argues that, and
`MessageOpacityTests` enforces it. The storage decisions are here because they are not free: this is
the largest table in the system and it is partitioned.

- **`text`, not `jsonb`, for `content`.** The question that decides it is "does anything ever need to
  query *into* the payload", and the answer is **no, by design and permanently** - AGO Chat cannot
  filter, group or index on contents it is forbidden to understand, and the day it could would be the
  day the boundary had already been crossed. Everything `jsonb` buys (`->`, `@>`, GIN) is exactly that
  capability, and it is paid for with a parse and a binary re-encode on every insert. Two side effects
  happen to be what this field wants: `text` round-trips the producer's own bytes verbatim, so a
  payload a product signed still verifies (`jsonb` reorders keys and drops duplicates), and a payload
  over roughly 2 KB TOASTs out of line and compressed rather than widening the heap the hot
  keyset-by-`sequence` read scans.
- **Three nullable columns, not one composite.** On a prose message - which is every message today -
  three NULLs cost **zero additional bytes**: Postgres records them in the row's null bitmap, which is
  sized in bytes and already exists for `attachment_id`/`client_message_id`. The table goes from 9
  mapped columns to 12, and both round to the same two bytes of bitmap.
- **The migration adds columns and nothing else.** Three nullable columns with no default and no
  backfill is a catalogue-only change in Postgres - no table rewrite, which on a partitioned table
  would have meant rewriting every partition.
- **`actions` is the one column AGO Chat reads.** The asymmetry is the design: AGO Chat owns the
  actions' schema (a label and an opaque value) because a channel with no UI has to *enumerate* the
  choices to print them as a numbered list; it owns no schema for the payload. Stored as a JSON array
  in one `text` column rather than a child table, because this table is `PARTITION BY RANGE` and a
  child table would need its own partitioning or a foreign key pointing at a partitioned parent - the
  same reason `attachments.message_id` carries no FK - and because the hot read would grow a join for
  a list that is empty on virtually every row.
- **`ck_messages_content_length`** - `CHECK (content IS NULL OR char_length(content) <= 16384)`. The
  ceiling also lives in `MessagePayload.MaxLength`, and the duplication is deliberate: this page's own
  rule is "anything enforcing a guarantee gets a constraint, not just application code", and the
  guarantee is not politeness - it bounds an opaque field on the one write path that accepts
  unauthenticated input from the public internet. An integration test writes a payload at exactly the
  limit so the two statements of the number cannot drift apart unnoticed. No matching constraint on
  `actions`: its bound is a *count*, which a cheap CHECK cannot express.
- **What may travel in a payload** is `personal-data.md`'s row, not this page's - an opaque field is
  where personal data hides, and the map is what erasure and export read.

**Shipped in `2-06`**: `messages` is `PARTITION BY RANGE (created_at)`, monthly. Rationale: bounded
index size, cheap retention (`DROP` a partition instead of a mass `DELETE`), and a concrete thing to
demonstrate.

`Stage2PartitionMessages` converts the table (rename old, create the partitioned replacement plus
the current month and the next two, copy every row across, drop the old table - Postgres cannot
`ALTER TABLE` a regular table into a partitioned one, `Migrations` below has the reason this is
marked one-way) and `PartitionMaintenanceJob` (`Ago.Chat.Worker`, `PeriodicTimer`, daily) keeps the
current month plus the next two always present afterward, via `CREATE TABLE IF NOT EXISTS ...
PARTITION OF` per partition - idempotent by construction, safe under a missed run or two `Worker`
replicas racing to create the same one.

**Deepened once, in `13-06`**: each class-level partition above (`messages_free` etc.) is itself
`PARTITION BY RANGE (created_at)`, monthly — the shape `2-06` originally gave to `messages` itself
before `13-06` inserted the class level above it. `PartitionMaintenanceJob` now creates this grid once
per class, not once total; the same `CREATE TABLE IF NOT EXISTS ... PARTITION OF` idempotency applies
per class, unchanged.

**Consequence for the uniqueness guarantee** (`adr/0019`): Postgres requires every unique
constraint on a partitioned table - primary key included - to include the partition column. The
primary key becomes `(id, created_at)`, and the `(conversation_id, sequence)` unique index widens to
`(conversation_id, sequence, created_at)`. This is a real weakening: two racing inserts that
land in the same partition with different `created_at` values no longer collide at the storage
level. It is an acceptable one because this index was always the *last* line of defence
(`concurrency.md`) - the first is the `Conversation` aggregate's optimistic-concurrency
load-mutate-save on `xmin`, which still rejects the race that matters (two saves computing the same
`LastSequence`) regardless of what the `messages` index can see. **Widened a second time in `13-06`**
to `(id, created_at, retention_class)`/`(conversation_id, sequence, created_at, retention_class)` -
`adr/0019`'s own addendum has the detail; nothing about the argument above changed, only the column
count.

**Reading the partition list now needs `pg_partition_tree`, not a direct `pg_inherits` lookup on
`messages`.** Verified against a real Postgres 17 while building `13-06`: `pg_inherits` filtered to
`inhparent = 'messages'::regclass` returns only the three class-level partitions, never the monthly
leaves underneath them, now that there are two levels. `MessagePartitionPruneQuery.ListPartitionsAsync`
(shared by `MessagePartitionPruneJob`, `MessageSearchIndexJob` and `MessageSiteIdBackfillJob`) reads
`pg_partition_tree('messages') WHERE isleaf` instead, which returns the correct set regardless of
nesting depth.

## Personal data

`personal-data.md` maps which of the tables above hold personal data, and is the file a schema change
updates when it adds a column that holds something about a person. Two properties recorded there are
load-bearing for erasure and are easy to break from here without noticing: `outbox.payload` and
`webhook_deliveries.payload` hold no message bodies, so message content **at rest in Postgres** exists
in exactly two places (`messages.body` and the object store) rather than in every copy an event-driven
system would otherwise scatter.

**Qualified by `16-01`**: "exactly two places" is true of this database and not of the whole system.
The realtime fan-out path publishes a full `MessageDto`, body included, as a persistent message on a
durable broker queue, so message text also exists transiently in RabbitMQ and durably in any node
queue left behind by a replaced pod. `personal-data.md` has the mechanism and the bound; it changes
nothing about this schema, but it does change what "delete the row and you are done" means.

## Access strategy

Writes go through EF Core, one aggregate per transaction, no lazy loading. Reads go through Dapper
with hand-written SQL returning DTOs. Rationale and trade-offs: `adr/0004`.

**One deliberate exception, `10-02`**: `RegisterSiteHandler`'s bootstrap transaction writes `Site` +
two `roles` rows + `Operator` + two `operator_roles` rows together, via
`ISiteRegistrationRepository.TryRegisterAsync` (`Ago.Chat.Application.Abstractions`) - a real,
multi-aggregate provisioning step, not an accidental widening. `1-05`'s seed script already produces
the identical shape non-transactionally (idempotent `ON CONFLICT DO NOTHING` SQL, harmless to
re-run); a real caller hitting `POST /api/v1/sites` gets exactly one attempt, so a partial failure
here must not leave a site with no roles or an operator that resolves to nothing. Every other write
in this codebase still follows the one-aggregate rule above unchanged.

**The one cross-tenant read, `12-02`**: `PlatformOverviewReadStore.ListSitesAsync`
(`IPlatformOverviewReadStore`) is the only query in `ago-chat` that is not scoped to a single
`site_id`. Every other read takes a tenant-scoped id and its `WHERE` clause cannot address another
tenant's rows; this one deliberately takes no site parameter, because "how many accounts exist and what
is each one doing" has no answer inside one tenant. It is safe for a structural reason rather than a
careful one: exactly one endpoint reaches it (`GET /api/v1/owner/sites`), gated exclusively by `12-01`'s
`RequirePlatformOwner` (`adr/0032`), which is satisfied only by a Keycloak *realm* role - no row in
`roles`/`operator_roles`, however broadly seeded, can satisfy it. Read-only: one `SELECT`, no write
surface for the owner exists.

Two things about its shape are worth recording here because the table definitions above do not make them
obvious:

- **`messages` carries no `site_id`.** The tenant is reachable only through `conversations`, so any
  per-site message aggregate is a join (`conversations` filtered by `site_id` via
  `ix_conversations_site_all`, then each conversation's messages on the
  `(conversation_id, sequence, created_at)` unique index).

  **Changing, per `adr/0031`'s addendum (decided 2026-08-29, built by `18-01`)**: `messages` gains a
  plain denormalized `site_id` column and a composite index carrying it, so `18-01`'s tenant-scoped
  search predicate does not need the join above. The partition key is unaffected — the addendum's own
  reasoning is why: `site_id` was considered as a third partition dimension and rejected (partition
  count would multiply by tenant count, and it would not deliver real horizontal scale-out on a
  single Postgres instance regardless), so this is an ordinary column plus index, not a repartitioning.
- **A per-site message count must be time-bounded, not all-time.** Because `messages` is partitioned by
  `created_at` (above), a predicate on that column is what lets Postgres prune to the partitions the
  window covers; an all-time `COUNT(*)` or `MAX(created_at)` reads every partition that has ever existed
  and degrades for the life of the deployment. `12-02` uses a 30-day window - at most two monthly
  partitions - for both its message count *and* its "last activity", the latter being a real narrowing
  of what that field can mean (backlog `12-02` states it). The aggregates are computed per page row, so
  the work per request is bounded by the page size rather than by how many tenants exist.

## Migrations

**Verified**: `Stage1CreateChatSchema` (`1-04`) applied cleanly to a real Postgres (both the
`docker-compose` instance and a throwaway Testcontainers one), all tables/FKs/indexes landed as
designed, and `Ago.Chat.Integration.Tests` proves the unique `(conversation_id, sequence)` constraint
actually rejects a duplicate insert at the storage level. `Stage2AddOutboxAndInbox` (`2-02`) is
verified the same way: `outbox` and `inbox` are real tables (`adr/0005`, `adr/0017`), mapped through
`Ago.Platform.Persistence.Postgres`'s shared configuration rather than hand-rolled here - `outbox`
already has a real writer (`2-02`'s handlers). `inbox` gained its first real writer in `2-05`:
`UnreadCounterConsumer` stages its increment on the tracked `Conversation` and lets
`IInboxChecker.TryRecordAndSaveAsync` commit both in one `SaveChangesAsync` - proven live (real
Postgres, real RabbitMQ) that a redelivered event increments exactly once, not twice.
`Stage2AddConversationUnreadCounts` (`2-05`) adds `visitor_unread_count`/`operator_unread_count` to
`conversations`, both `integer not null default 0` - additive, reversible, no table rewrite.
`Stage5AddOperatorLastReadSequence` (`5-15`) adds `operator_last_read_sequence` the same way, and
deliberately does **not** backfill it from `last_sequence`: no operator has ever marked a conversation
read, so zero is the truthful value for every existing row, and claiming otherwise would be inventing
a fact. The visible consequence is intended - the first open after this ships clears the accumulated
backlog that `5-15` exists to fix.
`Stage2PartitionMessages` (`2-06`) is verified against a real Postgres (`Ago.Chat.Integration.Tests`,
via `PostgresFixture`'s from-scratch migration run): the rename-copy-drop conversion applies
cleanly, an insert landing in the current month succeeds without `PartitionMaintenanceJob` having run
first, and the widened `(conversation_id, sequence, created_at)` unique index still rejects a
duplicate insert post-partitioning. Explicitly one-way (`Down` throws) - see the Partitioning section
above for why reversing it is a data-recovery procedure, not a rollback.
`Stage4AddOperatorActiveChats`/`Stage4AddWaitingQueueIndex` (`4-01`) are both additive and reversible,
verified from-scratch the same way: `active_chats` lands as a genuine EF-visible shadow property
(confirmed by `OperatorCapacityStoreTests`' concurrent-claim proof actually reading/writing it), and
`ix_conversations_waiting` replaces the default FK index cleanly with no query regression found.
`Stage12AddSiteCreatedAt` (`12-02`) is additive and reversible, verified the same from-scratch way
(`PlatformOverviewFixture` migrates a fresh Postgres and then reads the column back through the real
query): one nullable `timestamptz`, no default, no backfill, no table rewrite.

`Stage14AddChannelIdentities` (`14-01`) is additive and reversible - a new table with two foreign keys
and no change to any existing column, so `Down` is a single `DROP TABLE` that genuinely restores the
prior schema. Nothing to backfill: no existing row has ever been reached through a channel. Verified
from scratch against a real Postgres the same way as the entries above (`ChannelIdentityPersistenceTests`,
via `PostgresFixture`'s own migration run), including that the unique index actually rejects a duplicate
`(site_id, kind, external_address)` at the storage level - proven with a raw insert that bypasses the
repository, and shown to be load-bearing by removing `unique: true` from the migration and watching that
one test go red.

`Stage13RepartitionMessagesByRetentionClass` and `Stage13AddMessageArchives` (`13-06`) are verified
against a real Postgres 17, from scratch: the two-level rename/create/copy/drop conversion applies
cleanly, existing `site_id` values and the pre-existing `ck_messages_content_length` CHECK constraint
both survive the copy (the latter found missing by a failing test during development, then restored -
the rename/drop step silently loses every constraint on the old table that is not explicitly
re-added), and a live-fire test proves a failed archive upload leaves the partition undropped. Both
migrations are additive/one-way respectively - `Stage13RepartitionMessagesByRetentionClass`'s `Down`
throws, for the same "reassembling a two-level grid is a data-recovery procedure, not a rollback"
reason `Stage2PartitionMessages` already established one level shallower.

EF Core migrations, one per change, named `<Stage><Verb><Subject>`. Rules:

- Always reversible, or explicitly marked one-way with a comment explaining why.
- Never edit a migration that has been applied anywhere but the local machine.
- Raw SQL (partitions, partial indexes, helper functions) goes into the migration via
  `migrationBuilder.Sql`, never into a hand-run script that will drift.

## AGO Calendar (Stage 20)

A **separate database**, in a separate repository, reached only by `Ago.Calendar.*` hosts. Built by
`20-01` (`Stage20CreateCalendarSchema`, `Ago.Calendar.Infrastructure.Postgres`) and extended by
`20-02` (`Stage20AddWorkerDayIndex`). The reasoning behind the decisions that shaped it - how time is
stored and where the no-overlap guarantee lives (`adr/0049`), how availability is generated without
ever overwriting what is already there (`adr/0053`), and how a slot is claimed under contention
(`adr/0059`) - is in those ADRs; this section records the shape. `20-03` added no schema: the booking
claim is a statement against tables `20-01` already built, which is what materialising slots in
advance was for.

Everything above about **ids (UUID v7), `timestamptz`, keyset pagination, partial indexes for
queue-like predicates, EF for writes / Dapper for reads, and one aggregate per transaction applies
here unchanged**. What follows is only what is specific to this product.

### Tables

- `tenants` - `id`, `name`, `created_at`. The account holder. Structurally what `sites` is for AGO
  Chat and deliberately not that row (`adr/0027`).
- `operators` - `id`, `tenant_id`, `display_name`, `external_subject_id?` (unique when present, the
  same partial-unique shape `adr/0022` added to `ago-chat`'s own table). **No `capacity`, no
  `active_chats`, no `status`** - the absence is the point: `adr/0027` rejected a shared `Operator`
  precisely because a booking queue is a work list, not a set of simultaneous attachments, and nothing
  in this product routes to a *particular* operator.
- `roles` - `id`, `tenant_id`, `name`, `permissions text[]`; `operator_roles` - `(operator_id,
  role_id)`. `adr/0016`'s pattern with an independent vocabulary (`booking:confirm`, `booking:reject`,
  `booking:cancel`, `booking:mark_no_show`, `customer:read`, `customer:edit`, `calendar:configure`).
  **The v1 seeded role set, stated plainly the way `1-05` states AGO Chat's: exactly one role,
  `"Operator"`, holding all seven** - in a one-person business the tenant, the operator and the only
  worker are the same human, so an operator login that could not configure its own calendar would be
  unusable by the target customer. Unique on `(tenant_id, name)`, never on `name` alone. **No writer
  in production yet** - `Role.SeedOperatorRole` exists and the provisioning transaction that calls it
  is `20-06`, the same position `ago-chat`'s `roles` was in at `1-04`.
- `workers` - `id`, `tenant_id`, `display_name`, `is_active`. The person a customer books; not an
  operator, and possibly with no login at all.
- `services` - `id`, `tenant_id`, `name`, `duration_minutes int`. Whole minutes in an integer rather
  than a Postgres `interval`: the domain's own invariant is already "a whole number of minutes", and
  an integer column stays trivially comparable for `20-02`'s availability queries.
- `calendars` - `id`, `tenant_id`, `name`, `time_zone` (**IANA id as text, never an offset**),
  `buffer_minutes`, `is_published`, `created_at`. `buffer_minutes` is per calendar, not per service or
  per worker (the product spec's own decision), and is consumed by `20-02`; nothing reads it yet.
- `customers` - `id`, `tenant_id`, `phone`, `display_name?`, `notes?`, `no_show_count`,
  `first_seen_at`, `last_seen_at`. The lead card. **Unique `(tenant_id, phone)`** - the same person
  booking at two shops is two cards, and one tenant's notes must never surface in another's console.
  That index is also `20-03`'s find-or-create backstop, the same "storage backstop, not the primary
  mechanism" division `adr/0019` draws for chat's message sequence. Personal data: see
  `personal-data.md`.
- `working_hours_rules` - `id`, `worker_id`, `calendar_id`, `day_of_week` (stored as the name, not the
  ordinal - .NET's `Sunday = 0` versus the ISO week is a trap worth not setting), `starts_at`/`ends_at`
  as **`time` without a zone**. Wall clock, deliberately: see `adr/0049`. v1 allows one calendar per
  worker, enforced in the aggregate (`Worker.JoinCalendar`) and **not** as a unique index on
  `calendar_workers.worker_id`, so widening it later removes a check rather than reversing a
  constraint.
- `events` - `id`, `tenant_id`, `calendar_id`, `worker_id`, `service_id?`, `customer_id?`,
  `starts_at`/`ends_at` (`timestamptz`), `local_date` (`date`), `status`, `confirmation_deadline?`,
  `created_at`, plus `xmin`. **One row is both the free slot and the booking that takes it** - status
  transitions, never a second row (`adr/0049`). `tenant_id` is carried even though it is reachable
  through `calendar_id`, deliberately learning from this page's own record that `messages` carries no
  `site_id` and every per-tenant message question is a join forever.
- `calendar_workers` - `(calendar_id, worker_id)`; `worker_services` - `(worker_id, service_id)`. Both
  owned by the `Worker` aggregate, because the invariants they carry are statements about a worker.
- `outbox` / `inbox` - the platform's own tables (`adr/0017`), taken unchanged through
  `ApplyOutboxInboxConfiguration()`. **The first evidence that generalisation was real rather than an
  AGO-Chat-shaped guess**: a second product consumes it with one line and no change to the platform.
  No writer here yet; `20-05`'s SMS event is the first.

### Keys, indexes and the one constraint that matters

- `ix_events_available` - partial, `(calendar_id, starts_at) WHERE status = 'Available'`. The direct
  analogue of `ix_conversations_waiting`: proportional to what is bookable rather than to everything
  ever booked. Proven to be the index the planner reaches for, by `EXPLAIN` against a real Postgres -
  the same bar `4-01` set, and with the same honesty about what that does and does not show (it shows
  an index *can* serve the predicate; whether it is faster than a scan is a measurement, and no
  measurement has been made).
- `ix_events_pending_confirmation` - partial, `(tenant_id, confirmation_deadline) WHERE status =
  'PendingConfirmation'`. Serves both of `20-04`'s readers - the auto-confirm sweep and the operator
  queue - over the same small, short-lived set.
- `ix_events_worker_day` - `(calendar_id, worker_id, local_date)`, added by `20-02`, and
  **deliberately not partial** unlike the two above. Every question that item asks is "what is on this
  worker's day": has this day been generated (the materialisation job's non-destructive rule), what is
  on it before a manual edit rewrites it, and which rows a day off deletes. The rule turns on whether
  a day holds *any* row - booked, blocked and cancelled included - so a status filter would hide
  exactly the rows whose presence is the decision. This is also the index `local_date` was stored for
  rather than derived: an `AT TIME ZONE` predicate is non-sargable, so no index could serve a per-day
  query. Proven to be the index the planner reaches for by `EXPLAIN`, with the same caveat as
  `ix_events_available` - it shows an index *can* serve the predicate, not that it is faster than a
  scan, which nothing has measured.
- `ix_calendars_published` - partial on `tenant_id WHERE is_published`.
- `ux_customers_tenant_phone`, `ux_roles_tenant_name`, `ux_operators_external_subject_id` (partial on
  `IS NOT NULL`).
- **`ex_events_worker_no_overlap`** - a GiST **exclusion constraint**, `EXCLUDE USING gist (worker_id
  WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&) WHERE (status <> 'Cancelled')`, needing the
  `btree_gist` extension. This is the no-double-booking guarantee, and it is a constraint rather than
  application code for the reason `adr/0049` argues at length: an aggregate can enforce a rule about
  itself, and only the database can enforce one about the relationship between rows. `'[)'` matches
  `TimeSlot.Overlaps` exactly so adjacent slots do not collide; `Cancelled` is excluded because a
  cancellation frees the time, while `Blocked` and `NoShow` are not, because both still occupy the
  worker.
- Optimistic concurrency is `xmin` on `events`, mapped exactly as `1-04` mapped it on `conversations`.

### Availability materialisation (`20-02`)

`events` rows in `Available` status exist before any customer books, generated from
`working_hours_rules` out to a rolling horizon by **`AvailabilityMaterializationJob`**
(`Ago.Calendar.Worker`). Documented here for the same reason `PartitionMaintenanceJob` is: a
background job that keeps rows ahead of need is part of the data model's shape, not an implementation
detail of one host.

- **Shape**: `BackgroundService` + `PeriodicTimer`, exactly `PartitionMaintenanceJob`'s form - runs
  once immediately, then every `Interval`, catching and continuing on anything but cancellation. Walks
  every tenant by keyset, then every published calendar of each, one DI scope per calendar so a
  calendar that fails alone fails alone.
- **Configuration**, all named and none measured: `Interval` (daily), `HorizonDays` (30),
  `TenantPageSize` (100). Thirty days is a legible starting point, not a claim - the only real
  constraint is that the horizon exceeds how far ahead customers book, and this product has no traffic
  to know that from. `3-05`'s rate-limit buckets set the same precedent.
- **The invariant, and it is the whole item**: *the job only ever inserts rows into business-local
  days that have no event row at all.* It never updates, never deletes, and never regenerates a day it
  has already generated. Everything else follows - a `PendingConfirmation`/`Booked`/`Cancelled`/
  `NoShow` row cannot be touched because its day is skipped, and a day a tenant edited by hand cannot
  be overwritten for the same reason. Nothing marks an edited day as edited; the absence of a
  mechanism is the mechanism.
- **A day off is a row, not an absence.** `DeleteDayOffHandler` deletes the day's unclaimed rows and
  writes one `Blocked` event spanning what it replaced. Deleting them and leaving the day empty would
  have been undone by the very next run. The blocking row is also literally true and participates in
  `ex_events_worker_no_overlap`, so nothing can be materialised or booked across it either.
- **Idempotent by construction**, two mechanisms deep: a `SELECT DISTINCT local_date` existence check
  keeps the common case from generating anything, and the insert itself is a single
  `INSERT ... unnest(...) ON CONFLICT DO NOTHING` with no conflict target - which in Postgres covers
  the exclusion constraint as well as the primary key. Two `Worker` replicas racing the same day both
  succeed and exactly one set of rows lands; the loser's rows are dropped rather than its transaction
  aborted. No lease, no advisory lock, no leader election (`adr/0053`).
- **Manual edits are day-scoped rewrites**, not row nudges: both `DeleteDayOffHandler` and
  `EditDayBoundaryHandler` go through one `DELETE ... WHERE status IN ('Available','Blocked')` plus an
  insert, in one transaction. A claimed row is not addressable by that `DELETE`, so no edit can delete
  a booking - and a caller whose pre-read was overtaken by a customer has its replacements refused by
  the exclusion constraint rather than silently losing the booking.

### The booking claim (`20-03`)

Two statements, one transaction, no read that a write decision depends on. The reasoning is
`adr/0059`; the shape is here because it is the second place in this codebase to make the same call
`4-01` made for `operators.active_chats`, and a reader comparing them should find both on this page.

```sql
-- the claim: the verdict IS the rows-affected count
UPDATE events
SET status = 'PendingConfirmation', customer_id = @customerId,
    service_id = @serviceId, confirmation_deadline = @deadline
WHERE id = @eventId AND calendar_id = @calendarId
  AND status = 'Available' AND starts_at > @now
RETURNING worker_id, starts_at, ends_at, local_date;

-- the lead card: found-or-created, arbitrated on ux_customers_tenant_phone
INSERT INTO customers (id, tenant_id, phone, display_name, no_show_count, first_seen_at, last_seen_at)
VALUES (@id, @tenantId, @phone, @displayName, 0, @now, @now)
ON CONFLICT (tenant_id, phone) DO UPDATE
    SET last_seen_at = GREATEST(customers.last_seen_at, EXCLUDED.last_seen_at),
        display_name = COALESCE(customers.display_name, EXCLUDED.display_name)
RETURNING id;
```

- **Raw SQL, a stated exception to `adr/0004`'s "EF for writes"**, with the same qualifying reason
  `4-01` gave: a compare-and-set is what EF's load-mutate-save cannot express in one round trip, and
  EF's own answer to the gap - optimistic concurrency - turns an ordinary lost race into an exception
  on the most contended path in the product. Everything else in `Ago.Calendar.Infrastructure.Postgres`
  is still EF.
- **Every predicate is in the `WHERE` clause, not in application code.** `calendar_id` is there
  because the endpoint is unauthenticated and the route's calendar id is the only thing binding a
  request to a tenant; `starts_at > @now` is `Event.Claim`'s own precondition restated where it
  cannot go stale. A row count of 0 covers all of them and is reported as one message, so a stranger
  cannot use the error to learn which event ids exist.
- **A row count of 0 is an ordinary outcome**, never logged at `Error`, never a 500, never an
  exception. It surfaces as `409 booking.slot_unavailable`.
- **Both statements share one transaction, and the reason is personal data**, not consistency: a lost
  claim rolls the lead card back, so the endpoint never accumulates phone numbers for bookings that
  did not happen. It also fixes a single lock order - the customer row first, always - so two
  bookings from one number cannot deadlock.
- **`GREATEST`/`COALESCE` are the merge rules**, not decoration: the watermark never rewinds (the same
  rule `Customer.Touch` enforces in memory), and a name an operator curated is never overwritten by
  whatever a public form was typed into next time.
- **Proven under real contention**, not asserted: `Ago.Calendar.Concurrency.Tests` releases 2, 8 and
  24 callers through one gate, each on its own connection opened before the gate, and asserts exactly
  one booking and exactly one lead card afterwards.

**Redis joins this product's dependency list here**, for one thing only: the booking endpoint's two
rate-limit buckets (per phone, per calendar), through `IRateLimiter` reused unchanged from
`Ago.Platform.Abstractions`. Never a source of truth - the claim reads nothing from it
(CLAUDE.md rule 8). What is stored in it, and for how long, is a row in `personal-data.md`.

### The confirmation sweep (`20-04`)

The second half of `20-03`'s two-step mechanic, and **no schema change at all** - it acts on rows
`20-01` shaped and reads through an index `20-01` created. Recorded here because a background job
that decides an outcome is part of the data model's shape, the same way `PartitionMaintenanceJob` and
`20-02`'s materialiser are.

- **Same shape as two mechanisms already shipped**, deliberately: `PeriodicTimer`, a
  `SELECT ... FOR UPDATE SKIP LOCKED` batch claim, one transaction per batch, catch-and-continue -
  `ConversationAssignmentJob` (`4-02`) and `OutboxDispatcher` (`2-04`). `SKIP LOCKED` is what makes
  two `Worker` replicas safe with no lease, no advisory lock and no leader election: they split the
  rows instead of racing for one, and a row somebody else holds is picked up next tick with no
  un-claim step, because the lock dies with its transaction.

```sql
SELECT id FROM events
WHERE tenant_id = @tenantId
  AND status = 'PendingConfirmation'
  AND confirmation_deadline <= @now
ORDER BY confirmation_deadline
LIMIT @batchSize
FOR UPDATE SKIP LOCKED;
```

- **The claim and the transition commit together.** The claim is raw Npgsql on the `DbContext`'s own
  connection; the `Event.Confirm` that follows is EF on that same connection inside that same
  transaction, so the row lock is still held when the aggregate transitions. `4-02` reached the same
  arrangement from the other direction when it refactored `OperatorCapacityStore`. The
  `BookingConfirmed` outbox row is staged in the same `SaveChangesAsync` (rule 4) - proven by
  comparing the two rows' `xmin`, which is a direct observation of one transaction rather than an
  inference from both being present.
- **`ix_events_pending_confirmation`** - `(tenant_id, confirmation_deadline) WHERE status =
  'PendingConfirmation'`, created by `20-01` for exactly these two readers and now having both: the
  sweep's claim and the operator queue's read.
- **`confirmation_deadline <= @now` is the one place a clock decides an outcome in this product**
  (`CLAUDE.md` rule 11). `now` is read once per tenant per tick and passed down as a parameter, never
  read again further in, so every row in one tick is judged against one instant. The boundary is
  inclusive and there is a test standing one second either side of it.
- **The sweep's failure mode is inverted, and that is why it is documented here.** Everywhere else in
  this system, a job that stops running means work does not happen. Here **doing nothing confirms the
  booking**, so a dead sweep silently converts every pending booking into one that never confirms,
  while the customer has already been told they are booked. The signal is an outcome count -
  "bookings past their deadline and still pending" - not a liveness check, so it climbs whether the
  loop died, the query broke or the transaction never committed. It surfaces as a `Warning` log line
  per tenant per tick and as an `isOverdue` flag on the operator queue. **It is not yet a metric and
  cannot yet raise a `15-03` alert**: `Ago.Calendar.Worker` deliberately takes no
  `Ago.Platform.Observability` reference (`7-09`, `20-00`), so this host has no meter and no scrape
  endpoint. Stated as a gap rather than implied to be covered.

### The shared pending-bookings queue (`20-04`)

One queue per tenant, spanning every calendar, worked by any operator holding `booking:reject`. No
per-operator assignment exists - the same "unassigned queue" shape AGO Chat's conversation queue uses,
and the reason `Ago.Calendar.Domain.Operator` carries no presence and no capacity (`20-01` called a
status column with no reader "a guess about `20-04`"; this is `20-04` and it does not want one).

**This product's first Dapper read model** (`adr/0004`), on its own `NpgsqlDataSource` rather than the
write context's connection - a read model sharing a write context inherits its change tracker and any
ambient transaction, and a queue screen has no business inside a write transaction. It reads through
the same `ix_events_pending_confirmation`, carries no name and no phone number (a list does not need
them, and a joined lead card would put personal data into every row of a screen an operator leaves
open all day), and computes `is_overdue` in SQL from the caller's `@now`.

### Migration

**Verified**: `Stage20CreateCalendarSchema` applies cleanly from scratch to a real Postgres
(Testcontainers, `Ago.Calendar.Integration.Tests`), and is **fully reversible** - including its two
hand-written `migrationBuilder.Sql` statements, which is the half a `DropTable`-only `Down` silently
gets wrong. The reversibility is a test that reverts to `"0"`, asserts the tables, the constraint and
the extension are all gone, re-applies, and asserts they are all back with no pending model changes.
The overlap guarantee is proven by two genuinely concurrent transactions racing for one worker's time,
with the loser refused by `23P01`; deleting the constraint from the migration turns exactly four tests
red, which was checked rather than assumed.

## Provider swap (Stage 9)

`Ago.Chat.Infrastructure.MySql` implements the same ports. Known frictions to document rather than
hide: `jsonb` vs `json`, UUID storage, `SKIP LOCKED` support, partitioning syntax, and
case-sensitivity of identifiers. The honest list of frictions is the point of the exercise.

**AGO Calendar adds the hardest entry on that list so far** (`20-01`): MySQL has neither exclusion
constraints nor range types, so `ex_events_worker_no_overlap` has no translation at all - a MySQL
adapter would need a different *mechanism* (a lock, or a serializable transaction), not different DDL.
Also Postgres-specific here: the partial indexes on `events`/`calendars`, `text[]` for
`roles.permissions`, `tstzrange`, and the `btree_gist` extension. Stage 9 is deprioritized
(`roadmap.md`), and this entry exists so that if it is ever revived nobody discovers the exclusion
constraint by hitting it.
