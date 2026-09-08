# a revoked module is labelled expired, and still offers its actions

- **Stage**: 23
- **Status**: ready
- **Depends on**: `22-30`, which introduced the third state this screen does not have.
- **Found**: 2026-09-08, on the first real revoke, minutes after the first real grant.

## What the screen says

After revoking the calendar for site `01a06262`, the `/owner` module row reads:

| Module | Granted by | Expires | Status | Quantity |
|---|---|---|---|---|
| calendar | Platform owner | No end date | **Expired** | Not granted |

with **Set quantity** and **Revoke** still offered on the row.

**The data is correct.** `enabled_modules.revoked_at` is stamped, `expires_at` is null, and the
calendar's `chat_module_registrations` is empty — the revoke did exactly what it should on both sides.

**The label is not.** The module was revoked, not expired. Nothing expired; there was no end date.

## Why it happened, and it is a consequence of a change that was right

```ts
export function formatModuleStatus(isActive: boolean): string {
  return isActive ? "Active" : "Expired";
}
```

**The console has two states where the domain now has three.** Before `22-30`, revoking *deleted* the
row, so a row that existed and was not active could only be one that had expired — and the two-way
mapping was true. `22-30` made revoke a tombstone, deliberately and correctly, because the row is
chat's only record that a site ever had the module and a later erasure needs it (`adr/0155`).

Nothing on the read side followed. And it could not have been fixed in the console alone:
`OwnerSiteModule` carries `isActive: boolean` and nothing else, so the browser has no way to know
*why* a module is inactive.

**This is the merger's miss rather than the item's.** `22-30`'s own reasoning states that the tombstone
is invisible to every caller except the one that needs the history — but `GetAllForSiteAsync`, built
unfiltered for `23-14`'s support diagnostics, is exactly the read this screen uses. It was named in
that item's own summary and not carried through to the screen.

## The second half: the actions

A revoked row still offers **Revoke** and **Set quantity**. Both are wrong in different ways:

- Revoking a revoked module is either a no-op that reports success — the worst outcome, because it
  teaches the operator that the button does nothing meaningful — or an error for a state the screen
  itself presented as actionable.
- Setting a quantity on a revoked module writes a grant nobody can use, and `worker_quota` is precisely
  the number a tenant needs *after* a grant.

## Scope

- **The contract carries why a module is inactive**, not merely that it is. Expired and revoked are
  different facts and one boolean cannot hold both.
- **The status reads what actually happened**, and the row says when: a revoke has a timestamp, and a
  row that stops being active for no visible reason invites exactly this bug again.
- **Actions match the state.** A revoked module is not revocable and its quantity is not settable.
- **Re-granting is the case to get right**, because it is the next thing anybody does: `adr/0155`
  already records that a revoke-then-re-grant leaves two rows. This screen will show both, and what it
  should show is a decision — one live row with history behind it, or two rows honestly.

## Where this is likely to go wrong

- **Do not fix it by hiding revoked rows.** The list's own caption promises *"every module this tenant
  has ever had enabled, including any that have since expired"* — hiding is how the tombstone becomes
  invisible again, which is the state `22-30` deliberately left behind.
- **`formatModuleStatus(false)` has a test asserting `"Expired"`.** That test is now asserting the bug;
  changing it is part of the fix, not collateral.
- **Three states may be four.** A grant can expire *and* be revoked. Decide which is shown rather than
  discovering the precedence from whichever branch is written first.

## Done when

- [ ] A revoked module says revoked, and an expired one says expired.
- [ ] A revoked module offers no action that cannot work.
- [ ] What the screen shows after a revoke-then-re-grant is decided and demonstrated.
