# 26-02 · Should the .NET hosts publish an OpenAPI description?

- **Stage**: 26
- **Status**: needs a decision
- **Found**: 2026-09-21, the author, reading `26-00`'s own `plan.md` ("No OpenAPI description of
  the API... a *generated* shared client is not an option that exists"): "Я не понимаю цены и
  последствий этого утверждения... Может быть нам его и сделать? Скажи цену и последствия если
  сделать и если не сделать этого." (I don't understand the price and consequences of that
  statement - maybe we should build it? State the price and consequences of doing it and of not
  doing it.)

## What this item is

**A question with a real answer, not yet a decision.** Per this project's own rule 14 (the
managing session files a found defect or open question as the question itself when it would
decide something, rather than quietly deciding it by building one way or the other), this item
exists to gather the actual facts and lay out the real trade-off - not to pick a side. The author
decides once the trade-off is on the table.

## What is actually true today, to be confirmed rather than assumed

*(Confirmed 2026-09-21 - see Findings §0 below.)*

`26-00`'s own investigation found no `AddOpenApi`, `MapOpenApi`, Swashbuckle, or NSwag anywhere in
`ago-chat`, `ago-platform`, or `ago-calendar` - confirm this is still current. Both existing
clients (`ago-console`, `ago-widget`) hand-write their own wire types from `Ago.Chat.Contracts`,
each stating explicitly in its own source why (`ago-console/src/realtime/protocol/types.ts`: "it
exists so the rest of the console never guesses field names").

## Scope

Answer, with real numbers and real citations to the code rather than estimates, both sides of the
trade-off the author actually asked for:

- **The cost of adding it.** Which ASP.NET Core packages/middleware, on which hosts
  (`Ago.Chat.Api`, `Ago.Calendar.Api`, any others that serve a real public contract) - .NET's own
  built-in `Microsoft.AspNetCore.OpenApi` versus Swashbuckle versus NSwag, and which one actually
  fits this codebase's own Minimal API style with the least fighting. Whether the *existing* wire
  types in `Ago.Chat.Contracts` already produce a usable spec as-is, or whether they need real
  changes (attributes, restructuring) to describe correctly - if the latter, name what changes and
  how invasive they are. Whether generating a *client* from that spec (for a future Android/iOS
  consumer, or for re-generating what `ago-console`/`ago-widget` hand-write today) is realistic
  given this API's own shape (SignalR hub methods are not naturally described by OpenAPI at all -
  say plainly what OpenAPI can and cannot cover here, since the realtime half of this product is
  the harder half).
- **The cost of not doing it.** This project's own actual history of contract drift between a
  hand-written client and the real server contract - search real commits/PRs/backlog items for
  cases where `ago-console`'s or `ago-widget`'s own hand-written types disagreed with what the
  server actually sent or expected, and what that cost (a bug, a review catch, a live incident).
  If the honest answer is "this has not actually happened much, or the cases that did happen would
  not have been caught by a generated client either", say so - the author asked for a real answer,
  not a justification for either side.
- **What it would unlock**, concretely: a generated Android/iOS client (partial - see the SignalR
  caveat above), tooling that can validate a request/response against the real contract in CI,
  a browsable API reference for anyone else who ever needs to integrate against this API.
- **What it would not change**: `adr/0178`'s own reasoning stands or falls on this - if OpenAPI
  existing changes the sharing-strategy calculus for a future generated mobile client, say so
  explicitly rather than leaving two documents quietly disagreeing.

## Out of scope

- Actually adding OpenAPI - this item is the analysis the author's own decision needs, not the
  implementation of either outcome.

---

# Findings (2026-09-21)

Every number below was counted in the working tree, not estimated. Where something could not be
verified on this machine it says so.

## 0. The current state, re-confirmed rather than assumed

`26-00`'s claim holds. There is no `AddOpenApi`, no `MapOpenApi`, no Swashbuckle, no NSwag and no
committed `.json`/`.yaml` specification anywhere in `ago-chat` or `ago-calendar`. There is also no
`.Produces`, `.WithOpenApi`, `.WithName`, `.WithSummary` or `.WithTags` call **anywhere in either
host** - zero occurrences across both.

