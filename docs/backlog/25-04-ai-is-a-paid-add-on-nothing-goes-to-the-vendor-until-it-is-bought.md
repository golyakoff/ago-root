# AI is a paid add-on, and nothing reaches the vendor until a tenant has bought it and accepted its terms

- **Stage**: 25
- **Status**: ready
- **Depends on**: `22-07` for the add-on machinery, `24-01`/`24-02`/`24-03` for accepting a document
- **Decision**: the author's, 2026-09-06 — every choice below is recorded, not inferred

## Goal

The two AI features are off until a tenant buys them, and buying them is a deliberate act with an
accepted agreement behind it — so no tenant's conversations ever reach an LLM vendor because AGO
turned a key.

## What is actually true today, and why this is urgent rather than tidy

`24-08` found it: **the AI switch is AGO's, deployment-wide.** `ChatModule` registers the real
YandexGPT client when an API key and a folder id are present and an `Unconfigured*` one otherwise.
No key is set in any overlay, checked 2026-09-05, **so nothing reaches the vendor today**.

The day one is set, every tenant's closed conversations begin going to an LLM vendor for
categorisation and every tenant's operators can draft replies from one — **without any tenant choosing
it and with nothing for a tenant to point at and refuse.**

`docs/compliance-checklist.md`'s line **H4** is red because of this, and it is the sharpest red line on
that page: *a processor adding a processing purpose and a sub-processor on its own initiative is
precisely what a processing instruction exists to constrain.*

## What the law actually requires here, checked 2026-09-06

**Art. 6 ч. 3:** *«Оператор вправе поручить обработку персональных данных другому лицу **с согласия
субъекта персональных данных**, если иное не предусмотрено федеральным законом»* — and the operator
stays answerable to the subject for what that other person does.

**Art. 6 ч. 4:** *«Лицо, осуществляющее обработку персональных данных по поручению оператора, **не
обязано получать согласие** субъекта»*.

Applied to this system through `adr/0076`: the **tenant** is the operator for a visitor's conversation
data and **AGO is the processor**. Sending that conversation to an LLM vendor is processing entrusted
one step further, so the basis has to exist **for the visitor**, and by ч. 4 obtaining it is the
**tenant's** obligation, not ours.

**So the tenant's acceptance of our terms is necessary and is not sufficient by itself.** It settles
our side — they instruct, we execute, they answer to their own customers. It does not create the
visitor's basis, and a checklist that treated it as if it did would be wrong in the direction that
costs money.

## The decisions, all taken by the author on 2026-09-06

1. **A separate paid add-on**, not part of a higher tier. The module machinery already exists —
   `22-07`/`adr/0125` grants a module a quantity across the product boundary through the outbox, and
   `enabled_modules` already carries per-site enablement. This is a third module beside calendar and
   FAQ, not a new mechanism.
2. **Off by default, for everyone, always.** Including for tenants who never look at the setting.
3. **One acceptance for the whole add-on**, not one per feature. Reply-draft and categorisation are
   the same disclosure — *this vendor sees conversation text* — and splitting them would ask a tenant
   to reason about a difference that does not change what leaves the deployment.
4. **AGO writes the agreement**, because it is **our** agreement with the tenant. This is not the
   `16-04` boundary: that one forbids AGO writing the *tenant's* words to *their* visitors, which
   still holds. Words we say to our own counterparty are ours to write. A draft is below; **a lawyer
   reviews it before it is ever published.**
5. **The tenant declares they have a basis for their visitors' data reaching the vendor; we record the
   declaration and do not verify it.** By ч. 4 that obligation is theirs. Recording it means that when
   somebody asks *"on what basis did this conversation reach a vendor"*, there is a dated answer with
   a name against it instead of a shrug.
6. **Only conversations from the moment of enabling.** The archive is not re-processed. The visitors
   in those conversations wrote before this purpose existed, and reaching back would be exactly the
   retroactive widening the instruction rules exist to prevent — at the price, accepted knowingly, that
   a tenant sees less value on day one than their history could give.

