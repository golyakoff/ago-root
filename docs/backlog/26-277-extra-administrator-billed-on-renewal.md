# 26-277 · Extra administrator is not billed on renewal (revenue leak); seed the price; reconcile +500→+1000

- **Stage**: 26. Kind: defect fix (billing correctness). Found 2026-09-29 by the billing-vs-published
  reconciliation, filed by the managing session (CLAUDE.md rule 14).
- **Status**: done 2026-09-29 — merged as ago-chat#395 (fix + seed migration) and ago-business#40 (0012
  price text).
- **Repos touched**: `ago-chat` (renewal handler + seed migration + code comments), `ago-business`
  (decision `0012` price text). No platform, console, android, or landing change.

## The defect (reconciliation finding, cited)

The published pricing charges **+1000 ₽/mo per administrator beyond the second**. The code charged it
**once** and then never again:

- `PurchaseAdministratorSlotHandler` bills the extra administrator as a one-time prorated purchase.
- `ProcessSubscriptionRenewalHandler` computed the recurring `amount` as `seatAmount + overageAmount`
  only — `ExtraAdministratorsPurchased` was **absent from the renewal term**. So a tenant kept a paid
  3rd administrator but stopped paying for it on the first renewal. A real revenue leak.

Two further gaps in the same dimension:

- `admin-extra` (1000) was **not seeded by any migration** — it existed on the stand only because the
  owner published it by hand. On a fresh/local deploy, administrator purchase returned
  `PriceNotConfigured`. (`seat-base`/`seat-extra`/`download-overage-per-gb` are all migration-seeded.)
- Stale **`+500`** (the old administrator price) still lived in `SubscriptionTierBands.cs` and
  `BillingSubscription.cs` comments, and in ago-business `0012`.

## The one promise

A tenant with purchased extra administrators is charged `+1000 × count` on **every** renewal, the price
is **seeded** so purchase works on any deploy, and **every** authoritative source says 1000, not 500.

## Done-when

- [x] `ProcessSubscriptionRenewalHandler` adds `ExtraAdministratorsPurchased × current(admin-extra)` to
      the renewal amount, reading the price fresh from `IPriceCatalogRepository` the same way seats do
      (throws if purchased-but-unpriced, never charges zero; skipped when none purchased). Renewal tests
      assert `amount == seat + admins×adminPrice` and the missing-price guard (fails-before: 490 vs 2490).
- [x] A data-seed migration (`Stage26SeedAdminExtraPrice`) seeds `admin-extra` = 1000, `ON CONFLICT DO
      NOTHING` so the stand's manually-published row is untouched. Seed integration test (fails-before:
      null without the migration).
- [x] `SubscriptionTierBands.cs` + `BillingSubscription.cs` comments and ago-business `0012` say 1000, not
      500. (Closed-item backlog history 25-20/25-29/25-41 is historical record — left as-is.)
- [x] `channel-addon` explicitly out of scope here — filed as **26-278**.

## Outcome

Merged as ago-chat#395 and ago-business#40, 2026-09-29. Full ago-chat suite green (Domain 809,
Application 1616, Integration 1601, Architecture 53, Concurrency 91, FakeCrm 21). Fails-before proven for
both the renewal charge and the seed. The connected-channel add-on (advertised but never charged) is the
sibling item **26-278** (designed; implementation queued behind this item's migration).
