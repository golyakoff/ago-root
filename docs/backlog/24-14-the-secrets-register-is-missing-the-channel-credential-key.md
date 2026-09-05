# the secrets inventory lists the key that protects tenants' channel credentials

- **Stage**: 24
- **Status**: ready
- **Depends on**: nothing
- **Decision**: none — `secrets.md`'s own six sweeps are the method this restores

## Goal

Re-running `secrets.md`'s own stated method finds nothing the file does not already list.

## What is actually true today, verified 2026-09-05 (`24-06`)

**`CHANNELS_CREDENTIAL_ENCRYPTION_KEY` is not in `secrets.md`.** It is consumed by all three host
manifests as `Channels__CredentialEncryptionKey: "$(CHANNELS_CREDENTIAL_ENCRYPTION_KEY)"`
(`ago-deploy/k8s/base/api.yaml:137`, `worker.yaml:89`, `webhooks.yaml:82`), documented in
`k8s/overlays/demo/.env.example`, and supplied from `infra-credentials` exactly like its neighbours.

The value is held correctly — this is an inventory omission, not a leak. What it protects is every
tenant's channel credential at rest: the bot tokens and API credentials for MAX, Telegram, VK, Avito,
WhatsApp and Email (`14-01`'s `channel_credentials`). By the rotation-cost classes `secrets.md` itself
defines, it is the same shape as `Webhooks:SecretEncryptionKey` — reversible encryption over stored
ciphertext, so changing it without re-encrypting silently destroys what it protects — and that is
exactly the kind of fact a reader consults that file to learn.

`secrets.md` states its own method: six sweeps, "anyone re-running these should find the same set".
Sweep 2 is "every `$(VAR)` substitution in `ago-deploy/k8s/`" — the sweep that found
`KEYCLOAK_DEMO_PROVISIONER_SECRET` when the file was written. Re-run today it finds one more.

## Why this is a gap rather than an oversight

`17-03` (2026-08-27) and `14-01`'s channel-credential storage landed within days of each other, and the
inventory has had no forcing function since: nothing makes adding a secret update the file the way
`personal-data.md` is named in three places that make adding a column update it. A file whose value is
completeness, with no mechanism keeping it complete, drifts on exactly this schedule.

It matters beyond tidiness because `processing-instruction-facts.md` Element 4 cites `secrets.md` as
the source for the confidentiality answer. A source with a known omission is a defective source, and
the omission is not knowable to a reader of that file.

## Scope

- Re-run all six sweeps and add whatever they find, not only this one row — a single-row fix would
  leave the file's own completeness claim untested a second time.
- The new row carries what every row carries: what it protects, where the value lives, who reads it,
  and its rotation-cost class, including the re-encryption problem if it has one.
- A forcing function, in the same spirit as `personal-data.md`'s "Keeping this true": name the file
  somewhere a change that introduces a secret has to pass through.

## Out of scope

- The open finding already recorded at the bottom of `secrets.md`. It is a separate, already-stated
  problem with its own required fix, and it is not made better or worse by this item.
- Rotating anything.

## Done when

- [ ] All six sweeps re-run, dated in the file, and every row they produce is present.
- [ ] The channel-credential key has a row with its rotation-cost class.
- [ ] Something forces the next secret into this file.

## Open questions

- **Where does the forcing function live** so it is actually read? `personal-data.md` uses two skills
  and a sibling doc; the equivalent set for a secret is not obviously the same three.
