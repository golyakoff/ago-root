# a tenant operator still holds a secret the platform owner no longer needs

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-65`, which removed the secret from the owner's own routes. This is the other half.
- **Found**: 2026-09-07, while building `23-65`.

## What is now inconsistent

`adr/0150` took the deployment-wide provisioning secret out of the **platform owner's** request body and
put it in `Ago.Chat.Api`'s configuration. The reasoning was that the owner can read that secret from the
cluster anyway, so making them paste it is a second inconvenience rather than a second lock.

**`Ago.Chat.Api/Modules/ModuleEndpoints.cs` still takes it from a request body** — on the tenant's own
self-service routes: enable, rotate, revoke, set entry point. Those are called by an ordinary tenant
operator holding `site:configure`.

So after `23-65` the position is upside down: **the least trusted caller in this system is the one
still required to hold the strongest secret it has.** A platform owner, who could read it from the
cluster, no longer needs it; a shop's administrator, who could not, does.

## Why it is a real problem and not only untidy

That secret is deployment-wide. Whoever holds it can register, rotate or delete the module registration
for **any site that deployment serves** — `module-grant-and-revoke.md` says so in as many words. Asking a
tenant to hold it means either they never can (and the self-service path is dead) or they somehow can
(and a tenant holds a key to every other tenant's modules).

Both readings are bad, and the second is the one worth checking: **find out whether any tenant-facing
surface has ever supplied this value**, because if one does, that is not a design question.

## Scope

- The self-service routes obtain the secret the same way the owner routes now do — from configuration,
  never from the caller.
- **Authorisation stays where it is.** The tenant is still gated on their own permission for their own
  site; the secret was never the authorisation, which is exactly why removing it changes nothing about
  who may call.
- **Check the callers.** `23-84` is one broken caller found the same day; there may be others, and a
  route whose required field nobody sends is a route nobody has exercised.

## Where this is likely to go wrong

- **Removing a required field from a request is a wire change.** Anything already sending it must not
  break; ignoring an unexpected field is kinder than refusing it, and `23-65`'s own test already proves
  a smuggled value is ignored rather than honoured.
- If it turns out **no tenant ever could call these routes**, then the honest finding is that
  self-service module provisioning has never worked, and this item should say so rather than quietly
  making it work for the first time and calling it a fix.

## Done when

- [ ] No tenant-facing route accepts a provisioning secret from its caller.
- [ ] A value smuggled into the body is ignored, not honoured, asserted by a test over the wire.
- [ ] Whether these routes have ever been usable by a tenant is established and written down.
