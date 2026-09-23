# 26-72 · «Разбивка по тегам» is not on the phone

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ago-console/src/pages/TagBreakdownReportPage.tsx`,
  `ago-console/src/api/conversationsApi.ts` and `ago-console/src/realtime/protocol/types.ts` against
  `ago-android` `main` at `b099282`, with the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own `MyNumbers -- "⋮ · site:configure" --> TagStats`.

## Found

The third of the five reports `26-58` decided to port: what these conversations are actually about,
by tag — and, inseparably, **how much of the window is tagged at all**. `26-70` builds the overflow
this hangs off.

## What is actually true today, confirmed against real code

- `ago-console/src/App.tsx:386` → `TagBreakdownReportPage`, drawn at `consoleNav.ts:192`, gated
  `site:configure`.
- The read is `GET /api/v1/conversations/tag-breakdown-report` (`conversationsApi.ts:568`), **both
  bounds optional** (`TagBreakdownReportParams`, `:556`), server-side thirty-day default.
- **The response is not just a list of tags** (`types.ts:506`). It carries
  `totalConversationCount`, `taggedConversationCount` and `percentageTagged | null`, their three
  `previous*` counterparts, and `byTag`.
- `TagBreakdownBucketDto` (`types.ts:482-491`) is `tagId`, `tagName`, `conversationCount`,
  `convertedCount`, `notConvertedCount`, `recordedCount`, `conversionRate | null` — the same
  `null`-not-`0` rate convention `26-71`'s bucket uses.
- **Two statements on that page are load-bearing, not garnish**, and the DTO's own remarks say so:
  - the **coverage banner** — `taggedConversationCount / totalConversationCount (percentage)`,
    rendered above `byTag` every time (`TagBreakdownReportPage.tsx:288-292`), with its own
    "unknown" branch when `percentageTagged` is `null`. This is "the honesty check this whole report
    exists to keep visible".
  - the **multi-tag note** (`:311`): `byTag`'s counts **do not sum** to `totalConversationCount`,
    because a conversation with two tags counts once per tag.
- The coverage figures get the same previous-window comparison the other reports have (`:297-301`).
- The same three client-side date presets as the conversion report (`:230-238`), and the same
  `Conversation.Forbidden` / `Analytics.InvalidRange` / generic failure branching (`:131-135`).

### What the mockup does and does not say

The mockup names this destination («По меткам») and its gate as a graph node and an overflow edge,
and **draws no frame for the screen itself**. The layout below is scoped from the data shape plus
`scope-inventory.md` §5's suggestion; the coverage figures are what actually make the stat-card half
of that suggestion true here, and `byTag` is the one table.

## Scope

One promise: **«Разбивка по тегам» shows what this site's conversations were about in a chosen
window, and how much of the window is tagged at all.**

1. A `TagBreakdownApi` port in `:core:domain` and a Ktor adapter in `:core:network`, on the existing
   `apiBaseUrl`, built the way `ConversationsApi`/`KtorConversationsApi` are.
2. A new entry in Аналитика's overflow («По меткам»), gated `site:configure`, one level deep with
   the same `BackHandler` contract `26-70` establishes.
3. Default window on first composition, range taken from the response.
4. **Coverage first, as stat cards**: tagged of total plus the percentage, with its own "unknown"
   state when `percentageTagged` is `null`, and the previous-window comparison beside it.
5. **The multi-tag note renders wherever `byTag` does.** A reader must not be left to infer that the
   rows do not add up to the total.
6. `byTag` as one horizontally-scrollable table — tag name, conversations, converted, not converted,
   rate — with a `null` rate rendering its own value rather than `0%`.
7. The three presets port as a chip row; `Analytics.InvalidRange` keeps its own message, everything
   else is a refusal with a retry (`26-59`).

## Out of scope

- **The overflow menu itself** — `26-70`.
- **Applying, creating or editing a tag.** Tag management is `tagsApi.ts`'s own surface in the
  console and a different promise entirely; this screen is a read.
- **Any chart**, per `26-57`'s own stated rule.

## Done when

- [ ] An operator holding `site:configure` reaches «По меткам» from Аналитика's overflow and sees the
      window's tags with no interaction.
- [ ] Coverage (tagged of total, and the percentage) is on the screen above the tag rows, every time,
      with a distinct state when the percentage is unknown.
- [ ] The "rows do not sum to the total" note renders wherever the tag rows do.
- [ ] A tag whose rate is `null` shows its own value, never `0%`.
- [ ] Each of the three presets produces the range the response then echoes back.
- [ ] An invalid range renders its own distinct message.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device, in both light and dark, against a window with tagged conversations
      and against one with none tagged at all.
