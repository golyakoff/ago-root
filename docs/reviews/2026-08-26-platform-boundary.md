# Where the communication surface belongs — a boundary review

- **Date**: 2026-08-26
- **Status**: findings only. **This document decides nothing.** It exists so the decision can be made
  from evidence; the ADR that follows is the author's to write.
- **Question**: three propositions were raised — that fundamental roles (tenant, operator, customer)
  are emerging and may belong in the platform; that the widget is a universal communication window and
  two widgets for one customer is unacceptable; and that AGO Inbox is a third product whose point is
  that the chat widget becomes one entry point among several. Underneath all three: **does the
  communication surface belong to AGO Chat, to the platform, or to a product that does not exist yet?**

## Where this file lives, and why here

`conventions/naming-and-structure.md` names five documentation homes — `architecture/`, `adr/`,
`backlog/`, `conventions/`, `runbooks/` — and **none of them fits a findings document**.
`architecture/` states what the design *is*, so an open question filed there would read as settled.
`adr/` is for decisions, and this is deliberately not one. `backlog/` holds work, and this is not work.

So this proposes a sixth: **`docs/reviews/<date>-<topic>.md`**, following the precedent
`load/reports/` already sets in this repository — dated, one topic per file, written to be read once
and then superseded by whatever it feeds. If the author would rather not have a new folder, the
next-best home is `known-limits.md`, at the cost of turning a 400-line analysis into a bullet.

## Method, and what I could not establish

Every claim below is traceable to a file or a measurement. Where a number required judgement, it says
so and gives the unjudged floor beside it.

Similarity figures come from a line-level `difflib` ratio after normalising away the product name and
whitespace — it measures "the same idea written the same way", not a byte diff. Comment-stripped
figures are given where comments dominate a small file.

**What I could not establish:**

- **AGO Calendar's domain code is not on `main`.** `ago-calendar/origin/main` is `9ebdfa2`, the `20-00`
  scaffold; `Ago.Calendar.Domain` there contains no source files at all. Everything measured below
  comes from the unmerged `feat/20-03-booking-claim` branch (`0d71140`, which carries `20-01` and
  `20-02`). It is real, reviewed code, but it is not merged, and it can still change.
- **Calendar has no authentication yet.** `Ago.Calendar.Api/Program.cs` is 32 lines and there is no
  claims transformation anywhere in the repository. So the duplication `adr/0027` explicitly accepted —
  a copied `OperatorIdentityClaimsTransformation` — **has not happened yet**. That ADR's central cost
  is still theoretical, and this review cannot say whether copying it will feel right in practice.
- **No customer-facing evidence.** Proposition 2 rests partly on what a shop with both products would
  tolerate. There are no such shops. The product claim is taken as given and only its *architectural*
  consequences are examined.
- **Nothing was run.** This is a reading exercise; no test was executed and no branch was built.

---

## 1. Verified premises

**"Ten packages and not one domain concept" — confirmed.** `ago-platform/src` holds exactly ten
projects (`Abstractions`, `Caching.Redis`, `Hosting`, `Kernel`, `Messaging.RabbitMq`, `Observability`,
`Persistence.Postgres`, `Realtime`, `Resilience`, `Storage.S3`). A case-insensitive search across all
of their `.cs` sources for `tenant`, `siteid` or the word `site` returns **12 matches, every one of
them inside a comment** — and 6 of the 12 are the English phrase "call site", which is not the concept
at all. The 4 that genuinely refer to tenancy are all naming a *product's* scheme as something the
platform deliberately does not know: `CacheKey.cs:6` offers `site-config:{public_key}` as an example
of a namespace, and `IFileStorage.cs:8` says outright that "a product's own key-naming scheme
(site/conversation/attachment ids) is not" this port's business.

There is no tenant type, no tenant parameter, and no tenant-shaped generic argument anywhere in the
platform. The premise is verified, and the platform's own comments show it was deliberate.

