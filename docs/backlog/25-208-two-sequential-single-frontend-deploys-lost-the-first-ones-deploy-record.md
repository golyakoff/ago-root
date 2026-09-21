# 25-208 · Two sequential single-frontend deploys lost the first one's deploy-record entry

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-21, live on the demo VPS, while landing `25-202`..`25-206`: `./deploy.sh
  demo-shop1 72af3a7...` ran to completion (rollout succeeded, smoke 42/43 - the one expected
  failure being `widget-assets` not yet moved), then `./deploy.sh widget-assets 72af3a7...` ran
  immediately after (rollout succeeded, smoke 43/43). A `check-manifest-drift.sh` run straight after
  both reported the manifest and the cluster in full agreement. A **second**, standalone
  `check-manifest-drift.sh` run about a minute later - after `ago-deploy`'s own manifest-pin PR
  merged and the node's checkout pulled it - reported real drift: `ago-deploy-record`'s own
  `ago-demo-shop1` key held `3b99549...`, the tag from *before* either deploy, even though the live
  Deployment's own image (confirmed directly via `kubectl get deployment ... -o jsonpath`) was
  correctly `72af3a7...` throughout. `ago-widget-assets`'s own key was correct.

- **Recurred, same day, same shape**: landing `25-207`/`25-209` (`ago-console`, `ago-widget`), the
  deploy sequence was `./deploy.sh demo-shop1 fae3969...` then `./deploy.sh widget-assets
  fae3969...` (same pattern: two sequential single-frontend deploys), followed separately by
  `./deploy.sh console 5f79a7a...`. A standalone `check-manifest-drift.sh` run after `ago-deploy`
  PR #255 (the manifest pin) merged and was pulled reported: `ago-demo-shop1 recorded
  72af3a7dcaad22893f654c5a37712549de0bcc17, manifest still pins fae396944b8f0a43e1e50ebb330a82a925d621f2`
  - `72af3a7` being exactly the value this same key held *before this round's* deploy (i.e. the
  value this item's own first occurrence had fixed it to). The live Deployment's own image was
  confirmed correct (`fae3969...`) throughout via `kubectl get deployment ... -o jsonpath`, exactly
  as the first occurrence found. **This is the same key, in the same position** (the first of a
  sequential `demo-shop1` → `widget-assets` pair) reverting to its own pre-deploy value once the
  second deploy in the pair runs - not a new symptom, a second confirmation of the same one, which
  now makes "the first of two sequential single-frontend deploys loses its record to whatever the
  key held immediately before that pair ran" a reproduced pattern rather than a one-off. Fixed the
  same way: `kubectl patch configmap ago-deploy-record --type=merge -p
  '{"data":{"ago-demo-shop1":"fae396944b8f0a43e1e50ebb330a82a925d621f2"}}'`, re-verified clean with
  a standalone `check-manifest-drift.sh` re-run.

## What is actually true today, confirmed rather than assumed

`lib-deploy-record.sh`'s `record_write` uses `kubectl patch configmap ago-deploy-record --type=merge`
with only the keys the current invocation deployed - reading the function itself, a single-frontend
deploy's own merge patch should touch exactly one key and leave every other key, including one
another invocation wrote moments earlier, untouched. No cron job, systemd timer, or GitOps
reconciliation loop was found on the node that could plausibly have reset the ConfigMap between the
two `deploy.sh` calls (checked `crontab -l`, `sudo crontab -l`, `systemctl list-timers --all` -
nothing named `ago`/`deploy` runs on a schedule that fits the window). `apply-demo.sh` never calls
`record_write` at all.

**This item does not have a confirmed root cause and should not invent one.** The mechanism read
correct on paper; the observed ConfigMap state was wrong in a way that specifically pointed at "the
first of two sequential single-frontend deploys, run back to back with no drift-check in between, has
its own record entry overwritten by something before the second deploy's own write" - stated as the
symptom, not diagnosed as the cause.

## Scope

- **Reproduce it deliberately** - two sequential `./deploy.sh <frontend-a> <sha>` /
  `./deploy.sh <frontend-b> <sha>` calls against a real or a scratch cluster, with a `kubectl get
  configmap ago-deploy-record -o yaml` snapshot taken after each call (not only at the end) to catch
  the exact moment the first entry reverts.
- **Instrument or add logging to `record_write`/`record_check` temporarily** if the snapshot alone
  does not localise it - in particular, confirm whether `record_write`'s own `kc get configmap ... ||
  kc create configmap ...` fallback is somehow re-triggering on the second call (which would imply the
  `kc get` check itself is unreliable rather than the patch), and whether `kc` resolves to `kubectl`
  or the `sudo k3s kubectl` fallback consistently across both invocations in the same shell session
  the operator actually used (an inconsistency there is a real candidate: `record_check`'s own
  `kc get configmap ago-deploy-record -n "$ns" >/dev/null 2>&1` fallback path has not been exercised
  as often as the success path has).
- **Fix the real cause** once found, with a regression test if this project's own deploy-tooling test
  conventions support one (check `docs/conventions/testing.md` and how `lib-deploy-record.sh`'s
  sibling libraries are already tested, if at all).
- **State plainly if this turns out to be unreproducible** - a one-off caused by something specific to
  that exact session (e.g., a stale `kc` function definition left over from a much earlier `source` in
  the same SSH session) is a real, honest possible outcome, and this item should say so rather than
  leave a phantom fix in place for a bug that was never real.

## Out of scope

- Any change to `deploy.sh`'s actual image-setting behaviour (`kubectl set image`) - only the
  ConfigMap it is not meant to affect ever showed wrong.
- Redesigning the deploy-record mechanism itself (ConfigMap vs. some other store) - `23-90`'s own
  reasoning for choosing a ConfigMap is unaffected by this bug, whatever its cause turns out to be.

## Done when

- [ ] The sequence is reproduced on demand, or the item states plainly that it could not be
      reproduced and why that is a credible one-off rather than a live bug being left in place.
- [ ] If reproduced, the real mechanism is named with evidence (not "kubectl is sometimes wrong"),
      and a fix lands with the one manual demo-stand correction already applied (`ago-demo-shop1` set
      back to `72af3a7...` by hand, 2026-09-21) as its own proof the live state is currently correct.
- [ ] `check-manifest-drift.sh` run twice in a row, minutes apart, with no deploy in between, agrees
      with itself both times - the actual symptom that should never recur.
