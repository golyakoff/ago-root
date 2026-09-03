# the module channel is published to the internet and does not need to be

- **Stage**: 22
- **Status**: in review (2026-09-04), `ago-deploy#140`
- **Found**: 2026-09-04, weighing whether `22-11` was safe to deploy.

## The finding

`ago-calendar-api` has a ClusterIP Service. Chat and the module products run **in the same cluster**,
so a chat-to-module call can go to `http://ago-calendar-api/` and never leave the pod network. Today
it goes to `https://calendar-api.reserve-me.ru/` — out through the Gateway, across the public
internet, and back in.

And the decision is **still free**: `enabled_modules` holds zero rows on the live node, so no
`EntryPoint` has been chosen in production yet. Nothing has to be migrated; it has to be decided
before the first row is written.

## Why it mattered now rather than as tidiness

`22-11` added `/api/v1/module-registrations/{siteId}` — `PUT`, `POST …/rotate`, `DELETE`, `GET` —
authenticated by a **deployment-wide** provisioning secret, on routes that are `AllowAnonymous()`.
`adr/0095` states the blast radius plainly: a holder of that secret can register, rotate or delete the
registration for **any** site the deployment serves. Not forge one call — rewrite who the legitimate
credential-holder is.

There is no IP allowlist, no audit log, no rate limiting and no alerting on those routes. On a
publicly reachable host, one shared string was the whole defence.

**Making the channel internal removes the exposure rather than mitigating it.** A secret only
reachable from inside the cluster is a different risk from one reachable from anywhere, and this costs
a URL rather than a mechanism.

## What had to be worked out rather than assumed

- **The public hostname still serves the console API.** `calendar-api.reserve-me.ru` is a real, needed
  surface, so this was never "drop the route". Gateway API has no negative matcher, so exclusion means
  **enumerating what stays** — and that is the risk in the change: a prefix omitted stops being
  served, and the failure looks like a broken screen rather than a routing change.
- **TLS inside the cluster.** The public path terminates TLS at the Gateway. An in-cluster call over
  plain HTTP carries the provisioning secret and the per-call credential in clear text across the pod
  network, and **no NetworkPolicy restricts which pods may reach `ago-calendar-api`**. Both are
  smaller exposures than the public internet and neither is nothing.
- **`smoke.sh` asserted the public 401** (`22-02`). That check had to invert rather than be deleted:
  from outside the prefixes must now be *absent*, and the 401 moves in-cluster. Both halves are
  needed — absent-outside alone would also pass against an API that had stopped serving the channel
  entirely.

## Done when

- [x] A chat-to-module call reaches the module without leaving the cluster, proven by the absence of
      the public route. — verified reversibly against the live cluster before the change was proposed:
      applied, probed every path, restored `main`'s version. The cluster ended where it started.
- [x] The module and module-registration routes answer nothing from outside, proven by trying from
      outside. — both 404 with the new route; `module-tasks` returned to 401 after the revert.
- [x] `smoke.sh` asserts both halves — refused inside without a credential, absent outside.
- [ ] Whatever was decided about in-cluster TLS is written down. — **not decided.** Named in the
      change and here rather than inherited silently; it belongs with whoever issues the provisioning
      secret, which is the next step and is gated on this.

## What the change does not do

`EnableModuleForSite` takes the entry point from its caller, so nothing forces the in-cluster URL. The
first row written must use `http://ago-calendar-api`, not the public host. That is data, not manifest,
and there is no row yet.

## One thing found while writing its smoke check

The obvious in-cluster probe — `kubectl exec` into `ago-chat-api`, the one process that legitimately
makes this call — **does not work and fails silently**: that image is Chiseled and has no curl, so the
check compares an empty string against 401 and reports a failure about the image rather than the
channel. Replaced with the Service's ClusterIP reached from the node, which k3s programs into the
node's own iptables — verified before being relied on.
