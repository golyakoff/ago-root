# the visitor's consent attaches to handing over contact details, not to opening the chat

- **Stage**: 24
- **Status**: ready
- **Depends on**: `24-01` (the record), `24-02` (the version). `16-04` shipped the notice this builds
  on; `23-09`/`23-10` are the acts this consent actually attaches to.
- **Decision**: `docs/adr/0076-*` — AGO is **processor** on the tenant's instruction for visitors'
  conversation data

## Goal

A tenant who needs their visitors' consent can collect it at the moment it is actually needed — when a
visitor hands over a phone number or an email — and have it recorded, without AGO authoring the words
or becoming the party who collected it.

## Where the consent attaches, and why this is the crux

**Not at the chat. At the contact details.**

The 1 September 2025 rules name "cannot use the site without ticking the box" as a defect, and they are
right to: a consent that is the price of using the product is not freely given. But handing over a
phone number is a different act, and gating *that* on a consent is both lawful and honest.

Checked against a competitor operating under the same law: Jivo attaches its consent checkbox to the
**contact form**, not to the chat — *"Контактные данные будут переданы только после установки
галочки"* — and keeps a second, optional checkbox for marketing that cannot be enabled without the
first. Two controls, two purposes, one of them refusable. That is the shape.

For us that means this item lands on `23-09` (a visitor leaves a name and a phone) and `23-10` (an
operator promotes one out of the transcript), not on the widget's opening. **A visitor who only ever
types "do you have this in blue?" is asked for nothing.**

## The one place we deliberately differ from the competition, and it is worth re-deciding

`16-04` established that **AGO never authors a default text** — the tenant supplies the words, because
it is the tenant's relationship with their own customer. Jivo does the opposite: it offers a *типовой
документ* alongside the option of the tenant's own file or link.

Both positions are defensible and they trade different things:

- **Ours**: no risk of AGO's words being wrong for a tenant we know nothing about, and no implication
  that AGO is the collecting party. Cost: a small tenant with no lawyer has nowhere to get a text, so
  the feature stays off and the tenant is *less* compliant, not more.
- **Theirs**: the feature is usable on day one. Cost: a generic text shown to every visitor of every
  tenant, and a platform that looks like the author of a document it is not party to.

**This item does not decide it.** It is a product and legal call for the author, and it is recorded
here so it is made deliberately rather than inherited from `16-04` by default. If the answer is a
template, `16-04`'s stance is superseded rather than quietly bent.

## What is actually true today, verified

`16-04` is shipped: the widget's processing-notice text and link are per-site configuration, shown
before the visitor types. Nothing records that any visitor saw it, and there is no mechanism for a
tenant who needs an actual consent rather than a notice.

## Scope

- A per-site setting: a recorded consent is required before contact details are accepted, or it is not.
  **Default is unchanged behaviour**, because silently changing every tenant's widget would be worse
  than leaving it.
- Where required, the visitor's act is recorded per `24-01`, against a version of the **tenant's**
  document.
- **A second, separate, optional control** for anything beyond the contact itself — marketing being the
  obvious one — which cannot be the same tick. Bundling them is precisely what the September 2025 rules
  forbid.
- Refusing must leave the visitor able to keep using the chat. They lose the ability to hand over a
  phone number, and nothing else.
- `personal-data.md` records what a visitor acceptance holds and how erasure reaches it — a visitor
  erasure already takes their conversation and their contact (`23-08`); this is a third thing.

## Out of scope

- Writing the tenant's document. Whether AGO offers a template at all is the open question above, and
  is decided before this is built, not during.
- Whether a given tenant needs consent. Their lawyer's question about their own relationship.
- **The channel-arriving visitor.** Somebody who writes from SMS or Telegram never opens the widget, so
  the widget cannot be where their basis is established. Named here, left to its own item rather than
  half-solved.

## The exemption `24-01` leaves behind does not extend to this item

`24-01` built `RecordAcceptanceHandler`/`GetAcceptancesForSubjectHandler` with **no host endpoint**, and
both are listed in `TenantScopeExemptions` — correct for that item, because neither takes a `SiteId` and
no route maps to either, so there is nothing yet for a permission policy to sit behind.

This item builds one of the real entry points, and the exemption entries will already be in the file
when it starts. Two things follow, and neither is negotiable:

- **The subject comes from the validated principal, never from a parameter the caller supplies.** An
  endpoint that accepts a subject id and checks it matches is the same defect with an extra step.
- **The exemption covers the handler, not the route.** Adding an endpoint means the route carries its
  own authentication and authorisation, argued in this item rather than inherited from a line written
  when there was no route at all.

## Done when

- [ ] A site can require a recorded consent before contact details are accepted; the default is
      unchanged behaviour.
- [ ] Consent gates the contact details and **not** the conversation — asserted by a test, because this
      is the half that would quietly become a gate on the product.
- [ ] Anything beyond the contact is a separate, independently refusable control.
- [ ] Where required, the acceptance is recorded with the tenant's document version.
- [ ] `personal-data.md` records the store and its erasure path.

## Open questions

- **Does AGO offer a template text?** See above. It changes `16-04`'s recorded stance and should
  supersede it rather than bend it.
- **The channel case is genuinely unsolved**, and naming it here is not solving it.
