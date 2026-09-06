# Launch compliance checklist — `152-ФЗ`, kept until the first real tenant

`25-02`, opened 2026-09-06. **This file is a working checklist, not an opinion about the law.** Every
line says who closes it, and lines marked **lawyer** are not ours to close no matter how confident a
reading looks.

## How to read this file, and its one hard rule

**Citations here are for orientation, not advice** — the same footing `personal-data.md` and
`processing-instruction-facts.md` already use. This file was assembled by an engineer from what the
repository establishes plus a reading of the statute's shape. **The statute changed materially in
2025, and a recollection of amendments is exactly the kind of thing that is confidently wrong.** Where
this file says *lawyer*, it means the line cannot be closed by reading code.

The hard rule: **a line is only ticked when somebody can point at the artefact.** Not "we do that" —
*here is the document, here is the test, here is the screen.* That discipline is the whole reason this
file exists rather than a conversation.

| Mark | Meaning |
|---|---|
| **built** | The mechanism exists in this codebase and something proves it |
| **document** | Needs a document written, signed or obtained — not code |
| **lawyer** | Needs a lawyer's determination; an engineer's reading is not enough |
| **provider** | Needs a paper from whoever hosts the machine |

---

## A. Where the data physically sits

| # | Must be true | State | Who |
|---|---|---|---|
| A1 | The databases holding personal data run on machines in Russia | **blocked** — `25-01`. Fornex is out: the machine is *probably* in Russia (RIPE `country: RU`) and Fornex does not issue a document saying so | provider |
| A2 | A written confirmation of the datacentre location is on file | **not started**, closes with `25-01` and `24-07` | provider |
| A3 | Where backup copies live is recorded | **not recorded.** `adr/0050` says "the author's own machine" and nothing about where that machine is. Every artifact holds both databases and the MinIO objects | document |
| A4 | Every destination outside the deployment is listed, with what reaches it | **built** — `personal-data.md`, *Where it goes* (`24-08`): six channel providers, the visitor's own mail provider, the LLM vendor, and the SMS gateway that does not exist | — |
| A5 | What each of those vendors retains is known | **not established, and honestly recorded as such** — it is each provider's own terms. A tenant who needs it gets it from the provider they chose to connect | lawyer |
| A6 | The Telegram relay's egress is recorded | **not recorded.** `adr/0070` routes it through the author's own personal endpoint, which that ADR already calls a gap "worth revisiting before any real paying tenant depends on Telegram" | document |

**A1 is the critical path.** Nothing else on this page matters if the machine is somewhere we cannot
evidence.

---

## B. Telling the regulator

| # | Must be true | State | Who |
|---|---|---|---|
| B1 | The notification of intent to process personal data is filed with Roskomnadzor **before** processing starts | **not started** | lawyer + document |
| B2 | What the notification says matches what the system actually does — purposes, categories, means | The facts are assembled: `processing-instruction-facts.md` answers the seven things art. 6 ч. 3 requires, dated and sourced | lawyer |
| B3 | Whether any cross-border transfer notification is owed | **open.** Six channel providers receive message text on the tenant's own act. Whether that is an onward transfer, a processing-on-instruction, or neither is precisely the determination this file must not guess at | lawyer |

**B1 has a sequencing consequence worth stating plainly:** it is *before processing starts*, and the
demo deployment has been processing data typed by whoever tried it. Whether that already counts is a
lawyer's call, and it is better asked now than after a first tenant.

---

## C. What we publish

| # | Must be true | State | Who |
|---|---|---|---|
| C1 | A policy on processing personal data is published and reachable without an account | **half built.** `24-02` stores documents and their versions, `24-03` links one from registration, and `PolicyPage` renders it to somebody with no account. **The table ships empty** — the mechanism exists, the text does not | document + lawyer |
| C2 | The published text is a lawyer's, not ours | **by design.** `adr/0114` made a document's text data precisely so a wording fix is one call, not a deploy — which is what makes "build the mechanism now, have a lawyer validate the text after" work | lawyer |
| C3 | The tenant agreement's processing clause is drafted from the system, not from memory | **facts ready** — `processing-instruction-facts.md`, dated 2026-09-05 | lawyer |
| C4 | A visitor is told, at the widget, who processes their data and on whose behalf | **built** — `16-04`: the tenant's own notice text and link, carried by the widget, never AGO-authored | — |

---

## D. Consent, and the traps in it

This is the section the author asked for by name. Each line names what the trap actually is.

| # | Must be true | State | Who |
|---|---|---|---|
| D1 | **No pre-ticked boxes anywhere** | **built and verified 2026-09-06.** Both consent checkboxes are created unticked (`contactCapture.ts`), and nothing in the widget sets `checked` or `defaultChecked` | — |
| D2 | Consent is a separate, deliberate act — not inferred from silence, inaction, or continuing to use the product | **built** — a consent is recorded only when a box was rendered *and* ticked; the client sends `false` otherwise | — |
| D3 | **Refusing an optional consent still lets the person use the service** | **built and proven by a test whose whole point is this**: `ConsentGateDoesNotBlockConversationTests`. The gate attaches to handing over a phone or email, never to the conversation | — |
| D4 | A second purpose is a second, independently refusable control | **built** — the marketing checkbox is deliberately not `required`, so it can be refused while the first is given | — |
| D5 | The tenant, registering with AGO, is **not** asked to consent to processing their contract already requires | **built, and it is a decision rather than an omission** — `24-03` deliberately has no consent tick. A consent that cannot be refused without losing the service is not freely given, so adding one would have been *wrong*, not merely redundant | — |
| D6 | What each consent was given *to* can be produced afterwards — which document, which version, when | **built** — `acceptance_records` with the document version (`24-01`, `adr/0111`), and `adr/0114`'s server-derived `v{n}` versions are quotable | — |
| D7 | Whether a **new version** of a document invalidates an existing acceptance | **open and deliberately unanswered** — `adr/0114` names it; today any past acceptance satisfies the gate | lawyer |
| D8 | Whether writing a `visitorId` to the visitor's device needs consent, or is necessary to the service they asked for | **open** — `24-15` made the facts available for exactly this question | lawyer |
| D9 | The consent form itself meets whatever formal requirements are in force | **unverified.** There are rules on the *form* of consent, and this file will not guess at their current text | lawyer |

