# Authenticate the chat → module channel

- **Stage**: 22
- **Status**: done (2026-09-03), `adr/0094` — deployed, and the last Done-when closed with it.
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

- [x] An unauthenticated `POST /api/v1/module-tasks` is refused on both products, with a control
      proving the route exists. — refused with **401**, deliberately not 404, so a check can tell
      "protected" from "unreachable". Proven in both products' own suites.
- [x] A call carrying one site's credential cannot act for another site — proven by trying it. — and
      proven **failing before the check existed**, in both products: `200 OK` where the refusal was
      expected. This was the case the brief called easiest to leave untested.
- [x] `smoke.sh` asserts the refusal, so it cannot silently regress. — met once the images were
      deployed: the check expects **401**, not 404, so it fails both when the guard disappears and
      when the route does. Confirmed against the live deployment on 2026-09-03, anonymously, from the
      node.
- [x] No shared code between the two products beyond the contract itself. — two independent
      validators, each naming its twin in a comment. `adr/0094` records why that duplication was
      chosen over a package.

## Outcome

`adr/0094`, accepted 2026-09-03. Three repositories: `ago-chat` mints, `ago-calendar` and `ago-faq`
verify.

**What the item got wrong about itself.** It framed this as one product's problem. It is two —
`ago-faq` had the identical anonymous route, found only because the brief said to look. So this
closed an exposure in a product nobody had asked about.

**Two limits are recorded in the ADR rather than smoothed over**, because both are cheap to note now
and expensive to discover later:

- The secret is **per module deployment, not per site**. The token cannot cross sites, which is what
  the tests attack — but whoever holds the raw secret can mint one for any site that deployment
  serves. Harmless while a deployment serves exactly one tenant. **`22-04` is where that stops being
  true**, and its brief carries the requirement explicitly.
- The wire format lives in **three hand-kept copies** with no check that they agree.

**mTLS is named in the ADR as the answer a larger deployment would take and that this one deliberately
did not** — which is the point of writing an ADR rather than a comment.

### Still owed, and it is why one box above is unticked

Nothing is deployed. The shared secret has to be generated, placed in the node's environment,
referenced from the manifests, and matched by the `credential` column on each `enabled_modules`
row — **three places, one value**, recorded in `secrets.md`. A mismatch presents as `401`, naming no
secret.

Deliberately not started yet: if `22-04` gives each registry row its own secret, the deployment-wide
setting disappears, and writing it into the manifests today would be work done only to undo. The live
system makes that safe to wait on — `enabled_modules` holds **zero rows** and `ago-faq` is not
deployed at all, so nothing calls this channel today.
