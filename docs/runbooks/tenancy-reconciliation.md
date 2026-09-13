# Running the tenancy reconciliation report

`22-32`. Nobody could previously find out, without asking anyone, whether every account with the
calendar add-on has exactly one calendar tenant and whether any calendar tenant exists without an
account. This procedure is how a person finds out, on demand.

**It reports. It never repairs.** A reconciliation that auto-fixes drift is a program that deletes a
tenant's data on the strength of a join, and the first time it is wrong it is catastrophically wrong
(`22-32`'s own Out-of-scope section). What a non-zero result means, and what to do about it, is a
person's decision — this file's last section says where that decision leads.

**Manual, on demand — deliberately not a scheduled workload.** `22-32`'s own Open questions section
treats "a script with both connection strings is a new place two credentials meet" as a real
question, and reserves whether it becomes a Kubernetes `CronJob` — a new scheduled workload holding
credentials to two databases — for the author to decide, explicitly, separately. This procedure is
the other branch: a person runs it when they want the answer to "is it drifting right now?", the same
shape `ago-chat/docs/runbooks/landing-prices.md`'s script already uses for a single-database
on-demand read.

## What you need before you start

- A connection to the live `ago_chat` **and** `ago_calendar` databases — the same reachability
  `backup-and-restore.md`'s own drills need: either a direct connection if you have one, or an
  SSH-tunnelled `kubectl port-forward` chain against the real node.
- `psql` on your own machine, or a container (e.g.
  `docker run --rm --entrypoint psql postgres:17-alpine ...`) if you don't want it installed directly.
- `join`, `comm`, `sort`, `cut`, `awk`, `wc` — every POSIX shell already has these; nothing else is
  required.

**As of `20-20`, both databases live on the same Postgres instance under the same `ago` role**
(`ago-deploy/k8s/base/api.yaml` and `calendar-api.yaml` — `AGO_CHAT_CONNECTION_STRING` and
`AGO_CALENDAR_CONNECTION_STRING` differ only in `Database=`), so in practice the two connection
strings below are usually identical apart from `dbname=`. The script still takes two full connection
strings rather than one string plus a second database name — that coincidence is not a guarantee, and
nothing here should quietly stop working the day the two databases move apart.

## Running it

```bash
cd C:/git/ago/ago-deploy/k8s
bash tenancy-reconciliation-report.sh \
  "host=<host> port=<port> dbname=ago_chat user=<user> password=<password>" \
  "host=<host> port=<port> dbname=ago_calendar user=<user> password=<password>"
```

Each connection string is whatever `psql` itself accepts — a libpq keyword string (shown above) or a
`postgresql://` URI. **Both are required arguments** — there is no default and no fallback to a bare
`psql`'s own `PG*` environment variables, precisely so a missing second argument fails loudly with a
usage message instead of quietly running two queries against the same database. The script never
logs, stores, or echoes either string.

## What it checks

1. **Every account with an active calendar registration** (`ago_chat.enabled_modules`,
   `module_key = 'calendar'`, `revoked_at is null` — a revoke stamps this column since `22-30` rather
   than deleting the row, so a revoked registration correctly stops counting as "active" here) that has
   **no matching row in `ago_calendar.tenants`.** Half-failed provisioning: payment succeeded,
   provisioning did not (`22-07`'s own words).
2. **Every calendar tenant that was provisioned from a chat purchase** (`ago_calendar.tenants`,
   `auto_provisioned = true` — the flag `RegisterChatModuleHandler` sets, and the only reliable way to
   tell "this tenant exists because a chat account bought the module" apart from "a human registered
   this tenant directly") **that has no active chat registration naming it.** This is the shape a
   revoke leaves behind: the calendar's own `RevokeChatModuleRegistrationHandler` deletes only its
   registration row, never `tenants`, `customers`, `events` or `workers`.

There is no `site_id`/`account_id` column on `tenants` linking it back to a chat account — by
construction (`adr/0093`, `22-03`), **`tenants.id` is the same value as `sites.id` on the chat side**
for every chat-provisioned tenant. That equality is the entire join.

**A tenant with `auto_provisioned = false` is never treated as drift**, no matter which side of the
join it falls on — it was registered directly, by a human, and never had a chat account to agree with
in the first place. The report still counts these tenants, as context, so a reader can see they exist
and are accounted for, but their absence from `enabled_modules` is not flagged as an asymmetry the way
a chat-originated tenant's would be.

## What it reports, and what it deliberately does not

**Counts and identifiers only — an id and a name, never a full row.** This is a cross-tenant read, and
identifiers-only is what keeps it from being a third copy of anyone's data (`22-32`'s own Scope
section — and is why this script needs no `adr/0113` `access_records` entry: it reaches no person's
data to record a reach of). Nothing this script prints ever includes a credential, an entry point, an
allowed-origin list, or any other column from either table beyond the id and the display name.

A clean run says so plainly:

```
RESULT: no drift - the two databases agree about who exists.
```

A non-zero run states the count and lists the ids and names that need a look, then says the same
thing every time: this script only reports, it repairs nothing.

**`TENANCY_REPORT_MAIL_ON_DRIFT=1`** additionally mails the report through the node's own Postfix, to
the same `alerts` alias `15-03`'s own rules already use (`docs/runbooks/alerting.md`) — the identical
mechanism `ago-deploy/k8s/backup/backup-watchdog.sh` already uses for its own findings. This is
best-effort only: off the node, or on a machine with no `/usr/sbin/sendmail`, it is silently skipped
rather than failing the report. It does not make this script scheduled — it still only fires the
moment a person runs it by hand.

```bash
TENANCY_REPORT_MAIL_ON_DRIFT=1 bash tenancy-reconciliation-report.sh "<chat connection>" "<calendar connection>"
```

`TENANCY_REPORT_ALERT_TO` / `TENANCY_REPORT_ALERT_FROM` override the default addresses
(`alerts@reserve-me.ru` / `no-reply@reserve-me.ru`) the same way `AGO_BACKUP_ALERT_TO`/`_FROM` already
do for the backup watchdog.

## If it finds drift

This script's job ends at the report. What to do about a specific stranded tenant or a specific
half-provisioned account is a decision for a person, following
`docs/runbooks/module-grant-and-revoke.md` — that is where a repair procedure belongs, not here.

## Run against the live deployment, 2026-09-14

Confirmed against the real node (SSH tunnel + `kubectl port-forward` to the live `postgres` pod, the
identical reachability path `backup-and-restore.md`'s own drills already use), both queries running
for real for the first time:

```
accounts with an active calendar registration (ago_chat.enabled_modules): 1
calendar tenants total (ago_calendar.tenants): 1
  of which chat-originated (auto_provisioned = true): 1
  of which standalone, never chat-linked (auto_provisioned = false): 0

RESULT: no drift - the two databases agree about who exists.
```

Both queries executed cleanly against the real schema — no column-name or type error — and `psql`'s
`t`/`f` boolean literal in unaligned mode matched what the `awk` filter expects. The deployment's own
first real answer is **no drift**, on a single chat-originated calendar tenant. This is the actual
deliverable `22-32`'s own Done-when asks for, not only that the tool exists.