**The widget is already not privileged over other entry points — in shipped code.** `14-01` merged
`ChannelIdentity`, `ChannelKind`, `ExternalChannelAddress`, `ExternalMessageId` (`Ago.Chat.Domain`)
and `IInboundChannelAdapter`, `IInboundChannelAdapterRegistry` (`Ago.Chat.Application.Abstractions`).
`ReceiveChannelMessageHandler` maps an inbound channel message onto the same
`StartConversation` + `SendVisitorMessage` path a widget message takes. Proposition 3's *observation*
— that the widget becomes one entry point among several — is therefore already true of the code, today,
without anything being promoted anywhere.

---

## 2. What is actually duplicated between `Ago.Chat.*` and `Ago.Calendar.*`

Normalised similarity, corresponding file against corresponding file:

| File | Similar | Chat | Calendar | Identical lines |
|---|---:|---:|---:|---:|
| `ArchTestAssertions.cs` | **100%** | 12 | 12 | 12 |
| `BclAssemblyNames.cs` | **100%** | 10 | 10 | 10 |
| `CancellationTokenTests.cs` | **100%** | 39 | 39 | 39 |
| `ForbiddenTypeTests.cs` | **100%** | 32 | 32 | 32 |
| `LayeringTests.cs` | 98% | 31 | 30 | 30 |
| `TimeAndIdentityTests.cs` | 96% | 48 | 52 | 48 |
| `UseCaseConventionTests.cs` | 91% | 24 | 29 | 24 |
| `IlMemberScanner.cs` | 84% | 32 | 44 | 32 |
| `PostgresFixture.cs` | 65% | 46 | 64 | 36 |
| `DockerResourceLock.cs` | 62% | 66 | 53 | 37 |
| `TestAssemblies.cs` | 61% | 47 | 52 | 30 |
| `PlatformBoundaryTests.cs` | 44% | 24 | 40 | 14 |
| `IDomainEvent.cs` | 70% | 10 | 10 | 7 |
| `Operator.cs` | **22%** | 37 | 99 | 15 |
| `Permission.cs` | **17%** | 43 | 38 | 7 |

### Copied on purpose

`adr/0027` chose to copy the claims transformation. **That copy does not exist yet** (see Method), so
the category is currently empty in practice. The ADR's argument for it is unaffected; only its
evidence is missing.

### Converged by accident — the interesting category

**227 identical lines across eight architecture-test files**, none of which anybody decided to copy.
Each repository grew its own arch-test suite to enforce rules that come from `clean-architecture.md`
and `adr/0011` — that is, **platform rules, not product rules** — and independently arrived at the same
code. `Ago.Calendar.Architecture.Tests` additionally carries `ChatBoundaryRule.cs`/`ChatBoundaryTests.cs`
(148 lines) with no Chat counterpart, which is the one genuinely product-specific rule in the set.

`DockerResourceLock.cs` exists **three times** (Chat integration, Calendar integration, Calendar
concurrency) at 62% similarity, solving a machine-wide container-contention problem that has nothing to
do with either product.

**This duplication is real and it is not about roles.** It is test scaffolding for platform rules. It
argues for a shared test-support package, not for hoisting a domain concept.

### Not duplicated at all — and this is the load-bearing result

`Operator` is **22% similar**; `Permission` is **17%**.

| | Chat `Operator` | Calendar `Operator` |
|---|---|---|
| Shared | `Id`, `<tenant>Id`, `ExternalSubjectId` | same three |
| Only here | `Status`, `Capacity` | `DisplayName`, `Roles` (in-aggregate), `Grant`, `LinkExternalIdentity`, `Rename` |

The intersection is three fields, and all three are **the identity link** — precisely the part
`adr/0027` says lives in Keycloak rather than in either product.

They have also diverged *further* than `adr/0027` predicted. That ADR argued from capacity versus a
booking queue. In the code as written, Calendar's `Operator` holds its role assignments **inside the
aggregate** (`_roles`, `Grant(Role)`), while Chat's roles live outside it entirely, in
`Infrastructure.Postgres`'s `RoleRecord`/`operator_roles` join read by `PermissionChecker`. Calendar's
carries a `DisplayName`; Chat's deliberately carries no name at all (`personal-data.md`: the
`operators` table has "no name, no email"). A shared `Operator` would need a per-product extension
point on day one — which is exactly the smell `clean-architecture.md`'s second qualifying test exists
to catch.

**I tried to break `adr/0027` and could not.** The measurement strengthens it: the two entities are
less alike in code than they were in prose.

