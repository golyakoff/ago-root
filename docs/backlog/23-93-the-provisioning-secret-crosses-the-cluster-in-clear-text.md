# the provisioning secret crosses the cluster in clear text

- **Stage**: 23
- **Status**: ready — **and the first question in it is whether this is acceptable, not how to fix it**
- **Depends on**: `23-87` configured the secret; `23-92` establishes the address that makes it travel.
- **Found**: 2026-09-07, while establishing what a module entry point should contain.

## What is true

`Ago.Chat.Api` proves a provisioning call with `adr/0095`'s **deployment-wide** secret, sent as the
`X-Ago-Module-Provisioning-Secret` header. With the entry point `23-92` establishes as the working one —
`http://ago-calendar-api` — that header crosses the cluster **unencrypted**.

`adr/0095` states the blast radius plainly: a holder can register, rotate or delete the module registration
for **any site the deployment serves**, and since `adr/0098` can also bring a new tenant row into
existence. That is the value on the wire.

## Why this is a question and not obviously a defect

Three readings, and this item should not pretend the first is settled:

- **It is acceptable.** The traffic is pod-to-pod on one node and never leaves the host, and reading it
  needs a position from which far worse is already possible. `adr/0026` sized this deployment as one node
  deliberately; treating in-cluster traffic as trusted is an ordinary posture, not a lapse.
- **It is not, because `22-24` already decided otherwise.** That item built an internal CA precisely so
  in-cluster legs would not be clear text. If that reasoning held for the gateway-to-backend leg, it is
  hard to argue it stops at a leg carrying a strictly more powerful secret. And the gap is small:
  `ago-calendar-api` **already serves 8443**; what is missing is `ago-chat-api` trusting the CA, which is a
  volume mount and a trust-store step.
- **The secret is the wrong shape either way.** A bearer string replayable by anyone who sees it is the
  weakest of the available designs, and `adr/0094` already uses a per-call credential elsewhere in this
  same handshake. Whether the bootstrap anchor could be signed rather than presented is a bigger question
  and probably its own number.

## Scope

- **Answer the first question explicitly**, in an ADR or an amendment to `adr/0095`, whichever fits.
  `adr/0095`'s blast-radius section does not mention transport at all, and that silence currently reads as
  *considered and accepted* when it is *not considered*. Closing that gap is the deliverable even if the
  answer is that nothing changes.
- If the answer is that it should be encrypted: mount `22-24`'s CA into `Ago.Chat.Api`, prove the leg, and
  `23-92`'s documented value changes with it.

## Where this is likely to go wrong

- **Do not fix it silently by switching the entry point to https.** That fails closed on a certificate
  error and looks like a broken calendar — exactly the failure `23-92` exists to stop. Mount the CA first,
  prove the leg, then change the documented value.
- **NetworkPolicies are not a substitute**, and if they are offered as one, this item should name the
  policy that actually restricts who may reach `ago-calendar-api` on port 80. At the time of writing,
  `network-policies.yaml` names ingress allowances for Postgres, Redis, RabbitMQ, MinIO and the static
  sites, and the calendar API is not among them.

## Done when

- [ ] Whether clear text is acceptable here is decided, and written where `adr/0095`'s blast radius is read.
- [ ] If it is not, the leg is encrypted and proven, and `23-92`'s documented entry point follows it.
- [ ] Either way, `adr/0095` no longer implies transport was considered when it was not.