## Scope

- A module the tenant can buy and enable, off by default, reusing `22-07`'s machinery rather than a
  parallel one.
- **Enabling requires accepting a document** — `24-02` stores it and its versions, `24-01` records the
  acceptance with the version accepted, `24-03` already makes a document required for a subject kind.
  Nothing new is needed except the row and the text.
- **The tenant's declaration is a distinct recorded fact**, not folded into the acceptance: accepting
  our terms and asserting a basis about somebody else are two statements, and a later reader must be
  able to tell which was made.
- **A cut-off instant is stored**, and both AI paths refuse anything before it. The categoriser reads
  closed conversations in the background, so this is the one place where "off" is not enough — a job
  that already ran must not walk backwards through the archive.
- The register and the checklist follow: `personal-data.md`'s *Where it goes* row for the LLM vendor
  stops saying the switch is AGO's alone, and H4 stops being red.

## Out of scope

- **Collecting the visitor's own consent for this purpose.** The author chose the declaration shape
  instead, and `24-05`'s mechanism already exists if that changes. Adding a third visitor checkbox is
  its own item and its own conversation about conversion.
- Pricing. Commercial, and it lives in `ago-business`.
- Any change to what the two AI features do once enabled.

## Done when

- [ ] With the module disabled — which is every tenant until they act — **nothing reaches the vendor**,
      proven by a test that fails if the client is constructed at all.
- [ ] Enabling is refused until the current version of the agreement is accepted, and the acceptance
      names the version.
- [ ] The tenant's declaration is recorded as its own fact, with who made it and when.
- [ ] A conversation closed **before** the cut-off is never categorised, proven against the background
      job rather than against the handler.
- [ ] `personal-data.md` and `docs/compliance-checklist.md` H4 are updated to what is then true.

## Draft of the agreement text — **not legal text, a starting point for the lawyer**

Written to be corrected, not published. It says plainly what happens, because a tenant who cannot tell
what they agreed to has not agreed to anything.

> **Обработка переписки с использованием ИИ — дополнительное соглашение**
>
> 1. Подключая этот модуль, вы поручаете AGO передавать текст переписки ваших посетителей стороннему
>    поставщику ИИ-сервиса для двух целей: подсказки оператору при составлении ответа и автоматической
>    категоризации завершённых диалогов.
> 2. Передаётся текст сообщений диалога. Не передаются: контактные данные, вложения, сведения об
>    операторах и любые данные других арендаторов.
> 3. Передача начинается с момента подключения модуля и распространяется только на диалоги, созданные
>    после него. Ранее завершённые диалоги не передаются.
> 4. Поставщик указан в вашей консоли и может быть заменён с предварительным уведомлением; замена
>    поставщика даёт вам право отключить модуль без потери оплаченного периода.
> 5. Вы остаётесь оператором персональных данных ваших посетителей. Подключая модуль, вы подтверждаете,
>    что у вас есть законное основание для передачи их данных указанному поставщику. AGO это основание
>    не проверяет и не заменяет.
> 6. Отключить модуль можно в любой момент. С момента отключения передача прекращается; ранее
>    переданное у поставщика удаляется на его условиях, которые AGO не контролирует.
>
> **Открытые вопросы для юриста:** достаточно ли пункта 5 как формы заявления, или основание должно
> называться явно; нужно ли назвать поставщика в самом тексте, а не в консоли; и что должен говорить
> пункт 6 о сроках у поставщика, если сами эти сроки нам неизвестны (`personal-data.md` фиксирует их
> как *не установленные*).

## Open questions

- **Whether point 5 is enough as a form of declaration**, or the basis must be named. A lawyer's.
- **What happens to a tenant who disables the module** — the vendor's own retention is *not
  established* (`personal-data.md`), so point 6 currently promises only what we control. Whether that
  is acceptable to say out loud is the same lawyer's call.
