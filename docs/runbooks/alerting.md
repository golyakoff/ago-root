# Runbook: alerting on the public demo

`15-03`. Prometheus and Grafana have existed since `7-03`; what did not exist until now is anything
that tells a person. This file is the operator's half of that: where alerts come from, where they go,
and — one section per rule — what each one means and what to look at first.

A rule whose response is unknown is noise that trains its reader to ignore the next one. That is why
every rule below has an entry here, and why adding a sixth rule without adding a sixth entry is not a
finished change.

Applies to **the demo deployment only**. The local cluster and the compose loop get no alerting on
purpose (`15-03` Out of scope) — a developer watching their own terminal is the notification channel
there. Prometheus's rule glob simply matches nothing in `overlays/local`.

## The path, end to end

```
node-exporter / rabbitmq / cert-manager / the three Ago.Chat.* hosts
        -> Prometheus  (scrape, then evaluate k8s/overlays/demo/prometheus-alert-rules.yml)
        -> Alertmanager (k8s/overlays/demo/alertmanager.yaml, group / dedupe / repeat)
        -> Postfix on the node at 10.42.0.1:25, no auth, no TLS (adr/0040's amendment)
        -> alias `alerts` in /etc/aliases
             -> /var/mail/ago      (a local copy that survives an outbound mail failure)
             -> the author's real mailbox
```

**The human mailbox address is in `/etc/aliases` on the node and in no repository.** `CLAUDE.md`
forbids putting anyone's data in these repositories, and keeping it there also means changing who gets
alerted is two commands with no Secret to regenerate and no pod to restart:

```bash
ssh ago@<node-ip>
sudo nano /etc/aliases     # the `alerts:` line
sudo newaliases
```

**There is no credential anywhere in this path.** The hop to Postfix crosses the k3s bridge on the
same machine and takes neither SMTP AUTH nor STARTTLS, exactly as Keycloak's does — so `15-03`'s
"the notification channel's credential comes from the existing Secret mechanism" is satisfied by there
being nothing to keep secret. Nothing was added to `overlays/demo/.env` or `.env.example`.

## What this does not cover, and cannot

**The alerting path runs on the machine it is watching.** If the node is off, unreachable, or its disk
is full enough to stop Postfix, no alert is sent — and the silence looks exactly like "nothing is
wrong". `15-03`'s "Two mechanisms, not one" says this plainly: an external check that answers *is the
whole thing gone* is a separate mechanism against
`https://chat.reserve-me.ru/healthz/ready`, and it is **still an open question**, not done. Do not read
a quiet inbox as a healthy deployment until it exists.

## Looking at the current state

Neither Prometheus nor Alertmanager has a public route, and neither is getting one — the same
reasoning that removed Grafana's.

```bash
kubectl port-forward -n ago-chat svc/prometheus 9090:9090     # /alerts, /rules, /targets
kubectl port-forward -n ago-chat svc/alertmanager 9093:9093   # firing, silences
```

To silence a rule while you are deliberately breaking something, use Alertmanager's UI on 9093 rather
than editing the rule file. A silence expires by itself; a commented-out rule does not.

---

## ScrapeTargetDown

**Fires when** any `loop="k8s"` scrape target has been unreachable for 5 minutes.

**What it means.** The Service behind that job has no ready endpoint. For `ago-chat-api`,
`ago-chat-worker` and `ago-chat-webhooks` that is a crashed pod, an OOM kill, a rollout that never
completed, or — because the API's readiness probe is `/healthz/ready` with `ready`-tagged checks for
Postgres, RabbitMQ and Redis — one of those three dependencies being unreachable. For `node` it means
node-exporter is gone, and therefore that `NodeDiskFilling` below is blind. For `rabbitmq` the broker
itself is down.

**First check.**

```bash
kubectl get pods -n ago-chat
kubectl describe deploy/<name> -n ago-chat
kubectl logs -n ago-chat deploy/<name> --previous     # --previous is the one that matters after a crash
```

If the pod is `Running` and `Ready` but the target is still down, the problem is the Service or the
metrics endpoint, not the workload. `kubectl get endpoints -n ago-chat <name>`.

