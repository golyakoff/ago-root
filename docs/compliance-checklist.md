# Launch compliance checklist — `152-ФЗ`, kept until the first real tenant

`25-02`, opened 2026-09-06. **A working checklist, not an opinion about the law.** Every line says who
closes it, and lines marked **lawyer** are not ours to close however confident a reading looks.

## How to read this file

**Citations are for orientation, not advice** — the footing `personal-data.md` and
`processing-instruction-facts.md` already use. What is different here is that **the statutory claims
below were checked against sources on 2026-09-06 rather than recalled**, and the sources are listed at
the bottom. That distinction matters: an engineer's memory of an amended statute is exactly the thing
that is confidently wrong, and this file was drafted from memory first and then corrected against the
text — the corrections are noted where they happened, because they are the useful part.

The hard rule: **a line is ticked only when somebody can point at the artefact.** Not "we do that" —
*here is the document, here is the test, here is the screen.*

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
| A1 | The databases holding personal data run on machines in Russia | **blocked** — `25-01`. Fornex is out: the machine is *probably* in Russia (RIPE `country: RU`, `netname: RU-FORNEX`) and Fornex does not issue a document saying so | provider |
| A2 | A written confirmation of the datacentre location is on file | **not started**, closes with `25-01` and `24-07` | provider |
| A3 | Where backup copies live is recorded | **not recorded.** `adr/0050` says "the author's own machine" and nothing about where that is. Every artifact holds both databases and the MinIO objects | document |
| A4 | Every destination outside the deployment is listed, with what reaches it | **built** — `personal-data.md`, *Where it goes* (`24-08`) | — |
| A5 | What each of those vendors retains is known | **not established, and recorded as such** — it is each provider's own terms | lawyer |
| A6 | The Telegram relay's egress is recorded | **not recorded.** `adr/0070` routes it through the author's own personal endpoint and already calls that a gap "worth revisiting before any real paying tenant depends on Telegram" | document |

**A1 is the critical path.** Nothing else here matters if the machine is somewhere we cannot evidence.

---

## B. Telling the regulator

| # | Must be true | State | Who |
|---|---|---|---|
| B1 | The notification is filed with Roskomnadzor **before** processing starts | **not started.** Verified: art. 22 ч. 1 says *«Оператор до начала обработки персональных данных обязан уведомить уполномоченный орган»* | lawyer + document |
| B2 | **We are not exempt** | **confirmed, and this corrected a guess.** Exemptions 1–6 of art. 22 ч. 2 were **repealed effective 1 September 2022**. What remains is state security systems, processing done *entirely without automation*, and transport-security processing. None of them is us | — |
| B3 | What the notification says matches what the system does | Facts assembled — `processing-instruction-facts.md`, dated 2026-09-05 | lawyer |
| B4 | Whether a cross-border transfer notification is owed | **open.** Six channel providers receive message text on the tenant's own act | lawyer |

**B1 carries a sequencing question worth asking early:** it says *before processing starts*, and the
demo deployment has been processing whatever people typed into it since August. Whether that already
counts is a lawyer's call, and it is cheaper to ask now than after a first tenant.

---

## C. What we publish

| # | Must be true | State | Who |
|---|---|---|---|
| C1 | A policy on processing is published and reachable without an account | **half built.** `24-02` stores documents and versions, `24-03` links one from registration, `PolicyPage` renders it to somebody with no account. **The table ships empty** — mechanism yes, text no | document + lawyer |
| C2 | The published text is a lawyer's, not ours | **by design** — `adr/0114` made a document's text *data* precisely so a wording fix is one call, not a deploy | lawyer |
| C3 | The tenant agreement's processing clause is drafted from the system | **facts ready** — `processing-instruction-facts.md` | lawyer |
| C4 | A visitor is told who processes their data and on whose behalf | **built** — `16-04`: the tenant's own notice text and link, never AGO-authored | — |

---

## D. Consent — checked against the text, and one rule is newer than this project

**The rules on the form of consent changed on 1 September 2025.** Three of them bear directly on what
was built here, and one of them is why this section was rewritten rather than trusted:

- **Consent must be a separate document**, not bundled into another agreement.
- **Several purposes may not be combined in one consent.**
- **Pre-ticked boxes are prohibited outright** — consent requires an affirmative act.

