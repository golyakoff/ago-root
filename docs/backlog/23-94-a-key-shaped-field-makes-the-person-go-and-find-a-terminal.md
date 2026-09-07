# a key-shaped field makes the person go and find a terminal

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-92` is the neighbouring cure for the same disease — a form asking a human
  for something a machine should supply.
- **Found**: 2026-09-07, by the author, filling in a module credential by hand.

## What is wrong

The platform owner's grant form has a **Credential** field: the module's own per-site credential,
16–256 characters, never shown again once saved. Nothing exists to produce one. The author asked what to
put there, and the honest answer was *"go to a terminal and run `openssl rand -base64 32`"*.

**That is not a small friction, it is the friction that produces a weak secret.** A person who does not
have a terminal open, or is on a phone — which is where this was found — will type something. Whatever
they type will pass, because the only rule is a length floor, and `ModuleCredential`'s own remarks say
the floor exists as *"a floor against an operator typing something trivial"*. A floor is not a generator.

## Scope

- **A generate control beside every key-shaped field**, producing a value of the right shape for that
  field. Today that is Credential; the same argument covers any future field whose correct value is
  "random, long, and not chosen by a human".
- **The value is visible once, and copyable**, since this is the only moment it can be seen — the field
  is write-only afterwards by design.
- **Client-side if the browser can do it properly, a server route if it cannot.** The author's own
  framing, and the right order: `crypto.getRandomValues` is present in every browser this console
  supports and is a real CSPRNG, so the likely answer is that no route is needed. **Establish that rather
  than assume it**, and if a route is built, say what it does that the browser could not.
- **Never `Math.random()`.** It is not a CSPRNG, and a generator that produces predictable secrets is
  worse than no generator, because it removes the prompt to think.

## Where this is likely to go wrong

- **Generating is not the same as saving.** The generated value must be what actually reaches the module —
  if the field is regenerated, re-rendered, or trimmed between the click and the submit, the tenant ends
  up with a credential nobody holds. A test should follow one generated value from the click to the
  request body.
- **A generated secret must not be logged, and must not survive the page.** It is a credential from the
  moment it exists.
- **Do not put it in the URL, browser storage, or a form autofill path.** The console has no reason to
  keep it after the request.
- **The field's own hint is currently wrong next door.** `23-92` records that the Entry point hint claims
  a scheme that is neither required nor correct; whoever touches this form should not leave that pattern
  intact for Credential.

## Done when

- [ ] A key-shaped field can be filled without leaving the browser, with a value from a CSPRNG.
- [ ] The generated value is the one that reaches the module, proven by following it to the request body.
- [ ] Whether a server route was needed is answered explicitly, either way.
