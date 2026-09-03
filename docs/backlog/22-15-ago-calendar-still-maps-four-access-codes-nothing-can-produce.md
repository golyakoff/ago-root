# ago-calendar still maps four `access.*` error codes nothing can produce

- **Stage**: 22
- **Status**: ready
- **Found**: 2026-09-04, checking `22-06`'s API calls against what `22-05` left standing.

## The gap

`ago-calendar`'s `ErrorExtensions.cs` still maps `access.forbidden`, `access.not_found`,
`access.invalid` and `access.account_owner_requires_contact_access` to HTTP status codes. Their only
producer was `AccessControlErrors.cs`, which `22-05` deleted along with the rest of this product's
identity model.

## Why it is worth removing rather than leaving

Harmless today — dead branches in a switch. But **a mapping that names a code nothing produces reads
to the next person as evidence that something still produces it**, which is precisely the wrong
signal to leave beside a subsystem that was deliberately removed. Someone will eventually go looking
for the handler that raises `access.forbidden` and find nothing, and the honest reading of that is
"the mapping is stale", which is a conclusion they should not have to reach on their own.

## Done when

- [ ] No mapping in `ago-calendar` names an error code no code path can construct — checked across
      the file rather than only for these four. `22-05` deleted a great deal, and these were found by
      accident while looking at something else, so the same shape is likely elsewhere.
