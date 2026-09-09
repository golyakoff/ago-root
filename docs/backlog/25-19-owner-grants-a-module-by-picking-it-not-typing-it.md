# 25-19 · The owner grants a module by picking it, not typing it

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-09, the author granting a module by hand

## What is actually true

`OwnerSiteDetailPage.tsx`'s module-grant form takes `moduleKeyInput` as free text — the owner types
`calendar` (or whatever key) by hand, from memory, with a caption above the field explaining what can
be written there. A typo produces a grant for a module key that does not exist, silently.

## Scope

- Replace the free-text module-key input with a dropdown of the actual known module keys.
- Once the input cannot produce an invalid key, remove the explanatory caption that exists only to
  compensate for free text ("what can be written here") — the UI gets simpler because the control now
  enforces what the caption used to have to explain.
- Source the option list from wherever the module keys are already known on the owner side (`23-65`'s
  own grant flow, or `IModuleEntryPointProvider`'s registered set on the backend — check whether the
  frontend already has or needs a way to ask for this list; if none exists yet, a small enough static
  list mirroring what `EnableModuleForSiteAsOwnerHandler` actually accepts is an acceptable interim
  answer, stated as such).

## Where this is likely to go wrong

- **The dropdown must not silently drop a module key an owner could legitimately grant.** Check what
  the backend handler actually accepts before finalizing the option list — a dropdown that is stricter
  than the API is a worse regression than the free-text field it replaces.

## Done when

- [ ] The module-key field is a dropdown sourced from the real set of grantable module keys, not free
      text.
- [ ] The now-unnecessary "what can be written here" caption is removed.
- [ ] Granting a module through the dropdown still reaches `EnableModuleForSiteAsOwnerHandler`
      correctly, proven by a test.