---

## 3. How chat-specific `ago-widget` actually is

`ago-widget/origin/main` (`8352e9e`), production source only — the 14 test files (1,968 lines) and the
2 test helpers (238 lines) are excluded.

**Total production: 2,317 lines across 17 files.**

### Reusable by a booking flow with no conversation concept at all — 425 lines (18%)

| File | Lines | What it is |
|---|---:|---|
| `src/tokenExpiry.ts` | 86 | JWT `exp`/`nbf` parsing. No product concept |
| `src/index.ts` | 56 | Script-tag bootstrap, `document.currentScript`, single-global guard |
| `src/ui/focus-trap.ts` | 55 | Keyboard containment in the panel |
| `src/protocol/dedup.ts` | 48 | Bounded seen-id set |
| `src/config.ts` | 46 | Reads `data-site` and friends off the tag |
| `src/ui/appearance.ts` | 40 | Accent colour + corner from server config |
| `src/protocol/sequence.ts` | 29 | Monotone cursor |
| `src/errors.ts` | 24 | `guardSync`/`guardAsync` |
| `src/protocol/backoff.ts` | 21 | Full-jitter reconnect delay |
| `src/ui/shadow-root.ts` | 20 | Shadow DOM isolation |

This 18% is the **floor**: it required no judgement.

### Mixed — 1,687 lines (73%)

| File | Lines | Generic part | Conversation part |
|---|---:|---|---|
| `src/ui/widget.ts` | 657 | mount, shadow root, toggle/open/close, focus, session bootstrap | bubbles, composer, send, history, attachments, pending-send reconciliation |
| `src/session.ts` | 382 | renewal maths derived from `exp - nbf`, retry throttle, error taxonomy | `POST /api/v1/visitor-sessions`, `VisitorSession*` shapes |
| `src/ui/styles.ts` | 254 | launcher, panel, header, close, notice (≈ lines 1–130) | messages, bubbles, attachments, composer (≈ 130–254) |
| `src/connection.ts` | 250 | SignalR builder, token factory, backoff wiring, state machine, reconnect-resume | `/hubs/visitor`, `JoinAsync`, `SendMessageAsync`, `GetHistoryAsync`, `MessageReceived` |
| `src/storage.ts` | 144 | namespaced, failure-tolerant `localStorage` accessors | `conversation-id`, `last-sequence:{id}` |

### Conversation-only — 205 lines (9%)

`src/protocol/types.ts` (71, chat wire DTOs) and `src/attachments.ts` (134, chat upload flow).

### The number

Reading the mixed files and splitting them by inspection gives roughly **53% reusable** (~1,234 of
2,317). **That figure carries judgement and should be treated as an estimate**; 18% is the part that
does not.

### The measurement that does not need judgement

The three protocol primitives exist **twice already** — in `ago-widget` and in `ago-console` — and
nobody planned that:

| File | With comments | **Code only** | Widget | Console |
|---|---:|---:|---:|---:|
| `protocol/sequence.ts` | 93% | **100%** | 16 | 16 |
| `protocol/backoff.ts` | 80% | **100%** | 12 | 12 |
| `protocol/dedup.ts` | 64% | **84%** | 20 | 23 |
| `protocol/backoff.test.ts` | 100% | **100%** | 33 | 33 |
| `protocol/dedup.test.ts` | 100% | **100%** | 27 | 27 |
| `protocol/sequence.test.ts` | 96% | **96%** | 27 | 27 |

`ago-widget/src/connection.ts` says so in its own comment: *"Mirrors `ago-console`'s
`OperatorConnection`, which took the same shape for the same reason in `5-16` — the two repositories
keep converging on this because it is the same problem seen from two token issuers."*

**Two TypeScript clients of the same realtime protocol, in two repositories, maintaining byte-identical
copies of the ordering, backoff and dedup primitives. A booking widget would make it three.** The
platform ships `Ago.Platform.Realtime` for the server side of that protocol and has no client
counterpart at all.

### What this does and does not prove about proposition 2

It supports the proposition's premise and **not** its architectural conclusion, because the
proposition conflates two separable questions:

- **(a) One embed on the shop's page.** A shop running chat *and* booking must not paste two script
  tags and get two floating buttons. This is a genuine product constraint and nothing in the evidence
  contradicts it.
