# Per-site module resolution replaces the pinned deployment key

- **Stage**: 22
- **Status**: ready
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

- [ ] Two sites with the module enabled reach two different tenants — proven with two, not reasoned
      about with one.
- [ ] A site without the module enabled is refused rather than falling back to anyone's tenant.
- [ ] The deployment setting is removed from the manifests and from the options class.