`ago-platform` is not checked out in this workspace, so its half of the claim was not re-verified
directly. It does not matter for the answer: `ago-deploy/k8s/base` deploys exactly two HTTP hosts
that serve a public contract - `api` (`Ago.Chat.Api`) and `calendar-api` (`Ago.Calendar.Api`).
`worker`, `calendar-worker`, `migrator`, `calendar-migrator` and `webhooks` serve no routes;
`Ago.Chat.Webhooks` is an outbound dispatcher, not a receiver. **The blast radius of "add OpenAPI"
is two projects, not three hosts and not the platform.**

Both TypeScript clients do hand-write their wire types, and both say why in the same words:

- `ago-console/src/realtime/protocol/types.ts` (531 lines): *"it exists so the rest of the console
  never guesses field names"*.
- `ago-widget/src/protocol/types.ts` (240 lines): *"This file has no logic - it exists so the rest of
  the widget never guesses field names."*
- Beyond that file, `ago-console/src/api/` is 39 non-test modules, 7,080 lines, **185 exported
  `interface`/`type` declarations** - the REST half, spread across the modules that call it rather
  than collected anywhere.

There is a **third** hand-written client nobody has been counting: `ago-chat`'s own C# client for
`ago-calendar` - `HttpModuleGateway` (149 lines) and `HttpModuleRegistrationGateway` (231 lines) in
`Ago.Chat.Infrastructure.Modules`. It crosses the independently-versioned repository boundary
`adr/0012` created, which makes it the one hand-written client where drift is a deployment-ordering
problem rather than a rebuild.

## 1. The cost of adding it

### 1a. Which package: the built-in one, and it is not close

Read directly out of the installed SDK (`dotnet --version` -> `10.0.400`,
`C:\Program Files\dotnet\templates\10.0.11\microsoft.dotnet.web.projecttemplates...nupkg`): the
official `webapi` template's OpenAPI option is

```xml
<PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="10.0.11" Condition="'$(EnableOpenAPI)' == 'True'" />
```

with `builder.Services.AddOpenApi();` and, under `app.Environment.IsDevelopment()`,
`app.MapOpenApi();`. The AOT template (`WebApiAot-CSharp`) is identical. **Neither Swashbuckle nor
NSwag appears in any .NET 10 template shipped with this SDK.**

That settles it on this project's own "do not add a NuGet package without saying what it replaces and
why hand-rolling is worse" rule: the built-in package is version-locked to the framework the hosts
already target, needs no pinning in `Directory.Packages.props` beyond one line, is first-party, and
is what a reviewer would expect to find. Swashbuckle buys a bundled Swagger UI this project has no
stated need for and takes on a community-maintained dependency on the critical path of two production
hosts. NSwag buys client *generation* - which is a real differentiator, but is a separate tool that
can consume the built-in generator's output, so it is not a reason to replace the generator.

**Two lines per host, plus one `PackageReference` per host.** That part is genuinely trivial.

### 1b. What the existing code would produce as-is: a document with no response schemas

This is the real cost, and it is structural rather than cosmetic.

| Fact | `Ago.Chat.Api` | `Ago.Calendar.Api` |
|---|---|---|
| Mapped HTTP endpoints | **185** (74 GET, 81 POST, 15 PUT, 13 DELETE, 2 PATCH) | **51** |
| Endpoint files | 59 | 10 |
| Handlers declared `Task<IResult>` | **184 of 185** | **48** |
| Handlers using typed results (`Results<Ok<T>, …>`) | **0** | **0** |
| Endpoints with a bound request-body record | 57 | not counted separately |

`Microsoft.AspNetCore.OpenApi` builds its document from ASP.NET Core's own `ApiExplorer` metadata,
and `ApiExplorer` infers a response schema from the **declared return type of the endpoint delegate**.
`Task<IResult>` declares nothing. So switching it on today would produce a document that is correct
about paths, HTTP methods, route parameters and - for those 57 endpoints - request bodies, and that
says **essentially nothing about any response body on the entire surface**.

