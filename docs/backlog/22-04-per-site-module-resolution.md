# Per-site module resolution replaces the pinned deployment key

- **Stage**: 22
- **Status**: done (2026-09-03) — `ago-faq#2`, `ago-calendar#30`, `ago-chat#155`
- **Depends on**: `22-02` (hard — see Why the order matters), `22-03`

## The gap, in the code's own words

`ChatModuleTaskOptions`: *"every chat-originated task in this deployment is answered by exactly one
tenant's one calendar, named here."* The tenant comes from `ChatModule:TenantPublicKey`, a deployment
setting, and the same file names `adr/0065`'s per-site module registry — *"one row saying site X has
module K enabled"* — as explicitly out of scope for the item that built it.

**One deployment therefore serves exactly one calendar tenant.** That is the hard blocker on selling
the add-on at all, and no amount of billing work goes around it.

## Why the order matters

`22-02` is not a nicety before this. Today the pinned key is what stops an anonymous caller choosing a
tenant; per-site resolution replaces that pin with a value from the request. **Shipping this before the
channel is authenticated hands tenant selection to the internet.**

## What this must produce

- A chat site resolves to its own module instance through the registry `adr/0065` describes, keyed by
  the account id.
- `ChatModule:TenantPublicKey` is gone, not merely unused — a setting that still works is a setting
  somebody will configure.
- The resolution path is the module contract's, so `ago-faq` and `ago-calendar` resolve the same way.
  `ago-faq` already scopes by `SiteId`, so it is the cheaper of the two to move and the better one to
  move first.

## Done when

- [x] Two sites with the module enabled reach two different tenants — proven with two, not reasoned
      about with one. — asserted in both products, each site's response carrying its own tenant's
      seeded data rather than the other's. **With one honesty note the worker volunteered**: this
      case has no fails-before mutation of its own, riding instead on the per-site lookup checks that
      do. Reported as not done rather than implied.
- [x] A site without the module enabled is refused rather than falling back to anyone's tenant. —
      refused at the credential layer, before any tenant lookup runs.
- [x] The deployment setting is removed from the manifests and from the options class. — the classes
      are **deleted**, not left unused: `ChatModuleTaskOptions` and `ModuleCallCredentialOptions` both
      show as `D`, and no `ChatModule:` key survives in either product. Verified independently rather
      than taken from the report. The manifests needed no change at all — they never carried the
      setting, which is why the live calendar had been answering `not_configured` since it was
      deployed.

## Outcome

Merged 2026-09-03 across three repositories.

**It closed both limits `adr/0094` recorded against itself.** The secret is per site rather than per
deployment, and the Start/Reply asymmetry is gone — `ReplyToModuleTask` now cross-checks the
credential's site against the task's own tenant, which `ChatBookingTask` carrying no site id had made
impossible.

**The claimed-versus-proved boundary is one line**, and worth knowing where: the validator decodes the
payload and reads its site id while it is still attacker-controlled, using it for nothing but choosing
which row to look up. It becomes trusted only by surviving `FixedTimeEquals` against *that row's own*
credential — so a token signed with one tenant's real key while claiming another is refused, proven
failing before the check existed.

**And the order was load-bearing.** Until `22-02` the site arrived unproved in the request body;
per-site resolution shipped first would have handed tenant selection to the internet. The stage put
these two in this sequence for that reason rather than for convenience.

### What it revealed, carried out as its own numbers

- `22-11` — **a module registration has no lifecycle.** Nothing outside a test writes one, and the
  repository has add and read only, so a leaked credential cannot be rotated and a site's access
  cannot be revoked. The worker called this *"the load-bearing gap in this report, not a footnote"*
  and was right.
- `22-12` — the refusal does not say which refusal it is: "module not enabled" and "credential is
  wrong" are both a flat `401`.

Also found the same day, by CI rather than by the change: `17-09`, `RabbitMqConnection.DisposeAsync`
throwing on a slow broker and leaking its lock when it does. A doc-only pull request surfaced it, and
rerunning turned the build green while leaving the finding true — which is exactly why it got a number
rather than a rerun.