- **(b) One codebase for both.** This is a packaging question. 53% shared code can be had from a shared
  npm package with two thin product shells, and requires nothing to move out of AGO Chat.

**(a) does not imply (b), and neither implies that the communication surface leaves AGO Chat.** Even at
0% code reuse, (a) would still hold; even at 100%, the conversation model would still be Chat's.

**`20-06` is where (a) is currently decided, and it currently defaults the wrong way** — but less
starkly than "a live contradiction". Its Scope says "a new `ago-calendar-widget` **repository or
package**", and its own Open questions section already names "whether the widget is a new repository or
a new package inside `ago-widget`" as a decision that item must make. The plan leans toward two
widgets; it has not committed to them.

---

## 4. `Tenant`, examined on its own merits

`adr/0027` argued only about `Operator` and says nothing about `Tenant`. Applying
`clean-architecture.md`'s three qualifying tests as carefully:

**The evidence.** `Ago.Calendar.Domain/Tenant.cs` is 49 lines: `Id`, `Name`, `CreatedAt`, `Register`,
`Rename`. `Ago.Chat.Domain/Site.cs` is 116 lines: `Id`, `PublicKey`, `Name`, `CreatedAt`,
`AllowedOrigins`, `WidgetConfig` (accent colour, corner), `DemoExpiresAt`, `UpdateWidgetConfig`, and
domain events.

The intersection is **`Id`, `Name`, `CreatedAt`**.

And here is the part that matters more than the count: **every field `Site` has and `Tenant` lacks is
about the public communication surface.** `PublicKey` is what a `<script>` tag carries.
`AllowedOrigins` is which pages may embed it. `WidgetConfig` is what it looks like. `DemoExpiresAt` is
`8-07`'s minted demo tenant. The chat-specific part of Chat's tenant *is* the widget.

That is not a coincidence, and it cuts against hoisting rather than for it: Calendar's `Tenant` is
smaller precisely because Calendar has no embedded surface **yet**. `20-06` gives it one — a booking
widget needs a public key and an allowed-origins list, and `20-06`'s Scope already says so, adapting
`5-01`'s two-layer CORS model "from site to tenant". So the two will converge on roughly
`(Id, Name, CreatedAt, PublicKey, AllowedOrigins)` the moment `20-06` ships.

**Test 1 — "contains no domain concept."** Fails. A tenant is the account holder; it is the most
domain-laden concept either product has. `clean-architecture.md` says `IEventPublisher` qualifies and
`IConversationRepository` never will; `Tenant` is on the second side of that line.

**Test 2 — "a second product would plausibly use it unchanged."** Currently **passes**, on three
fields. After `20-06`, plausibly passes on five. This is the one test `Tenant` does better on than
`Operator` — and it is doing well on it only because the shared part is so thin that there is almost
nothing to disagree about.

**Test 3 — "can be described without naming chat, visitors, or operators."** Passes for the three-field
core. "The account holder, with a name and a creation time" needs no product vocabulary.