That is the invasive part, and it is per-endpoint: 236 endpoints each need either a `.Produces<T>(…)`
chain (plus a `.ProducesProblem(…)` for the RFC 7807 failure path every handler already has via
`ToProblem`) **or** the handler's signature rewritten from `Task<IResult>` to
`Task<Results<Ok<T>, ProblemHttpResult, …>>`. The second is the better shape - it makes the compiler
check the claim rather than trusting an annotation to stay true - and it is also a change to 232
method signatures across 69 files. **Neither option is "add two lines and you have a spec."**

Mitigating facts, all real:

- The DTOs themselves are unusually OpenAPI-friendly. In `Ago.Chat.Contracts`: **0** `object`-typed
  wire properties, **0** `Dictionary<,>`, **0** polymorphic record hierarchies, and exactly **one**
  `JsonElement` property in the whole project (`MessageDto.Content`, which the type's own doc comment
  already calls "the one field on this DTO that AGO Chat has no schema for" - so describing it as a
  free-form object is *honest*, not a gap). The rest are flat positional records of `Guid`, `string`,
  `int`, `bool`, `DateTimeOffset` and `IReadOnlyList<T>`.
- `<Nullable>enable</Nullable>` is on repo-wide, so required-versus-optional comes out right with no
  attributes. The additive-only convention (`api-design.md`) has already pushed every late field to
  `T? Foo = null`, which is exactly what a generator reads as optional.
- Schema-name collisions are a non-issue: of 171 `public sealed record` wire types declared inside
  `Ago.Chat.Api` itself, only **one** short name repeats (`RequiredDocumentResponse`, twice).

Two costs that are easy to miss:

- **Security schemes are not automatic.** The hosts run two JWT bearer schemes (`JwtSchemes.Visitor`,
  `JwtSchemes.Operator`) and three named policies (86 endpoints `RequireOperatorIdentity`, 22
  `RequirePlatformOwner`, 5 `RequireKeycloakIdentity`). The built-in generator does not emit
  `securitySchemes` from that on its own - a document transformer has to declare them and map
  endpoints to them, by hand, once.
- **`<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` is set repo-wide.** Any analyser warning
  the OpenAPI/minimal-API tooling emits becomes a build break rather than noise. This is not a
  reason not to do it; it is a reason the first PR will be larger than expected.

### 1c. The one thing worth doing before deciding, and it is cheap

Nobody in this project has ever actually looked at the document these hosts would produce. Adding
the package to `Ago.Chat.Api` on a throwaway branch, running the host, fetching `/openapi/v1.json`
and reading it would take well under an hour and would replace the paragraph above with the real
artefact. **This item deliberately did not do it** (its own Out-of-scope forbids implementation), but
if the answer is going to be "maybe", that spike is the next step, not a design discussion.

## 2. What OpenAPI can and cannot describe here - and this is the decisive section

OpenAPI describes HTTP request/response contracts. It does not describe a SignalR hub: not the
methods a client invokes, not their argument lists, not the events the server pushes, not the payload
of those events. There is no standard for that, and no generator produces a client for it.

Now the measurement that matters:

**What runs over the hub** (`HubContractManifest.cs`, `ago-chat`'s own checked-in list - 19 invokable
methods, 7 on `VisitorHub` and 12 on `OperatorHub`):

```
VisitorHub:  Join, JoinWithTrafficSource, SendMessage, SendStructuredMessage,
             SendMessageWithAutoGreeting, GetHistory, AcknowledgeDelivered
OperatorHub: JoinConversation, SendMessage, SendStructuredMessage, GetHistory,
             GetVisitorPresence, GetVisitorHistoryConversation, SetAway, GetMyPresence,
             SendTeamMessage, GetTeamHistory, GetTeamDelta, RemoveTeamMessage
```

plus 8 distinct server-to-client events the two clients subscribe to (`MessageReceived`,
`ConversationAssigned`, `MessageDelivered`, `TeamMessageReceived`, `TeamMessageRemoved`,
`AttachmentUploadGrantChanged`, `PendingBookingsChanged`, `Reconnect`).

**There is no REST route anywhere in `Ago.Chat.Api` that sends a message or returns a page of
history.** Grepped: the 185 routes cluster as `/sites` (56), `/conversations` (41), `/owner` (22) and
a long tail - configuration, analytics, billing, channel setup, owner administration. The
conversation *itself* - join, history, send, receive, delivery acknowledgement, presence, team chat -
is 100% hub.

