---
name: take-a-backup
description: Take an encrypted backup of the live node's databases on demand, pull it to the author's machine and prove it arrived intact. Use before anything that changes the shared Postgres - a migration, a new database, a schema change - and whenever a backup is wanted outside the nightly timer.
---

# Taking a backup on demand

The node takes one nightly. This is the other case: **before you change the shared database**, and
whenever somebody asks for one now.

The whole procedure is four commands. The value of this file is the three ways it goes wrong, each of
which has already cost a session time.

## 1. Never run `backup.sh` with `sudo` directly

```bash
sudo bash ~/ago/ago-deploy/k8s/backup/backup.sh     # WRONG
```

```
backup FAILED: no recipient public key at /root/ago/backup-recipient.pub
```

`sudo` resets `HOME` to `/root`, and the recipient key lives in `ago`'s home. The script is right to
refuse — it will not write an artifact it cannot encrypt — but the message names a path that never
existed rather than the substitution that caused it.

**Run the unit instead.** It carries the environment the script expects, and it is the same path the
nightly timer takes, so an on-demand backup is byte-for-byte the same operation as a scheduled one
rather than a second way of doing it:

```bash
ssh -i ~/.ssh/ago-vps-ed25519 ago@<node>
sudo systemctl start ago-backup.service
```

It is synchronous enough to finish in seconds. Confirm by the artifact, not by the exit code:

```bash
ls -lt ~/ago/backups/*.tar.gpg | head -3
```

The newest filename carries its own UTC stamp — `ago-backup-20260903T074159Z.tar.gpg` — which is the
only trustworthy age, for the reason in step 3.

## 2. Pull it off the node, and check it arrived

A backup that only exists on the machine it is backing up is a copy, not a backup.

```bash
bash C:/git/ago/backup-tools/pull-backups.sh
cat C:/git/ago/db_backups/_status.txt
```

That script fetches only what is missing, **verifies the sha256 of every artifact already on disk**
(not just the new one — a file that rotted afterwards is the same problem and just as silent), and
writes `OK`/`FAIL` with the newest artifact's age.

It also runs daily from the Windows Task Scheduler as `AGO backup pull`. Running it by hand is
harmless and idempotent.

## 3. The failure that looks like success

**A run that fetched nothing is indistinguishable from a healthy one**, and stays that way for as
long as nobody looks. If the node stopped producing backups, the pull still succeeds — it copies
zero new files and reports no error.

That is why the status line carries the **age of the newest artifact**, derived from the filename's
own UTC stamp rather than the file's mtime: `scp` without `-p` stamps a copied file with the copy
time, so mtime would answer "when did we last fetch" instead of "when was this taken". The two agree
until they matter.

So read the age, not the word `OK`.

## 4. Never decrypt automatically

The private half of the key is on the author's machine and its passphrase is typed by a human. That
is the design (`restore.sh`'s own remarks): nothing automated in this arrangement decrypts. If a
restore is wanted, that is `docs/runbooks/backup-and-restore.md`'s drill, and it runs against a
**scratch** target — never the live deployment, which has no default pointing at it precisely so that
it cannot happen by accident.

## What the artifact should contain

`backup.sh` **asks Postgres which databases exist** rather than working from a remembered list
(changed 2026-09-02, after a list would have silently missed a new one). The manifest inside names
them in `databases_dumped=`, with row counts taken at dump time.

**That line is the check worth making after a change that adds a database.** A backup that ran, wrote
an artifact and quietly omitted the new database is the exact failure the enumeration change exists to
prevent — and confirming it takes reading one line of a manifest the drill already prints.

## When to reach for this

- Before a migration, a new database, or anything else that changes the shared Postgres.
- Before a first deploy of a new product into the existing cluster.
- When somebody asks for a backup now.
- After such a change, again — so the artifact that names the new state exists, rather than only the
  one that predates it.
