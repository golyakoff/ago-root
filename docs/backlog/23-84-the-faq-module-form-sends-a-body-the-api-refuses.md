# the FAQ module form sends a body the API refuses

- **Stage**: 23
- **Status**: done
  not repairing it**
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

## The author's answer changed what this is

*«Теннант не должен мочь что-то прям настраивать себе… его настройки ограничены видами виджета,
управлением операторами, всё в своей песочнице.»*

So the FAQ module form is not a broken screen to fix. **It is a screen for a capability a tenant should
not have**, built when `19-03` assumed tenants provision their own modules (`23-83` has the full account).
That it never worked is the mildest possible version of that mistake.

Fixing it would be building the wrong thing carefully.

## Scope

- **The console stops offering a tenant a way to provision a module.** Remove the form; do not repair it.
- **A tenant still sees which products are on their account** — that is a read, it carries no secret, and
  `23-83` keeps the `GET` it needs.
- **Establish whether the form ever worked**, and write the answer down. It matters when somebody asks
  how long FAQ self-service has been available: the honest answer is likely *never*, and that is a fact
  about the product rather than a bug report.

## Why the earlier scope was wrong

The first draft of this item said to find out what the route requires and make the form send it. That was
written before the author's answer, and it would have been **building the wrong thing carefully** — a
working screen for a capability a tenant should not have.

Recorded rather than quietly replaced, because the mistake is the informative part: a defect report can
be correct about the symptom and wrong about the remedy, and the remedy is the half that costs work.

## Where this is likely to go wrong

- **The console cannot supply a deployment-wide secret**, and should not learn how. If the route still
  needs one after `23-83`, the answer is that the screen cannot exist in this shape — not that the
  console acquires a secret.
- **A tenant-facing failure that nobody reported is a signal about the feature, not only the bug.** Ask
  whether FAQ self-service is wanted before making it work; the queue is not obliged to fix what nobody
  is asking for.

## Done when

- [x] The module-registration form is gone from `FaqModulePage`; the screen has no write at all
      now, and a test asserts no submit control exists for a permitted operator - the stronger
      statement than the one it replaced.
- [x] `fetchModules` is what the panel calls now: whether the module is on this account, and its
      trigger words. A tenant seeing which products they have is ordinary and carries no secret. The
      knowledge-base panel is untouched - it is that product's own data, which `adr/0151` keeps the
      tenant's.
- [x] Established: **it never worked.** It sent `moduleKey`, `triggerWords` and `entryPoint` while
      the endpoint also required a credential and a provisioning secret, and `ModuleCredential`'s
      constructor rejects null before any module is contacted - so every submit it could make was
      refused from the day it shipped. Nobody reported it because a feature that does not work
      produces no complaints.
- [x] True by having nothing to hold: `provisioningSecret` is gone from the server's own shape, not
      merely unset in the console - `ownerApi.ts`'s remarks record the omission at each of the three
      call sites that used to carry it.