And the sharpest number in this whole document: **`ago-widget` calls exactly six REST endpoints**
(`POST /visitor-sessions`, `POST /visitor-sessions/renew`, `POST /widget-activity`, and three
attachment routes). Everything else the widget does, it does over the hub. The product's primary
surface would get essentially nothing from a generated REST client.

So, stated plainly:

- **OpenAPI could cover 236 of 236 REST operations** - every route in both hosts.
- **OpenAPI could cover 0 of 19 hub methods and 0 of 8 push events.**
- By *endpoint count*, OpenAPI covers almost everything. By *what the product actually is*, it covers
  the administrative and configuration surface and none of the conversation.

The hub half already has an answer, built and shipped, and it is not OpenAPI: `HubContractManifest`
+ `HubContractTests` (Cecil over every `Hub` subclass, compared against a checked-in list of method
arities and *who already calls each one*), written in `5-19` after the outage described below. That
is the "hand-maintained definition of the hub contract" a mobile client would also need - and it
already exists, in C#, in this repository, with the caller list attached.

## 3. The cost of not having it - this project's own history, counted

Searched the full `docs/backlog/` tree and the git logs of `ago-chat`, `ago-console` and `ago-widget`
for cases where a hand-written client type disagreed with what the server actually sent or expected.
**Six real cases.** Here is every one, classified by whether an OpenAPI-generated client would have
caught it:

| # | Item | What broke | Would OpenAPI + codegen have caught it? |
|---|---|---|---|
| 1 | `25-11` | `23-103` replaced `OwnerSiteModuleDto.IsActive: bool` with `Status: string`. `ago-console` kept declaring `isActive`, read `undefined`, and `formatModuleStatus(undefined)` rendered **every module as "Expired"**, active or not. Found live on `ago-demo` by the author, who then tried to grant a duplicate and got a correct `409` from a backend that had been right the whole time. | **YES.** REST response DTO, field removed server-side. A regenerated client drops `isActive`, and the console stops compiling. The item's own words: *"Nothing caught it. TypeScript checks the declared type against itself, not against what the server actually sends."* |
| 2 | `5-19` | `14-06` grew `SendMessageAsync` from 4 parameters to 7 on both hubs. SignalR binds positionally and requires exactly one argument per declared parameter, so **every already-embedded widget's sends failed** from the moment the API rolled out, with no server-side log line at all. The core interaction of the entire product, on every customer site. | **NO.** Hub method arity. Outside OpenAPI entirely. Fixed by the hand-written `HubContractManifest`. |
| 3 | `25-31` | The widget passed a raw JS object as `content` to `SendStructuredMessageAsync`, whose parameter is `string?`. SignalR's argument binding rejected it before the hub method ever ran. **Every structured reply the widget could send had never worked** - the whole calendar booking flow. Found live on `golyakov.net`. | **NO.** Hub method argument *type*. The item's own lesson: *"only a live click-through, or a fake that actually round-trips through JSON, would have."* |
| 4 | `5-11` | Fan-out DTOs were pre-serialized with default `JsonSerializer` options (PascalCase) while the hub protocol uses camelCase, so **every field arrived `undefined`** client-side. Fixed with `Ago.Chat.Contracts.WireJsonOptions`. | **NO.** A serialization-policy bug on the SignalR fan-out path. An OpenAPI document describes the REST serializer's output, not this one. |
| 5 | `25-62` | The widget's contact-capture form sent `Kind: "Other"` after the server renamed that member to `"Name"`. | **NO** - and this is the instructive one. `RecordContactDetailRequest(string? Kind, string? Value)`: the wire type is `string`, parsed inside the handler. A generated client would have produced `String`, exactly as permissive as what was there. See §1d below. |
| 6 | `23-41`/`23-31` | Two products answer `/api/v1/me/tenancies` with different shapes (`{siteId,siteName}` vs `{tenantId,tenantName}`); a ux-gate stub matched on pathname alone, the calendar's reader got the chat's body, `tenantName.trim()` threw, and **the entire console rendered an empty `<body>`**. | **PARTLY.** The *collision* is a routing design question OpenAPI does not solve. But a published document for each product would have made the two shapes' incompatibility visible as a fact rather than as a blank page. |

