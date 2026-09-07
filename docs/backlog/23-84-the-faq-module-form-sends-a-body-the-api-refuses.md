# the FAQ module form sends a body the API refuses

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-83` is the neighbouring cause.
- **Found**: 2026-09-07, while building `23-65`, by reading rather than by anybody reporting it.

## What is wrong

`ago-console`'s `FaqModulePage`/`modulesApi.ts` posts to the tenant's own module route without
`credential` and without `provisioningSecret`. **The API requires both.**

So the screen almost certainly does not work and has not worked. Nobody has reported it, which is its own
piece of information: either nobody has used it, or whoever did assumed they had done something wrong.

## Why this is worth its own number rather than a line in `23-83`

`23-83` removes the secret from the route. That fixes half of this by accident — and leaves
`credential`, which is a real field the caller must supply and which the form still omits. **A fix that
happens as a side effect of another item is a fix nobody tested**, and this is exactly the shape that
produces "we thought that was covered".

It is also a different promise: `23-83` is about who holds a secret; this is about a screen that does
not do what it appears to do.

## Scope

- Establish what the route actually requires **after** `23-83`, and make the form send it.
- **Show the screen working end to end**, over real HTTP, rather than asserting the request shape. A
  form whose body matches a record definition can still be refused for a reason nothing in the console
  can see.
- **Say plainly, in the item's Outcome, whether this ever worked.** If it did not, that is worth knowing
  when somebody asks how long FAQ self-service has been available.

## Where this is likely to go wrong

- **The console cannot supply a deployment-wide secret**, and should not learn how. If the route still
  needs one after `23-83`, the answer is that the screen cannot exist in this shape — not that the
  console acquires a secret.
- **A tenant-facing failure that nobody reported is a signal about the feature, not only the bug.** Ask
  whether FAQ self-service is wanted before making it work; the queue is not obliged to fix what nobody
  is asking for.

## Done when

- [ ] The FAQ module form's request is accepted by the API, shown over real HTTP.
- [ ] Whether it ever worked is established and written down.
- [ ] The console holds no deployment-wide secret, whatever the answer turns out to be.
