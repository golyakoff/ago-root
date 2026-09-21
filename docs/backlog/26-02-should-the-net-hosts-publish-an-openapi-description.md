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

## Done when

- [ ] The real cost of adding OpenAPI is stated with actual package/host/effort specifics, not a
      general impression.
- [ ] The real cost of not having it is stated from this project's own actual history, not a
      generic argument for API contracts.
- [ ] What OpenAPI can and cannot describe about this specific API (the SignalR half especially)
      is stated plainly.
- [ ] `adr/0178`'s own reasoning is either confirmed unaffected or flagged for revision, explicitly.
- [ ] The author has an answer to the question they actually asked, and can decide from it -
      status moves to `ready`/`done`/`not planned` once they do, with the decision recorded here.