---

## E. The person's own rights

| # | Must be true | State | Who |
|---|---|---|---|
| E1 | Erasure on request works and can be shown to have worked | **built** — `16-02`, with receipts in `erasure_records` (`24-13`, `adr/0112`) | — |
| E2 | The person's own data can be produced to them | **built** — `24-11`, per conversation and per visitor | — |
| E3 | **Blocking** — stop processing without destroying — exists | **built 2026-09-06** — `24-10`, `adr/0124`. It was the one statutory operation this system had no mechanism for | — |
| E4 | What the system cannot reach is stated rather than implied | **built** — `personal-data.md` says outright that `localStorage` on the visitor's own device is the one store with **no erasure path of ours at all** | — |
| E5 | Rectification — correcting wrong data on request | **not examined.** Nothing here has looked at it, which is its own small finding | document |

---

## F. Protection level and the measures under it

| # | Must be true | State | Who |
|---|---|---|---|
| F1 | The protection level is *determined*, in a document, not assumed | **not started.** The author's reading is УЗ-3 or УЗ-4, on the basis that no financial or medical data is held. That is a determination with inputs — category of data, whether subjects are staff, how many, and the threat type — and it is written down in an act, not decided in conversation | lawyer + document |
| F2 | A threat model exists | **not started** | lawyer + document |
| F3 | The measures the determined level requires are implemented and evidenced | **cannot start before F1** | document |
| F4 | Access to personal data is limited and recorded | **substantially built** — RBAC throughout (`tenant-isolation.md`), `access_records` for boundary-crossing reads (`24-12`, `adr/0113`), `contact_reveals`/`contact_phone_reveals` for unmaskings (`adr/0123`) | — |
| F5 | The contact-visibility ladder is actually sold and set, not merely built | **built, unset** — `23-11`/`23-12`. Every account is on `Visible` until somebody changes it | document |
| F6 | Secrets are inventoried and rotatable | **built** — `secrets.md` plus `tools/secrets-audit.sh` (`24-14`), which fails on any secret the inventory does not name | — |
| F7 | The two committed-key findings are closed | **open.** `Webhooks:SecretEncryptionKey` is a committed literal serving the live deployment (`secrets.md`'s own open finding); the channel key is held correctly but is **Breaking** to rotate with no re-encryption path | document |

---

## G. When something goes wrong

| # | Must be true | State | Who |
|---|---|---|---|
| G1 | There is a written procedure for a personal-data incident, and somebody has read it | **built** — `runbooks/personal-data-incident.md` | — |
| G2 | The notification deadlines in it are the ones actually in force | **unverified against the current text** | lawyer |
| G3 | A leaked secret has a procedure | **built** — `runbooks/secret-rotation.md`, including the interim procedure for the finding at F7 | — |
| G4 | Backups exist, are pulled off the node, and a restore has actually been performed | **partly** — taken and pulled with age-checked status; `25-01` makes the first restore-and-read a Done-when, because a backup nobody has restored is a hope | document |

---

## H. Being somebody else's processor

| # | Must be true | State | Who |
|---|---|---|---|
| H1 | The split is decided and written: who is controller for whom | **built** — `adr/0076`: AGO is controller for its own account holders, processor on the tenant's instruction for visitors' conversation data | — |
| H2 | The operator's own basis — they registered with us, but their employer is our counterparty | **open, and it is the one `adr/0076` does not resolve.** Three readings, one of which supersedes that ADR | lawyer |
| H3 | The instruction clause states the seven things the statute requires | **facts ready, clause not drafted** — `processing-instruction-facts.md` | lawyer |
| H4 | A tenant can point at something and refuse a processing purpose we added | **NO, and this is the sharpest open item on this page.** The AI features are switched on by **AGO, deployment-wide**. Nothing reaches the vendor today because no key is set — but the day one is, every tenant's closed conversations start going to an LLM vendor with nothing for a tenant to refuse. The author decided 2026-09-06 that this becomes a paid add-on, off by default, with its own accepted agreement; until that ships, this line is red | built next |

---

## What this file is not

It is not a substitute for the lawyer, and it is not a claim that the ticked lines are sufficient — only
that they are *done*. Twenty-odd lines here are green because the mechanisms landed over the last two
weeks; the ones that are not green are mostly documents and determinations, and those are the ones that
take calendar time rather than engineering time.

**The two that gate a launch outright** are A1 (a machine we can evidence) and B1 (telling the
regulator before processing starts). Everything else can be worked in parallel.
