# module provisioning has never been configured in any deployment

- **Stage**: 23
- **Status**: ready — **the wiring is merged and deployed; what is left is one live check**.
  `ago-deploy` `1e8d00f` set the key for both hosts and the value is generated on the node; the last
  Done-when needs the grant screen to actually answer something other than `503`, against the stand.
- **Depends on**: `adr/0095` created the secret; `adr/0150` moved it into configuration. This is the
  step neither of them took: putting a value there.
- **Found**: 2026-09-07, while trying to grant the calendar to a real account on the demo stand.

## What is actually true

`ModuleProvisioning:Secret` is read by **both** sides of the provisioning handshake:

- `Ago.Chat.Application/Abstractions/IModuleProvisioningSecretProvider` — `TryGet()` returns `null`
  when the key is unset, blank, or unparseable;
- `Ago.Calendar.Infrastructure.Postgres/ModuleProvisioningOptions` — bound in `CalendarModule`, and
  `SharedSecretModuleProvisioningAuthenticator` refuses every call while it is empty.

**`git grep ModuleProvisioning` in `ago-deploy` returns nothing.** Not in `k8s/base`, not in either
overlay, not in `.env.example`. So the key has never been set in any deployment of this system.

The consequence is exact rather than approximate: the platform owner's grant screen (`23-65`) returns
`503 Module.ProvisioningNotConfigured`, and the calendar would refuse the inbound call even if the
grant reached it. **Seventeen sites, zero rows in `enabled_modules`** — that is not a coincidence, it
is the only outcome this configuration allows.

## Why nobody noticed

Because until `23-65` there was no screen that called it, and before that the secret was a request-body
field nobody could supply (`23-83` has the full account of why: the model asked a tenant to hold a
deployment-wide key). **A capability with no caller cannot report that it is misconfigured.**

`ValidateOnStart` does not catch it either, and deliberately so — on the chat side the provider returns
`null` rather than throwing, because a deployment with no modules is a legitimate deployment. That is
the right call and it is also why this stayed invisible: the failure surfaces at the one moment
somebody tries to use it, which happened for the first time today.

## Scope

- **One value, set for both hosts.** `Ago.Chat.Api` and `Ago.Calendar.Api` read the same key and must
  see the same value — that is what makes it a shared secret rather than two unrelated settings.
- **It reaches the pods the way every other real secret does**: a key in `infra-credentials`, sourced
  from the overlay's gitignored `.env`, referenced as `$(VAR)`. Not a literal in a manifest — the
  committed `Webhooks__SecretEncryptionKey` literal is a finding in `secrets.md`, not a pattern.
- **`.env.example` gains the key with a placeholder and the generation command**, so the shape is
  documented and no value ever is.
- **The value is generated on the node** and never displayed, never pasted into a session, never
  committed. 16–256 characters (`ModuleProvisioningSecret`'s own bounds); `openssl rand -base64 32`
  gives 44 and matches what the file already tells the author to do for key-shaped values.

## Where this is likely to go wrong

- **Rotating it is a two-host operation.** Change it on one side and every provisioning call fails
  closed, with a 401 that names neither host. Worth a line in `secret-rotation.md` rather than
  discovering it during a rotation.
- **`Ago.Chat.Worker` and `Ago.Chat.Webhooks` do not need it** and should not get it. A blanket
  `envFrom` already gives them the Secret's other keys; adding this one as an explicit `env` on the
  two hosts that use it keeps the blast radius readable.
- **This makes a previously dead path live.** The same shape as `23-36`: the moment provisioning works,
  whatever it does not check becomes reachable. `23-85`'s entitlement gap is the known one.

## Done when

- [ ] `ModuleProvisioning__Secret` is set on `Ago.Chat.Api` and `Ago.Calendar.Api` from one source.
- [ ] `.env.example` documents the key and how to generate it, and holds no value.
- [ ] The platform owner's grant screen no longer returns `Module.ProvisioningNotConfigured` on the
      demo stand — checked against the stand, not against a manifest.
- [ ] What rotating this costs is written down where a rotation would be read.
