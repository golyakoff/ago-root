# a module registration has no lifecycle — nothing creates one, nothing rotates or revokes it

- **Stage**: 22
- **Status**: ready
- **Found**: 2026-09-03

## The gap

`22-04` gave each site its own module credential, held in a row: `ChatModuleRegistration` in `ago-calendar`, `ModuleSiteRegistration` in `ago-faq`. **Nothing outside a test writes one.** No endpoint, no console screen, no seed, no migration default.

Deployed as it stands, every chat-originated call to either product is refused — correctly, since there is no registration to verify against. The mechanism is sound and unreachable.

And the repositories are **add-and-read only**. There is no update and no delete, so:

- a credential that leaks **cannot be rotated**;
- a site whose access should end **cannot be revoked**.

## Why these are one item and not three

They are one promise — *a module registration is something that can be created, changed and ended* — and splitting them fails the test that matters: a provisioning path that can only add is half a path, and shipping it alone would leave the system in a state where a leaked secret has no remedy. Closing them together is the only way each lands green.

## Where it has to fit

- **Chat is the enabling side.** `EnableModuleForSite` already writes `EnabledModule` with the credential the chat side mints (`22-02`). The module product needs the matching row with the same secret — so this is a two-sided operation whose halves must not be able to drift.
- **Chat must not learn a product's name.** Whatever carries the registration travels over `adr/0065`'s generic contract, or the product exposes something chat calls generically. It is not a calendar-shaped API.
- **`adr/0094`'s wire format already has three hand-kept copies.** Do not make provisioning a fourth thing that must agree by hand.
- `20-27`'s `Ago.Calendar.Provisioner` is the precedent for a one-shot, no-DI, no-HTTP tool if the answer turns out to be operational rather than an API. It is not automatically the answer.

## Done when

- [ ] Enabling a module for a site produces a working registration on the module side, with no hand-inserted row anywhere — proven end to end, by a call that succeeds afterwards and failed before.
- [ ] A credential can be rotated without downtime for other sites, proven by rotating one while another keeps working.
- [ ] Revoking a site's registration refuses its subsequent calls, proven by trying one.
- [ ] The two sides cannot silently disagree: a registration that exists on one side only is detectable.

## Context

Found by the `22-04` worker and reported as *"the load-bearing gap in this report, not a footnote"* — correctly. Harmless today only because `enabled_modules` holds zero rows and `ago-faq` is not deployed.