| # | Must be true | State | Who |
|---|---|---|---|
| D1 | **No pre-ticked boxes anywhere** | **built, verified in code 2026-09-06.** Both checkboxes are created unticked in `contactCapture.ts`; nothing sets `checked` or `defaultChecked` anywhere in the widget | — |
| D2 | Consent is an affirmative act, never inferred from silence or continued use | **built** — a consent is recorded only when a box was rendered *and* ticked; the client sends `false` otherwise | — |
| D3 | **Purposes are not combined** | **built, and it now matches a rule we did not know about when we built it.** `24-05` gives the contact consent and the marketing consent **separate checkboxes**, and the marketing one is deliberately not `required` | — |
| D4 | Refusing an optional consent still lets the person use the service | **built and proven by a test whose whole point is this** — `ConsentGateDoesNotBlockConversationTests`. The gate attaches to handing over a phone or email, never to the conversation | — |
| D5 | The tenant is **not** asked to consent to processing their contract already requires | **built, as a decision** — `24-03` has no consent tick at all | — |
| D6 | What each consent was given *to* is producible — document, version, instant | **built** — `acceptance_records` (`24-01`, `adr/0111`) with `adr/0114`'s server-derived `v{n}` versions | — |
| D7 | **Each consent is a separate document in the sense the rule means** | **unverified, and this is the sharpest open question in this section.** Ours is a tick against a named, versioned document the tenant publishes. Whether that satisfies "отдельный документ" is exactly the determination an engineer must not make | lawyer |
| D8 | The consent's own content carries what the rule requires | **unverified.** The record holds subject, document key, version, instant, and narrow request context; the *substance* lives in the tenant's document text. Whether that text carries the required elements is a review of the text, not of the code | lawyer |
| D9 | Whether a new document version invalidates an existing acceptance | **open and deliberately unanswered** — `adr/0114` names it; today any past acceptance satisfies the gate | lawyer |
| D10 | Whether writing a `visitorId` to the visitor's device needs consent | **open** — `24-15` made the facts available for exactly this question | lawyer |

**One correction worth keeping, because it is the kind of mistake this file exists to catch.** The
first draft of this checklist asserted a general statutory ban on refusing service to somebody who
refuses consent. Checked: the **explicit** prohibition sits in **art. 11 (biometric data)**, not as a
flat general rule in art. 9. The general principle is real but derived rather than stated that
plainly — so D4 is a good engineering property and **not** a citation we should wave at anyone.

---

## E. The person's own rights

| # | Must be true | State | Who |
|---|---|---|---|
| E1 | Erasure works and can be shown to have worked | **built** — `16-02`, receipts in `erasure_records` (`24-13`, `adr/0112`) | — |
| E2 | The person's own data can be produced to them | **built** — `24-11`, per conversation and per visitor | — |
| E3 | **Blocking** — stop processing without destroying — exists | **built 2026-09-06** — `24-10`, `adr/0124`. It was the one statutory operation with no mechanism at all | — |
| E4 | What we cannot reach is stated rather than implied | **built** — `personal-data.md` says outright that `localStorage` on the visitor's device is the one store with **no erasure path of ours** | — |
| E5 | Rectification — correcting wrong data on request | **not examined**, which is its own small finding | document |

---

## F. Protection level and its measures

| # | Must be true | State | Who |
|---|---|---|---|
| F1 | The level is **determined in a document**, not assumed | **not started.** Checked against `ПП-1119`'s own inputs: *иные* categories of personal data, subjects who are **not** our employees, fewer than 100 000 of them, and **type-3 threats** give **УЗ-4**. УЗ-3 arrives at 100 000 subjects, or if type-2 threats are held to be actual | lawyer + document |
| F2 | The threat type is argued, not assumed | **the load-bearing input.** Type 3 means "no undocumented capabilities in system or application software". Arguing it is routine and is still a determination — and it is the single input that moves us from УЗ-4 to УЗ-3 | lawyer |
| F3 | An «акт определения уровня защищённости» exists, and a «модель угроз» after it | **not started** | document |
| F4 | The measures the level requires are implemented and evidenced | **cannot start before F1** | document |
| F5 | Access to personal data is limited and recorded | **substantially built** — RBAC throughout (`tenant-isolation.md`), `access_records` (`24-12`), reveal records (`adr/0123`) | — |
| F6 | The contact-visibility ladder is set, not merely built | **built, unset** — every account is on `Visible` until somebody changes it | document |
| F7 | Secrets are inventoried and rotatable | **built** — `secrets.md` plus `tools/secrets-audit.sh` (`24-14`), which fails on any secret the inventory does not name | — |
| F8 | The two committed-key findings are closed | **open** — `Webhooks:SecretEncryptionKey` is a committed literal serving the live deployment; the channel key is held correctly but **Breaking** to rotate with no re-encryption path | document |

---

## G. When something goes wrong

