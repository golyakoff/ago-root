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

## The author's answer, 2026-09-07, which changes what this item is

*«Теннант не должен мочь что-то прям настраивать себе. Он может за что-то заплатить и у него включится,
но не сам. Его настройки ограничены видами виджета, управлением операторами, всё в своей песочнице.»*

**That resolves the contradiction by removing one side of it**, and it means the first draft of this item
was wrong. It said the self-service routes should take the secret from configuration, the way the owner
routes now do. **That would have made tenant self-service work — and tenant self-service is the thing
that should not exist.**

### Where the mistake actually was

`ModuleEndpoints.cs`'s own comment records the origin without knowing it is recording a mistake:
*"This item needed a real console screen to register the FAQ module for a site, so this is that
endpoint."* (`19-03`.)

Two incompatible ideas were welded together:

- **a tenant turns a product on for themselves** — a self-service idea, and the reason the route is
  gated on `site:configure` and lives under `/sites/{siteId}/`;
- **turning a product on means proving to the module that the platform authorised it** — an
  infrastructure idea, and the reason it needs `adr/0095`'s deployment-wide secret.

Together they require a tenant to hold a secret that works against every other tenant. The model asked
for something that cannot exist, which is why nobody could ever supply the field.

**Nobody noticed because the screen never worked.** `23-84` is the proof: the console's FAQ form does not
send the field at all, so it has always been refused. A feature that does not work produces no
complaints.

## Scope

- **Remove the tenant-facing provisioning writes.** `PUT`, `rotate`, `revoke` and `verify` under
  `/api/v1/sites/{siteId}/modules` stop existing for a tenant. Provisioning is the platform's act, and
  `23-65` already built the surface for it.
- **Keep the read.** A tenant seeing which products are on their account is ordinary and carries no
  secret. `GET` stays.
- **Say what replaces them.** Rotating a module credential and verifying a registration are real
  operations that somebody still needs — they move to the owner surface rather than disappearing.
- **The console's FAQ screen goes or becomes a read** — `23-84`, which is now about removing something
  rather than fixing it.

## What this does not decide

**How a tenant who pays gets the product turned on.** The author's model is *pay, and it turns on* —
which is a billing event granting a module, not a person clicking. Nothing does that today: `22-33`
already found that a lapsed subscription never touches modules, and this is the same seam from the other
end. It is worth its own number rather than being smuggled in here.

## Where this is likely to go wrong

- **Removing a required field from a request is a wire change.** Anything already sending it must not
  break; ignoring an unexpected field is kinder than refusing it, and `23-65`'s own test already proves
  a smuggled value is ignored rather than honoured.
- If it turns out **no tenant ever could call these routes**, then the honest finding is that
  self-service module provisioning has never worked, and this item should say so rather than quietly
  making it work for the first time and calling it a fix.

## Done when

- [ ] No tenant-facing route provisions a module at all — the writes are gone, not re-plumbed.
- [ ] A tenant can still see which products are on their account.
- [ ] Rotate and verify exist on the owner surface, so nothing that was possible becomes impossible.
- [ ] Whether these routes were ever usable by a tenant is established and written down — the answer is
      almost certainly no, and that is worth stating rather than assuming.
