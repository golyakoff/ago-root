# Audit every hosted service in the Worker for multi-replica safety

- **Stage**: 15
- **Status**: ready
- **Raised by**: `14-16`'s own open question, kept rather than closed when that item merged
  (2026-09-02). `adr/0089` is the worked example of what this audit is looking for.
- **Blocks**: any decision to run `Ago.Chat.Worker` at more than one replica. It does not *make* that
  decision — that is a throughput question needing a load-test number (rule 7).

## Why this exists, in one sentence

`14-16` found that two of the Worker's hosted services were silently single-instance inside a host
`concurrency.md` documented as multi-replica; the reason nobody had noticed is that nobody had looked,
and **nobody has looked at the other thirty either**.

## The trap this is named after

Before `14-16`, the honest description of `TelegramLongPollingService` was *"appears safe"*. It was
not. `replicas: 1` hid it completely, and the failure would have surfaced as a provider problem the
first time somebody scaled the Worker for throughput — doing exactly what an architecture document
told them was supported.

Every service below currently has that same status: **not known to be unsafe, and not checked.** The
deliverable here is the check and its written result, including — especially including — the ones that
turn out to be fine.

## What exists, counted before scoping

`Ago.Chat.Worker/Program.cs` registers **32** hosted services. Two (`TelegramLongPollingService`,
`MaxLongPollingService`) are settled by `adr/0089`. **Thirty remain.** They are not one problem; they
are at least four, and the audit should say which each one is rather than giving a blanket verdict:

- **Broker consumers** (`OutboxDispatcher`, `UnreadCounterConsumer`, `ModuleTaskConsumer`,
  `ChannelMessageDeliveryConsumer`, `OfflineAutoReplyConsumer`, `LinkIdentityCommandConsumer`,
  `PhoneVerificationDeliveryConsumer`, `OperatorRemovedConsumer`, `AttachmentThumbnailConsumer`,
  `OperatorDisconnectGraceConsumer`, `ConversationAssignmentFanoutConsumer`). Competing consumers on a
  queue are the case the broker already handles, and rule 5 (idempotent consumers, at-least-once) is
  the standing defence. Expected to be fine — which is exactly why the audit must say so explicitly
  rather than skipping them.
- **Deliberate fan-out consumers** (`SiteCacheInvalidationConsumer`, `ConnectionFanoutConsumer`).
  These are the *inverse* case: they are supposed to run on every replica, and "coordinating" them
  would be the bug. `messaging.md` already records the fan-out-not-competing-consumers distinction.
  The audit's job here is to confirm each is on the side of that line it thinks it is.
- **Per-node in-process machinery** (`MessagePipelineWorkerHost`, `BatchFlusherService`). Node-local by
  design; each replica draining its own bounded channel is the intent, not a hazard.
- **Timer-driven jobs** (`ConversationAssignmentJob`, `OperatorDisconnectSweepJob`,
  `AutoCloseInactiveConversationsJob`, `ConversationCategorizationJob`, `DemoTenantExpiryJob`,
  `SubscriptionRenewalJob`, `AttachmentOrphanSweepJob`, `OutboxPruneJob`, `WebhookDeliveryPruneJob`,
  `InboxPruneJob`, `MessagePartitionPruneJob`, `MessageArchiveJob`, `ConversationErasureJob`,
  `SiteErasureJob`, `SiteExportJob`). **This is the group that actually needs thinking about.** A
  periodic job on N replicas fires N times, and whether that is harmless, wasteful, or wrong is a
  per-job question about what the job *does*.

## What a first pass already suggests, offered as a starting point rather than a finding

`ConversationAssignmentJob` and `AutoCloseInactiveConversationsJob` visibly claim work
(`SKIP LOCKED`), which is the shape `concurrency.md` already documents for the contended path.

`SubscriptionRenewalJob` is the one that prompted writing this down. It lists due subscriptions
(`ListDueForRenewalAsync`) and then processes each by id, with no claim visible in the job or in the
repository it calls. Two replicas would list the same rows and process them twice. Whether that is
harmful depends entirely on whether `ProcessSubscriptionRenewalHandler` is idempotent — a
compare-and-set on the period, a unique index, something. **That question is not answered here on
purpose**: a five-minute grep is how "appears safe" gets written down as fact, which is the failure
this item exists to prevent. It is named only so the audit starts somewhere useful, and because
billing is where a double-run would be least forgivable.

Note also that a claim mechanism can legitimately live *downstream* of a job, in the repository or
handler it calls. Reading the job class alone is not the audit.

## Scope

- **Every one of the thirty gets a verdict**, recorded in a table in `concurrency.md`: safe under N
  replicas and by what mechanism; safe only because something downstream is idempotent (naming it);
  deliberately fan-out; or **not safe**, with what would go wrong.
- **Anything found unsafe gets an item of its own**, not a fix smuggled into this one. This item's
  deliverable is the audit and its record; turning one job into a claim-based job is a separate slice
  with its own tests.
- **`concurrency.md` gains the table**, because the answer must be findable by the next person who
  wonders whether the Worker scales — which is how `14-16` happened in the first place.

## Out of scope

- Raising `replicas` in `ago-deploy`. Separate decision, needs a number (rule 7). The manifest comment
  already says so.
- The Api and Webhooks hosts. They register hosted services too, and the same question applies, but
  the Worker is where the periodic jobs live and is the host anyone would scale first. If the audit
  turns up a reason to widen, say so rather than widening silently.
- Fixing anything. See Scope.

## Done when

- [ ] All thirty are listed with a verdict and the reason for it, in `concurrency.md`, including the
      ones that are fine — an audit that only records problems cannot be distinguished later from an
      audit that was never finished.
- [ ] Every "safe because X is idempotent" verdict names X and points at the thing that enforces it (a
      unique index, a compare-and-set, a claim), rather than asserting idempotency.
- [ ] The two deliberate fan-out consumers are confirmed to be fan-out on purpose, against
      `messaging.md`, and the audit says what would break if they were made competing.
- [ ] `SubscriptionRenewalJob` specifically has a stated answer, because it is the one this item was
      written around and the one where being wrong costs money.
- [ ] Anything unsafe has a backlog item raised for it, referenced from the table.
- [ ] Where a verdict rests on behaviour rather than on a visible mechanism, it is proven by a test
      rather than by reading — at least for any job whose double-run would touch money, delete data, or
      send something outward.

## Open questions

- **Whether the answer should be a mechanism rather than a table.** If the audit finds many jobs that
  need coordinating, the honest fix may be a shared "run this periodically, on one replica" primitive
  built on `adr/0089`'s advisory lock, rather than fifteen individual claim implementations. Worth
  deciding *after* the audit — building the primitive first would be guessing at how many callers it
  has, which is the failure `clean-architecture.md` warns about.
- **Whether `replicas: 1` should stay after the audit passes.** Nothing in this item requires
  changing it, and the load-test evidence rule still applies. But if the audit finds everything safe,
  the only remaining reason to stay at one replica is that nobody has measured the need — which is a
  different and more honest sentence than the one that stands there now.