**The one false positive to know about**: a `loop="compose"` target is permanently down on this
deployment by design (they point at a developer's own machine). The rule matches `loop="k8s"` only.
If you ever see this alert naming a compose target, the matcher has been lost — fix the rule, not
the target.

---

## OutboxLagGrowing

**Fires when** the oldest unpublished outbox row is older than 60 seconds, for 10 minutes.

**What it means.** Acknowledged writes have stopped being published — `CLAUDE.md`'s rule 4 failing
quietly. A client was told its message was accepted and the integration event never left the database.
`nfr.md` budgets the outbox dispatch inside a 300 ms p99 for cross-node delivery, so 60 s sustained is
not slowness; it is a dispatcher that is not running.

**First check.**

```bash
kubectl logs -n ago-chat deploy/ago-chat-worker --tail=200
```

Then, in order: is `ScrapeTargetDown` also firing for `rabbitmq`? A dead broker produces exactly this
(`realtime.md`'s failure table — outbox rows accumulate and drain when it returns), and the fix is the
broker, not the dispatcher. If the broker is healthy, look at the dispatcher's own loop, then at the
table:

```sql
SELECT count(*), min(occurred_at) FROM outbox_messages WHERE published_at IS NULL;
```

**Do not** resolve this by clearing the outbox. The rows are the only record that those events were
supposed to happen.

---

## DeadLetterQueueNotEmpty

**Fires when** any queue whose name ends in `.dlq` has held at least one message for 15 minutes.

**What it means.** A message failed every retry and is parked. Nothing will retry it; it stays until
someone looks. `nfr.md`'s correctness invariants are binary — "zero acknowledged-but-lost messages" —
and a DLQ entry is the observable form of one at risk.

**First check.**

```bash
kubectl port-forward -n ago-chat svc/rabbitmq 15672:15672
```

In the management UI, open the queue and use **Get message(s)** with *Requeue: yes* to read the payload
and the `x-death` header without consuming it. `x-death` carries the original queue, the reason, and
the count — which tells you which consumer failed and how many times. Then read that consumer's own
logs around the first death's timestamp.

The threshold is zero because zero is the only correct depth for a dead-letter queue. Working queues
are deliberately **not** alerted on: `OperatorPresenceLost.operator-disconnect-grace` holds a hundred
or more messages at rest by design, because the grace period is implemented by holding them.

---

## NodeDiskFilling

**Fires when** the node's root filesystem is under 15% free for 30 minutes.

**What it means.** On a single node this is the failure mode that takes everything down at once: every
local-path PVC (Postgres, RabbitMQ, MinIO, Prometheus, Grafana, Alertmanager) and the containerd image
store live on this one filesystem. 15% of 79 GB is roughly 12 GB — chosen as "you still have room to
fix this", not "you are out of room". `nfr.md` states no disk target, so this number is a headroom
choice and is labelled as one rather than dressed up as a derived limit.

**First check.**

```bash
ssh ago@<node-ip>
df -h /
du -xh --max-depth=2 / | sort -rh | head -20
sudo k3s crictl images                 # unreferenced :local layers from past builds are the usual answer
sudo du -sh /var/lib/rancher/k3s/storage/*
```

`redeploy.sh` builds new `:local` images on every run and never removes the old ones, so image layers
are the first place to look, and `sudo k3s crictl rmi --prune` is usually the whole fix. `15-05` owns
making that bounded rather than manual.

---

## TlsCertificateRenewalOverdue

**Fires when** the public certificate has under 21 days left, for 1 hour.

**What it means.** cert-manager renews this certificate 30 days before expiry — that is its own
`renewal_timestamp`, not a number picked here — so under 21 days left means renewal has been failing
for more than a week. Nothing is broken yet. Everything public breaks on the expiry date if it is
ignored: widget, console, API and Keycloak are all behind this one certificate.

**First check.**

```bash
kubectl describe certificate -n ago-chat ago-public-tls
kubectl get certificaterequest,order,challenge -n ago-chat
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

A failed HTTP-01 challenge is the usual cause, and its usual root cause is DNS or the Gateway not
routing `/.well-known/acme-challenge/` — so check that the domain still resolves to this node and that
the Gateway is accepting traffic, before suspecting cert-manager itself.

---

## Testing a change to the rules

Two levels, and both are cheap. Neither is optional: the first cannot see whether the metric exists on
the real cluster, and the second cannot see whether the threshold is right.

**Offline, on the thresholds** — from `ago-deploy/k8s/overlays/demo`:

```bash
cd ~/git/ago/ago-deploy/k8s/overlays/demo
docker run --rm -v "$PWD:/w" --entrypoint /bin/promtool prom/prometheus:v3.0.1 \
  test rules /w/prometheus-alert-rules.test.yml
```

Every rule is asserted twice — silent one step below its threshold, firing one step above — and each
test also pins a near-miss that must stay silent. Add both when you add a rule.

**Live, on the delivery path** — post a synthetic alert straight into Alertmanager and watch it come
out the other end. This exercises Alertmanager, Postfix, the alias and the outbound leg without
touching any rule:

```bash
ssh ago@<node-ip>
cat > /tmp/testalert.json <<'EOF'
[{"labels":{"alertname":"AlertingPipelineSelfTest","severity":"page"},
  "annotations":{"summary":"manual check of the notification path"}}]
EOF
POD=$(kubectl get pod -n ago-chat -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
kubectl cp /tmp/testalert.json ago-chat/$POD:/tmp/testalert.json
kubectl exec -n ago-chat deploy/prometheus -- wget -qO- \
  --header='Content-Type: application/json' --post-file=/tmp/testalert.json \
  http://alertmanager:9093/api/v2/alerts

sleep 45
sudo grep -a 'alerts@reserve-me.ru' /var/log/mail.log | tail -5
```

`status=sent` twice is what you want — once `(delivered to mailbox)` for the local copy, once with a
`250 ... OK` from the receiving provider for the forwarded one. The alert auto-resolves after
`resolve_timeout` (5 minutes) and sends a `[RESOLVED]` mail; that is the pipeline working, not a
second problem.

**A note on deliverability, because this is the weak link.** `adr/0040`'s amendment is explicit that a
single VPS IP with no sending history is judged on nothing, and that blocklist monitoring is unowned
here. A `250` from the receiving provider means *accepted*, not *in the inbox*. If alerts stop being
noticed, check the spam folder before assuming nothing fired, and check `/var/mail/ago` — the local
copy exists precisely so that "did it fire?" has an answer that does not depend on the internet.
