# Authenticate the chat → module channel

- **Stage**: 22
- **Status**: ready
- **Found**: 2026-09-03. Probed from outside the cluster while measuring the consolidation.

## The gap, and it is live

`/api/v1/module-tasks` is `AllowAnonymous()` in **both** module products:

- `ago-calendar` — `ChatModuleTaskEndpoints`
- `ago-faq` — `ModuleTaskEndpoints`

Each takes `SiteId` **from the request body**. The site's identity is asserted by the caller, not
proved. Verified against the live deployment: an unauthenticated POST from outside reaches the
handler (`500 chat_module_task.not_configured`), while a nonsense sibling path returns `404` — so the
route is genuinely live and genuinely anonymous, not merely mapped.

**What saves it today is an accident.** `StartModuleTaskHandler` resolves the tenant from
`ChatModule:TenantPublicKey`, a deployment setting, so an anonymous caller cannot choose *which*
tenant to act on. The moment `22-04` makes resolution per-site, that protection disappears and the
body becomes the tenant selector.

So this is both a present-tense exposure and a hard prerequisite: every item below hands this channel
more authority.

## What this must produce

- A module call proves which site it is for. Whatever the mechanism — a credential issued when the
  module is enabled, a signed assertion, mTLS — the site id stops being self-declared.
- **Chat stays product-agnostic.** It already registers modules generically (`EnabledModule`:
  `ModuleKey`, `TriggerWords`, `EntryPoint`); the credential belongs in that same registry, not in
  anything that names a product.
- The same mechanism serves both existing module products. Two implementations of one contract is the
  outcome to avoid — `adr/0065`'s module contract is the place it goes.
- Rejection is distinguishable from absence: an unauthenticated call gets 401, an unknown route 404,
  so a future check can tell them apart (the lesson `20-24`'s smoke work already recorded).

## Done when

- [ ] An unauthenticated `POST /api/v1/module-tasks` is refused on both products, with a control
      proving the route exists.
- [ ] A call carrying one site's credential cannot act for another site — proven by trying it.
- [ ] `smoke.sh` asserts the refusal, so it cannot silently regress.
- [ ] No shared code between the two products beyond the contract itself.
