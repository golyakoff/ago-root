# the console tells a tenant to switch on a control it does not have

- **Stage**: 23
- **Status**: ready — **the gap is established; which way to close it is not**
- **Depends on**: nothing. Found while sweeping `23-107`'s guidance strings.
- **Found**: 2026-09-08, sweeping every string that tells a tenant to go somewhere.

## What a tenant reads

On the documents screen, on the contact-consent panel, when the document is not being enforced:

> Пока не требуется — включите «Требовать согласие перед сбором контактных данных» в настройках
> виджета, иначе это никого не связывает

Rendered with `badgeTone="danger"`, so it is the loudest thing on the panel.

## Why it cannot be followed

**That control does not exist.** The quoted phrase appears exactly once in the whole console — in
this sentence. There is no field, no label, and no string for it on the widget-settings screen or
anywhere else.

The setting itself is real: `Site.WidgetConfig.RequireContactConsent` is enforced by the API
(`GetConsentRequirement`, and `ConversationErrors`' `AgreementUnavailable`), and it is carried on
the widget-config endpoint's request and response (`WidgetConfigEndpoints.cs`). The console reads
it — `siteConsentDocumentsApi.ts` exposes `contactConsentRequired` — and never writes it.

So a tenant is told, in the strongest tone the component offers, to do something the product does
not let them do. `23-107`'s rule was that a screen name is not a path; this is the harder case,
where no path exists at the end of it.

## Why it is not merely cosmetic

A tenant who publishes a contact-consent document reasonably believes they have done the thing the
screen asked of them. The panel then tells them it binds nobody, and offers no way to change that.
Whether consent is actually collected before a phone number is captured is exactly the kind of
question where believing you have configured something and not having done so is worse than knowing
you have not.

## The readings — this is the part that needs the author

1. **The console gains the control.** The endpoint already accepts it, so this is a field on the
   widget-settings screen and nothing more. It makes the instruction true as written.
2. **Requiring consent stops being optional** when a contact document is published — the flag becomes
   a consequence of publishing rather than a separate switch, and the sentence disappears instead of
   being fixed. Fewer controls, but it takes a choice away from a tenant who may have one document
   for one jurisdiction and different rules elsewhere.
3. **The sentence is corrected to say what is actually true** — that enforcement is not yet available
   from the console — and the control is filed separately. Cheapest, and honest, but it leaves the
   product with an enforced setting no owner can reach.

**This item does not pick.** Reading 2 is a product decision about what a published document means,
and reading 1 quietly answers it the other way by shipping a switch. Both are choices the author
makes, not the implementer.

## Done when

- [ ] The reading is chosen by the author and recorded where a reader will find it.
- [ ] No screen instructs a tenant to operate a control the console does not offer.
- [ ] Whether `RequireContactConsent` is reachable by a site owner at all is settled either way.
