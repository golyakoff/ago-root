# ADR-0173: The AI add-on gate is three independent facts, and the vendor client is lazy so a refusal constructs nothing

- **Status**: Accepted
- **Date**: 2026-09-14
- **Stage**: 25

## Context

`24-08` found that the two AI features (`19-01` reply draft, `19-02` background categorisation) were
switched on by **AGO, deployment-wide**: `ChatModule` registered the real YandexGPT client whenever an
API key and folder id were present, and nothing per-tenant existed at all. Nothing reached the vendor
only because no key was set in any overlay. `docs/compliance-checklist.md`'s H4 was red for this.

The law decides the shape, and `25-04` records the reading checked against sources on 2026-09-06.
Through `adr/0076` the **tenant** is the operator for a visitor's conversation data and AGO is the
processor. Art. 6 ч. 3 lets an operator entrust processing to another person **with the subject's
consent**; art. 6 ч. 4 says the person processing on the operator's instruction is **not obliged to
obtain** that consent. So sending a visitor's conversation to an LLM vendor needs a basis that exists
**for the visitor**, and obtaining it is the tenant's obligation rather than ours. The tenant's
acceptance of AGO's own terms is therefore necessary and **not sufficient**.

Three further constraints came from the item's own decisions, all the author's, 2026-09-06: the add-on
is a paid module reusing `22-07`/`adr/0093`'s existing quantity grants rather than a new mechanism; it
is off by default for everyone; and only conversations **from the moment of enabling** are ever sent,
because the archive's visitors wrote before this purpose existed.

## Decision

**1. Three independent conditions, re-read on every call, in one Application-layer policy.**
`Ago.Chat.Application.UseCases.AiAddOn.AiProcessingGate` answers "may this conversation's text reach an
LLM vendor": the site holds an effective quantity of this deployment's AI module key; the site has an
enablement row that is on; and the conversation was **created** at or after that row's cut-off. It is a
class in Application, not a port — every fact it composes already has a port, and nothing about the
rule belongs to infrastructure.

**2. The entitlement is never captured into the enablement row.** A lapsed subscription must stop
transmission without anyone switching anything off, so the quantity is read fresh each time rather than
snapshotted at enable time.

**3. The tenant's declaration of a lawful basis is its own table, never a column and never an
acceptance.** `ai_processing_basis_declarations` holds one insert-only row per declaration, carrying
the declaring **operator** and its own timestamp. The acceptance of the agreement stays a `24-01`
`AcceptanceRecord` whose subject is the **tenant** and which names the document version. Enabling
requires both and refuses each absence with its own error code, so "accepted but not declared" and
"declared but not accepted" are two distinguishable states rather than one "not ready".

**4. Both AI call sites take their provider as `Lazy<T>`.** `CategorizeConversationHandler` and
`GenerateReplyDraftHandler` consult the gate before touching `.Value`, so a refused tenant causes the
real vendor client — its typed `HttpClient` included — **never to be constructed at all**.

**5. The cut-off compares against a conversation's creation, not its close**, and the comparison lives
in the gate rather than on the aggregate, because neither AI path ever holds the aggregate.

## Consequences

- **H4 closes on the mechanism.** A tenant has something to point at and refuse, and a dated, attributed
  answer exists to "on what basis did this conversation reach a vendor". The agreement's *wording* is
  still a draft a lawyer has not read; that half stays open and the checklist says so.
- **A test can assert the strongest form of the promise.** `Lazy<T>.IsValueCreated` fails on
  *construction*, which no call-count assertion on an already-built fake could ever show.
- **Two reads per categorisation candidate.** The background sweep now asks the gate per conversation —
  one small indexed read plus the grant read. Deliberately uncached: `caching.md`/rule 8, because the
  answer decides whether personal data leaves the deployment, and "off" must take effect on the next
  call rather than at the end of a TTL.
- **`Lazy<T>` is a novel DI shape in this codebase** and needs an explicit factory registration per
  port. Two exist; a third AI feature would need a third, and forgetting one is a silent regression of
  the "constructs nothing" guarantee rather than a compile error.
- **Re-enabling moves the cut-off forward**, so a tenant who toggles the add-on off and on loses the
  intervening conversations for ever. That is the conservative direction and it is accepted knowingly.
- **Republishing the agreement does not disable anybody already running.** It only blocks the *next*
  enable. Whether a new version should require re-consent is a lawyer's call, left open.

## Alternatives considered

- **A decorator on `IConversationCategorizer`/`IReplyDraftGenerator` in `Ago.Chat.Module`.** The natural
  home for a cross-cutting gate, and the shape `ResilientConversationCategorizer` already uses. Rejected
  because neither port's request carries a `SiteId` or a conversation, so the decorator could not have
  evaluated the gate without widening two contracts purely to serve it.
- **A boolean `has_accepted` column on the enablement row.** Rejected: it answers the wrong question the
  moment a new version is published, which is exactly when the answer matters. Comparing `24-02`'s
  current version against the tenant's own `24-01` records keeps one source of truth.
- **Folding the declaration into the acceptance** (one record, one click, a longer sentence). Rejected
  outright — it is the one thing the item names as its hardest requirement. Two statements made by two
  legal mechanisms, one of them about somebody else's customers, cannot share a row without becoming
  unanswerable later.
- **Collecting the visitor's own consent for this purpose** (`24-05`'s mechanism already exists).
  Rejected by the author as a separate item and a separate conversation about conversion; ч. 4 puts the
  obligation on the tenant, and the declaration is how that is recorded.
- **Gating in `ChatModule`'s existing key check alone** — i.e. leaving the switch AGO's and simply
  documenting it. That is the status quo H4 is red about.
- **Comparing the cut-off against `closed_at`** (the Done-when's own phrasing). Rejected as strictly
  weaker: it would send a conversation that ran for days before the tenant ever saw the agreement,
  merely because it happened to close afterwards. `created_at` satisfies the Done-when a fortiori, and
  it is what the agreement text itself promises.