**One in six.** That is the honest number, and the author should weigh it as such rather than as a
tidy argument either way. Two further notes that go in opposite directions:

- **The one that would have been caught was the most embarrassing kind**: silent, live, in front of
  the author, with the display lying about a backend that was correct. It also cost a wrong
  conclusion ("this tenant's calendar grants are expired") before it cost a fix.
- **The four that would not have been caught were the expensive ones.** `5-19` and `25-31` each took
  down a core product interaction for every user, live, with no server-side signal. Both are hub
  argument bugs. An OpenAPI programme would have bought nothing against either, and `5-19`'s own
  fix - a checked-in manifest with a Cecil guard - is the thing that actually closed that class.

Two smaller drifts were found and deliberately **not** counted above, because they are fixture
maintenance rather than contract drift: `fix(23-60)` (ux-gate contacts fixture behind the `Contact`
interface) and `fix(25-170)` (ux-gate fixtures catching up to a deliberate seat wire change). Both
are the *fixture* drifting from the hand-written interface, not the interface drifting from the
server. A generated client does not help; typed stubs would.

### 1d. Why a generated client would be *less* precise than what exists today, in one specific way

`Ago.Chat.Contracts.csproj` is, in full, `<Project Sdk="Microsoft.NET.Sdk"></Project>` - it
references **nothing**, by design. So no domain enum can cross the wire as an enum. Counted across
`Ago.Chat.Contracts` and `Ago.Chat.Api`: **41 stringly-typed enum-like wire fields** (10 `Kind`, 8
`Status`, 8 `Reason`, 3 `State`, 3 `AuthorKind`, 2 `Tier`, 2 `Source`, and one each of `Role`,
`Outcome`, `Mode`, `Channel`, `Assessment` - a 42nd match was `AgoClaimTypes.Kind`, a claim-type
constant rather than a wire field, and is excluded).

A generated client would type every one of those as a bare `string`. The hand-written console types
them as unions - `state: "Waiting" | "Assigned" | "Closed"`, `authorKind: "Visitor" | "Operator" |
"System"` - which is strictly more information than the server's own signature carries, obtained by
a human reading the domain. **Replacing the hand-written types with generated ones would lose that**,
unless each of the 41 gets a hand-written enum schema annotation, which is its own maintenance
surface.

(Incidentally, this search turned up a live, currently-shipping instance: `ago-widget` types
`authorKind` as `"Visitor" | "Operator" | "System" | "AutoGreeting"`; `ago-console` types the same
field without `"AutoGreeting"`. Benign today - the console falls through to its unrecognised-kind
path - but it is drift, it exists right now, and a generated client would have "fixed" it by making
both `string`, which is not an improvement.)

## 4. What it would unlock, and what it would not

- **A generated Android/iOS client, for the REST half only.** Real, and worth something: the owner
  and administration screens, analytics, channel configuration, billing. Worth *less* than it sounds
  for an operator app, because the operator's actual working screen - the conversation - is hub-only
  (§2).
- **Contract validation in CI.** This is the strongest unstated benefit, and it does not require a
  generated client at all. With the document emitted as a build artefact, a CI step can diff it
  against the committed copy and fail a PR that changes a response shape without saying so. That is
  the same mechanism `HubContractManifest` already applies to the hub - *"editing a number here is
  the moment a reviewer gets to ask 'which deployed client did you just break?'"* - extended to the
  236 REST endpoints that currently have no such guard at all. `25-11` is precisely the PR that
  mechanism would have stopped. Note that this only works if §1b is done properly; a document with
  no response schemas has nothing to diff.
