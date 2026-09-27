# extend API-boundary shape validation to the remaining ago-console readers

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-41` (done), `23-99` (done) — the mechanism and the decision both exist.
- **Decision**: none open. `23-41` chose reading 3 (validate at the API boundary) as the standard and
  `23-99` built the mechanism (`shapeGuard.ts`). This item is the mechanical rollout of that decided
  standard, split out per rule 15 so each reader group lands green rather than one PR touching ~35
  files.

## Why this exists

`23-41` established that every API reader should validate the shape it was promised and reject a
mismatch as a typed, localized error — so a contract breach between two independently-versioned
backends (`adr/0012`) is an ordinary caught error, never a rendered blank page. `23-41` itself landed
only the incident's own reader (the calendar `/me/tenancies` reader) plus the shell-critical
`/me/tenancies` pair and the localized `shape.mismatch` surfacing. The rest of the console's readers
are still unvalidated, and each one is the same latent trap: an absent required field renders as a
false empty state (or throws) rather than as an honest error.

## The remainder

Readers in `ago-console/src/api/` that do **not** yet import `shapeGuard`:

`aiAddOnApi, assignmentPenaltyApi, attachmentsApi, billingApi, cannedResponsesApi,
channelDeliveriesApi, channelIdentitiesApi, contactDetailsApi, conversationsApi, documentsApi,
downloadUsageApi, emailChannelApi, faqKnowledgeBaseApi, installationApi, maxChannelApi, modulesApi,
notesApi, offlineAutoReplyApi, operatorInvitesApi, operatorTeamApi, ownerApi, personsApi,
replyDraftApi, siteAttachmentStorageApi, siteConsentDocumentsApi, siteExportsApi, siteSuspensionApi,
sitesApi, tagsApi, telegramChannelApi, visitorRestrictionsApi, vkChannelApi, widgetConfigApi`.

Per `23-99`'s bound, this does **not** mean a schema on every response indiscriminately: the reading
reaches a reader where a missing field and a genuinely empty result render identically. A single object
whose absence throws or renders visibly wrong is already loud and does not need the guard. Each reader
is judged against that test rather than converted mechanically.

Also on the chat side: chat readers surface failures via `problemDetails.ts` / `ApiProblemError`, and
`TenanciesError` is currently swallowed by `PermissionsProvider` — establish the localized
`shape.mismatch` surfacing there too, matching the calendar side landed in `23-41`.

## Split guidance

This is not one PR. Group readers by screen/feature so each PR is one promise that lands green
(rule 15) — e.g. channels together, billing/usage together, operator-team/invites together. Each PR
adds the guard where absence-looks-empty holds, adds a boundary test (happy path + one missing field +
the localized surfacing), and runs the full `ago-console` set including `npm run ux-gate`.

## Done when

- [ ] Every reader in the list above where absence renders as a false empty state validates its
      promised shape and rejects a mismatch as a typed, localized error — or is explicitly recorded as
      out of scope (loud-on-absence) with a one-line reason.
- [ ] The chat-side `shape.mismatch` is surfaced localized rather than swallowed.
- [ ] Each landing PR runs `npm run typecheck`, `npm run lint`, `npm test`, `npm run ux-gate` green.