| # | Must be true | State | Who |
|---|---|---|---|
| G1 | There is a written incident procedure somebody has read | **built** — `runbooks/personal-data-incident.md` | — |
| G2 | Its deadlines are the ones in force | **verified 2026-09-06** — art. 21 ч. 3.1: **24 hours** to notify the regulator of the incident, its supposed causes and the supposed harm, **72 hours** for the results of the internal investigation. The runbook must be read against these two numbers | document |
| G3 | A leaked secret has a procedure | **built** — `runbooks/secret-rotation.md` | — |
| G4 | Backups exist, are pulled off the node, and a restore has actually been performed | **partly.** Taken and pulled with an age-checked status; `25-01` makes the first restore-and-read a Done-when, because a backup nobody has restored is a hope | document |

---

## H. Being somebody else's processor

| # | Must be true | State | Who |
|---|---|---|---|
| H1 | The split is decided and written | **built** — `adr/0076`: controller for our own account holders, processor on the tenant's instruction for visitors' conversation data | — |
| H2 | The operator's own basis — they registered with us, their employer is our counterparty | **open, and `adr/0076` does not resolve it.** Three readings, one of which supersedes that ADR | lawyer |
| H3 | The instruction clause states what art. 6 ч. 3 requires | **facts ready, clause not drafted** | lawyer |
| H4 | A tenant can point at something and refuse a processing purpose we added | **NO — the sharpest open item on this page.** The AI features are switched on by **AGO, deployment-wide**. Nothing reaches the vendor today because no key is set; the day one is, every tenant's closed conversations start going to an LLM vendor with nothing for a tenant to refuse. The author decided 2026-09-06 that this becomes a paid add-on, off by default, with its own accepted agreement - **filed as `25-04`**, which also records the finding that settles the shape: by art. 6 ч. 3 the basis must exist **for the visitor**, and by ч. 4 obtaining it is the **tenant's** obligation, not ours. So the tenant's acceptance of our terms is necessary and **not sufficient by itself**; the tenant declares a basis and we record the declaration without verifying it. Until `25-04` ships, red | built next |

---

## What a mistake costs, so the deadlines are not abstract

Fines rose sharply on **30 May 2025** (`420-ФЗ` of 30.11.2024). For a legal entity, checked
2026-09-06: processing without proper consent, or breaching the rules on obtaining it, **300 000 –
700 000 ₽**, and up to **1 500 000 ₽** on repetition. Failing to notify of a leak: **1 000 000 –
3 000 000 ₽**.

These are the ranges the sources give and they are here for scale, not as legal advice. The point is
the ordering: the cheapest line on this page to close is D1, and it is already closed; the most
expensive to get wrong are B1 and A1, and both are open.

---

## What this file is not

Not a substitute for the lawyer, and not a claim that the ticked lines are *sufficient* — only that
they are done. Most of what is green is green because Stage 24's mechanisms landed over two weeks; most
of what is not is documents and determinations, which take calendar time rather than engineering time.

**Two lines gate a launch outright:** A1 and B1.

## Sources checked 2026-09-06

- [`152-ФЗ` art. 9 — Согласие субъекта персональных данных](https://legalacts.ru/doc/152_FZ-o-personalnyh-dannyh/glava-2/statja-9/) — the wording *«конкретным, предметным, информированным, сознательным и однозначным»*
- [`152-ФЗ` art. 22 — Уведомление об обработке](https://legalacts.ru/doc/152_FZ-o-personalnyh-dannyh/glava-4/statja-22/) — notify before processing; exemptions 1–6 repealed 1 September 2022
- [`152-ФЗ` art. 21 — обязанности оператора при инциденте](https://legalacts.ru/doc/152_FZ-o-personalnyh-dannyh/glava-4/statja-21/) — the 24-hour and 72-hour deadlines
- [Consent rules from 1 September 2025 (ГАРАНТ.РУ)](https://www.garant.ru/article/1862510/) — separate document, no combined purposes, pre-ticked boxes prohibited
- [`ПП-1119` protection levels, explained](https://152fz.cyberosnova.ru/blog/urovni-zashchishchyonnosti-pdn) — the УЗ-4/УЗ-3 boundary and the documents that record the determination. **A secondary source**: the primary is [`ПП-1119` itself](https://base.garant.ru/70252506/)
- [КоАП art. 13.11 (КонсультантПлюс)](https://www.consultant.ru/document/cons_doc_LAW_34661/1f421640c6775ff67079ebde06a7d2f6d17b96db/) and [the 30 May 2025 increase](https://www.garant.ru/article/1862510/) — the ranges quoted above