- **A browsable API reference: no real demand exists, and that was already decided.** The one
  backlog item that ever wanted one, `20-19` ("A third-party integrator can actually use Calendar's
  public booking API"), records exactly this gap - *"No public API documentation exists for this
  endpoint at all - not a README, not an OpenAPI spec, not a worked example"* - and its status is
  **won't build (2026-09-01)**: the author reconsidered the premise the same day and could not
  construct a real case for a tenant integrating directly rather than through the widget. There are
  no third-party integrators. If one ever appears, `20-19` is the file to reopen, and this would be
  part of its answer.
- **What it would not unlock**: anything about the conversation. See §2.

## 5. Does this change `adr/0178`?

**No - its conclusion stands, and one sentence in it should be tightened.**

`adr/0178` (Context, first fact) says: *"the cheapest and most commonly proposed shared layer -
generated API models and a generated client - is not an option that exists today."* That is accurate.
Its Alternatives section adds: *"A generated API client shared between the two apps, from an OpenAPI
spec. There is no spec, and producing one is a change to three .NET hosts that this stage may not
make."* Two corrections of fact, neither of which changes the outcome:

- It is **two** hosts, not three (§0).
- Producing a *useful* spec is not merely "adding OpenAPI to the hosts" - it is annotating or
  retyping 236 endpoint handlers (§1b). The ADR's judgement that this option *"sounds free"* and is
  in fact *"the most expensive of the three, because it starts with backend work"* is therefore
  **understated, not overstated**.

The load-bearing reasoning is untouched. §4 of the ADR defers the iOS sharing question on the fact
that Microsoft's SignalR client is JVM-only and that the realtime layer *"is precisely the piece a
shared layer would be most valuable for - and it is also the piece whose dependency cannot be
shared."* Everything in §2 above reinforces that: OpenAPI covers none of the hub, and the hub is
where the operator app lives. An OpenAPI document would make `:core:network`'s *REST* half cheaper
to write; it would not move `ago-mobile-common`'s cost-benefit, because the expensive, duplication-
prone half is the half OpenAPI cannot describe.

**No revision of `adr/0178` is required.** Both factual corrections named above are already folded
into `adr/0178`'s own text as merged - this analysis found them while `0178` was still an unmerged
draft, and the managing session applied them before landing it rather than merging a known-wrong
number and superseding it later.

## 6. The trade-off, stated once, without a recommendation

**If it is done**, the honest price is: one `PackageReference` and two lines per host (trivial), plus
a per-endpoint pass over 236 handlers in 69 files to make responses describable (not trivial, highly
mechanical, splittable by endpoint file), plus a hand-written security-scheme transformer, plus - if
the enum precision the TypeScript clients currently have is to be kept - 42 schema annotations. What
is bought: a CI gate that would have caught 1 of this project's 6 real contract failures, a generated
REST client for a future mobile app covering the administrative surface but not the conversation, and
a public reference for integrators who do not exist. Expect the enum precision the TypeScript clients
have today to be *lost* rather than gained, unless 41 annotations are written to keep it.

**If it is not done**, the price is: the status quo, which has produced one live contract-drift
incident (`25-11`) in the project's history, caught by the author's own eyes on the demo
environment; three hand-written clients (two TypeScript, one C#) staying hand-written; and no
mechanical guard on 236 REST endpoints, against which the hub - the half that has actually caused
outages - already has one.

**The third option nobody has costed**, and the one this analysis kept pointing at: apply `5-19`'s
own answer to the REST half. A checked-in manifest of route + response-shape, guarded by a test, is
narrower than OpenAPI, needs no package, describes exactly the thing that broke in `25-11`, and is
this codebase's own established idiom for the identical problem. It buys no generated client and no
browsable reference. If the author's real concern is `25-11` happening again rather than a mobile
client or an integrator, that is the cheaper instrument and it should be a separate item.

## Done when

- [x] The real cost of adding OpenAPI is stated with actual package/host/effort specifics, not a
      general impression. (§1: `Microsoft.AspNetCore.OpenApi` 10.0.11, two hosts, 236 endpoints,
      184+48 untyped handlers, 0 existing annotations.)
- [x] The real cost of not having it is stated from this project's own actual history, not a
      generic argument for API contracts. (§3: six real cases found and classified; one of the six
      would have been caught.)
- [x] What OpenAPI can and cannot describe about this specific API (the SignalR half especially)
      is stated plainly. (§2: 236 of 236 REST operations, 0 of 19 hub methods, 0 of 8 push events;
      no REST route serves a message or a history page; the widget touches six REST endpoints.)
- [x] `adr/0178`'s own reasoning is either confirmed unaffected or flagged for revision, explicitly.
      (§5: conclusion unaffected; two factual corrections named, best folded in before it merges.)
- [ ] The author has an answer to the question they actually asked, and can decide from it -
      status moves to `ready`/`done`/`not planned` once they do, with the decision recorded here.
