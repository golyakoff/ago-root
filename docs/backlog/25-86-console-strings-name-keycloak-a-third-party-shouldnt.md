# 25-86 · Console strings name Keycloak, a third party nobody should see

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-14, the author's own live walkthrough of the invite/onboarding flow -
  `onboardingDescription` read "Ваш Keycloak-аккаунт подтверждён..." on the "finish setting up your
  site" screen, which names an implementation detail nobody signing up has any reason to know, and is
  a small security-hygiene smell on top of being noise.

## What is actually true

Four strings, present identically in `en.ts` and `ru.ts` (`ago-console/src/i18n/`), name Keycloak by
name:

- `onboardingDescription` - "Your Keycloak account is verified..." - pure leak, no reason given.
- `callbackOperatorLookupFailedDetailSuffix` - "...this is not related to your sign-in through
  Keycloak." - pure leak, no reason given.
- `signupDescription` - "...you'll enter your email and password on Keycloak's own registration
  page." - **not pure noise**: it is warning the visitor they are about to leave to a different page
  to do something before returning. The fact is useful; the brand name attached to it is not.
- `onboardingPlatformOwnerAlertBody` - "The platform owner role is a role in the Keycloak realm..." -
  **not pure noise** either: it distinguishes a realm-wide role from a site-scoped one, and that
  distinction is real and worth keeping, even if only the platform owner ever reads this string.

## Scope

- The two pure leaks lose the word "Keycloak" and the sentence around it simplifies rather than
  awkwardly working around the missing noun - "Ваш аккаунт подтверждён", not "Ваш аккаунт [blank]
  подтверждён".
- The two others **keep their own useful fact, reworded without the third-party name**: "you'll
  complete this on a separate page" instead of "on Keycloak's own registration page"; "a realm-wide
  role, not tied to one site" instead of "a role in the Keycloak realm." The author's own boundary for
  this, stated directly: naming *a different page/step* is fine and worth keeping as long as it stays
  inside AGO's own domain family - the distinction that matters is "ours, a different step" versus "a
  named third-party's own system," never "which page, exactly."
- Grep beyond these four before calling this done - `onboardingDescription`'s own case was found by
  the author reading the actual screen, not by a systematic search, so treat "four" as a floor, not a
  ceiling, and report the real final count.

## Done when

- [ ] No console string names Keycloak, in either locale.
- [ ] The two strings that carried a real, useful fact beside the leak still carry that fact, reworded
      without the third-party name - proven by reading the actual rendered screen, not only the string
      table.
- [ ] A grep for "Keycloak" across `ago-console/src` (excluding tests and code comments) returns
      nothing.