**Conclusion: two of three tests pass, and the one that fails is the first one — which is the one
`clean-architecture.md` states as an absolute** ("A candidate is platform only if **all** of these
hold"). More practically: what would be hoisted is a row with an id, a name and a timestamp. The
*value* of hoisting it would be that both products' tenant-scoping could be expressed once — but
tenant-scoping is already expressed once, as a **convention** enforced by tests
(`TenantScopeRule`/`TenantScopeExemptions` in Chat), and that convention is 227-lines-of-arch-test
duplicated, which §2 already identifies as the real shareable asset.

**So: no, on the current evidence — but for a different reason than `Operator`.** `Operator` should
stay split because the two are genuinely different. `Tenant` should stay split because the shared part
is too small to be worth a package, and because promoting it buys tenant-scoping consistency that is
better bought by sharing the *arch tests* that enforce it.

---

## 5. Where `ChannelIdentity` belongs, and what moving it costs

Today: `Ago.Chat.Domain` (5 files, ~330 lines — `ChannelIdentity`, `ChannelIdentityId`, `ChannelKind`,
`ExternalChannelAddress`, `ExternalMessageId`), with the ports in
`Ago.Chat.Application.Abstractions` (3 files) and the use case in `UseCases/ReceiveChannelMessage`
(3 files). 34 files reference the concept in total, but the rest is persistence, module wiring and
tests.

| Shape | Where it goes | Note |
|---|---|---|
| Surface stays Chat's | `Ago.Chat.Domain` — unchanged | `adr/0055` already argues this placement |
| Surface is a platform capability | a new `Ago.Platform.*` package | Fails qualifying test 1: `ChannelIdentity`'s whole purpose is to resolve to a `Visitor`. Would have to be generalised to "external address → opaque principal", at which point it is no longer the thing `ReceiveChannelMessageHandler` needs |
| Surface is its own product | `Ago.Inbox.Domain` | Natural home. It is the concept the product would be built around |

**The cost curve, which is the decision-relevant part.** `14-02` (MAX) and `14-03` (SMS) are unbuilt,
so **`channel_identities` has no production rows anywhere**. Moving it today is a file move, a
namespace change and one EF migration inside one repository — a day, with no data migration.

Once a channel adapter ships, real external identities accumulate. If the surface is still inside
`ago-chat`, moving it later is still a rename within one database. **If the surface has moved to a new
repository with its own database, it becomes a cross-database migration of personal data**, which
`personal-data.md` and `15-02`'s retention window both constrain.

So: the cost of moving `ChannelIdentity` **within** `ago-chat` is flat over time. The cost of moving it
**out of** `ago-chat` steps up sharply the moment `14-02`/`14-03` write their first rows — which makes
the repository question, not the namespace question, the one with a clock on it.

---

## 6. The three candidate shapes, costed

### Shape A — the surface stays AGO Chat's (status quo)

- **Moves**: nothing.
- **Breaks**: nothing.
- **ADRs superseded**: none.
- **Backlog invalidated**: none. `20-06` must still decide its own already-open widget-packaging
  question.
- **Repositories touched**: 0, or 1 if a shared client-protocol npm package is added (additive).

### Shape B — the surface becomes a platform capability

- **Moves**: `ChannelIdentity` + 4 companions out of `Ago.Chat.Domain`; `IInboundChannelAdapter` +
  registry out of `Ago.Chat.Application.Abstractions`; the client protocol primitives into a shared
  npm package.
- **Breaks**: `clean-architecture.md`'s first qualifying test, unless `ChannelIdentity` is generalised
  away from `Visitor` — and what survives that generalisation is a string pair, not an entity.
  `adr/0055` documents `IInboundChannelAdapter` as product-shaped *because* it is shaped around
  `Visitor`/`Conversation`, and says so in its Decision 3.
- **ADRs superseded**: `0055` (Decision 3 and its "Reusing this port for AGO Calendar's `ISmsSender`"
  contrast); `0027`'s Inbox paragraph.
- **Backlog rewritten**: `14-02`, `14-03`, `14-05` (target package changes); `20-06` (widget decision
  forced); `21-01` (integration shape changes).
- **Repositories touched**: `ago-platform`, `ago-chat`, `ago-widget`, `ago-console`, `ago-root` — **5**,
  plus `ago-calendar` when it catches up.

### Shape C — the surface becomes its own product, with Chat and Calendar behind it

- **Moves**: everything in B, plus `Conversation`, `Message`, `Visitor`, the message pipeline, the
  realtime hubs and the fan-out path out of `Ago.Chat.*` into a new `ago-inbox`. AGO Chat becomes a
  consumer of it.
- **Breaks**: `adr/0013` (three deployables split by failure profile — the pipeline and the hubs are
  what that split is *about*); `adr/0027` (its "Inbox is not a third product" conclusion);
  `adr/0055`; `adr/0012`'s repository test would need re-applying to a fourth product.
- **Data**: `conversations` and `messages` live in `ago_chat` with real rows and a partitioned,
  retention-classed schema (`adr/0031`). Splitting them out is a cross-database migration of the one
  table `personal-data.md` identifies as holding free-text personal data.
- **Backlog**: the whole of Stage 14, most of Stage 3–7's own descriptions, `8-05`'s demo topology.
- **Repositories touched**: **6** (a new `ago-inbox` plus all five).

---

## 7. What is irreversible, and what is cheap to undo

| Decision | Reversibility | When it gets more expensive |
|---|---|---|
| Sharing the client protocol primitives as an npm package | **Fully reversible** — purely additive; delete the package and the two copies are still there | Never. It gets *cheaper* to do and more embarrassing to skip as consumers multiply |
| Sharing the architecture-test scaffolding | **Fully reversible** | Never |
| Moving `ChannelIdentity` within `ago-chat` | Cheap: 5 files, one migration, no production rows | Flat. Rows appear with `14-02`/`14-03` but stay in one database |
| Moving `ChannelIdentity` out of `ago-chat` | Cheap today, **expensive after `14-02`/`14-03`** | Steps up when the first real external identity is persisted |
| Hoisting `Tenant` or `Operator` to the platform | Reversible while Calendar's tables are empty — they are, on `main` | Steps up when Calendar has production rows |
| **Which script tag a shop pastes on their page** | **Effectively irreversible** | The moment a real shop embeds it. Changing the tag afterwards is a customer-visible migration of somebody else's website |

The last row is the only one with a deadline, and `20-06` is where it is decided.

---

## 8. Findings

**The single most consequential finding: "the communication surface" is not one thing, and its two
layers have opposite answers.**

- The **transport/session layer** — reconnect backoff, ordering cursor, dedup, token renewal,
  namespaced storage, shadow-root isolation — is *provably* shared already. `sequence.ts` and
  `backoff.ts` are 100% identical code across two repositories that never coordinated, and a third
  consumer is planned. The platform has a server-side `Ago.Platform.Realtime` and **no client
  counterpart**, which is exactly why the duplication keeps happening.
- The **conversation layer** — `Conversation`, `Message`, `Operator`, the assignment engine, the
  permission vocabulary — is *provably* not shared. `Operator` 22%, `Permission` 17%, and diverging.

A question posed as "does the communication surface belong to Chat, the platform, or a new product?"
cannot be answered once, because the surface is two layers and they belong in different places.

**On the three propositions:**

1. **Roles in the platform — the evidence says no, for both.** `adr/0027` was tested against the code
   and came out stronger than it went in: `Operator`'s shared part is three identity fields, and the
   entities have diverged further than the ADR predicted. `Tenant` fails the first qualifying test and
   passes the other two only because its shared part is three fields. The author's instinct that
   *something* is emerging is right; the thing that is emerging is not a role.
2. **One widget for one customer — the product requirement is right; the architectural conclusion does
   not follow.** The evidence supports "a shop must not paste two script tags". It does not support
   moving the communication surface anywhere: 53% of the widget is reusable through a shared package,
   and the remaining conversation half stays Chat's either way. `20-06` should be told to produce one
   embed; it does not need the boundary to move to do that.
3. **Inbox as a third product — the observation is already true; the conclusion does not follow.** The
   widget is already one entry point among several in merged code. `adr/0027`'s reasoning that Inbox is
   not a third product *survives* proposition 2's attack: even under a shared widget, an inbound
   Telegram message still lands in a conversation with an operator, and that operator is Chat's.
   `21-01` — the one flow where a channel reaches Calendar — is already scoped as a cross-product call
   from `Ago.Chat.*` to `Ago.Calendar.Api`, and is blocked on an unresolved UX question, not on a
   boundary question.

**What the evidence does support doing** (all of it Shape A plus additive work):

- Extract the client protocol primitives into a shared package. Fully reversible, and the duplication
  is already measured at 100%.
- Extract the architecture-test scaffolding. 227 identical lines enforcing platform rules.
- Decide `20-06`'s widget-packaging question **deliberately and soon**, because it is the only
  irreversible one on the list.

**What the evidence does not support:** hoisting `Tenant` or `Operator`; moving `ChannelIdentity`;
creating `ago-inbox`. None of these has to be decided now, and none of them gets more expensive by
waiting — with the single exception that moving the surface *out of `ago-chat`* gets harder once
`14-02`/`14-03` persist real identities.

**Recommendation, stated plainly so it can be disagreed with: leave the boundary where it is, share the
two things that are already duplicated, and settle the widget-embed question in `20-06`.**
`adr/0027` appears to be correct, and the strongest evidence for that came from trying to break it.
