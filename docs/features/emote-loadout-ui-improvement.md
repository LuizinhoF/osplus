# Emote loadout UI improvement

| Field | Value |
|---|---|
| Slug | `emote-loadout-ui-improvement` |
| Status | `framed` |
| Created | 2026-05-02 |
| Last updated | 2026-05-02 |
| Owner | Cursor agent + maintainer |
| Branch | TBD — see *Notes* (currently sharing `feat/first-unlock-emote-lvl10` with the sibling feature) |

---

## Brief
*(Stage 2 — Frame.)*

**Problem.** Native Omega Strikers' emote-loadout configuration UI (Cosmetics → Emote sub-tab inside the per-Striker customization page) is a flat, unsearchable grid that mixes every emote across every Striker into one alphabetically-implicit pile. With 100+ emoticons in the catalogue (and growing as Strikers ship), finding the one you want — especially the *new* one you just unlocked — is high-friction. There's no per-Striker grouping, no search, no preview-then-equip flow, and the equipped row mixes named slots without surfacing which key triggers which emote.

**Audience.** All current OSPlus users (returning veterans + retention-curve newcomers, per `docs/product.md`). The pain hits everyone who customizes their loadout, but the curve is steepest for veterans (who own more emotes and re-equip more often). It also paves the runway for Feature 2 (custom emotes), where the OSPlus-canonical loadout state must be configurable through *some* surface — without this UI, the parallel-layer story from ADR 0004 has no entry point.

**Wedge fit.** This is **infrastructure for the wedge**, not a wedge feature itself. Like chat: it doesn't move OSPlus' identity definition forward by itself, but it pays forward the parallel-cosmetic-layer pattern that every future OSPlus unlockable will use. ADR 0004 *Notes* makes the same observation about emote unlockables generally; this feature builds the first OSPlus-canonical configuration surface they live inside.

**Anti-goal check.** Reviewed against `docs/product.md`:

- ✅ *Doesn't disrupt the matchmaking lobby* — the customization page is a separate top-level screen reached via "Customize"; replacing the Emote sub-tab body doesn't touch lobby flow.
- ✅ *Doesn't compete with the native game* — the Skins / Goal Explosion sub-tabs stay native; only the Emote sub-tab body is replaced.
- ✅ *No paid cosmetics, no monetization* — this is a UI-only change; nothing is sold, nothing is gated by payment.
- ✅ *Cross-platform-portable* — runs through the same UMG / cooked-pak path the chat widget uses; no Steam-specific dependency.
- ⚠️ *Maintenance commitment* — explicit per ADR 0004: the Cosmetics → Emote sub-tab becomes ours. Odyssey patches affecting that sub-tab → potential breakage. Accepted.

**Loose success criteria.**

- A returning OSPlus user equipping an emote completes the flow without consulting the previous "where's the search bar?" state of the native UI — they find the emote, preview it, equip it, and move on.
- The 7 equipped slots are visible, labeled with their hotkey, and equippable via drag-and-drop or click-to-equip — whichever the maintainer prefers; the Brief picks one in *Out of scope*.
- Per-Striker grouping is visible at a glance (sectioned or filtered) so a player who knows "I want a Juliette emote" doesn't scan the whole catalogue.
- Native-emote-only loadouts persist correctly across uninstall/reinstall (since OSPlus owns the relay loadout but native is the seed and the fallback).

**Out of scope.**

- Custom OSPlus-cooked `PMEmoticonData` assets (separate feature — `custom-emotes-in-game-ui`).
- In-match emote rendering (native handles the wheel; we don't touch the modal yet).
- Cross-OSPlus-peer visibility for emote uses (Feature 2's V-Relay surface).
- Slots 8+ / OSPlus-dedicated wheel (deferred per ADR 0004 *What this rules out*).
- Other native-customization sub-tabs (Skins, Goal Explosion, Logos, Nameplates, Titles).
- Drag-and-drop slot reorder among the 7 equipped — *click slot, click new emote, replace* is the default unless feasibility surfaces a cheap drag pattern.

---

## Feasibility
*(Stage 3 — Discover. Pass-1 captured in [ADR 0004](../decisions/0004-emote-loadout-as-osplus-layer.md). Pass-2 in progress.)*

**Verdict so far:** `Medium` (provisional — A1 + A2 still pending).

**Confidence rationale.** Pass-1 (static analysis + maintainer-conversation) closed the "is the UI shape replaceable at all" question; Pass-2 is decomposing the replaceability into testable runtime questions, of which **A0 is closed** with high confidence and **A1 / A2 are open**. The verdict moves to `High` if A1 succeeds; to `Low` (or shelve) if A1 surfaces a hard blocker on the swap mechanism.

**Pass-2 unknowns:**

- ~~**A0** — sub-tab swap mechanism reliability (Cosmetics → Emote)~~ **Closed 2026-05-02.** The host page is `WBP_Menu_Striker_C`, the Cosmetics tab body is `WBP_Panel_StrikerCosmetics_C`, and sub-tab navigation is a `UWidgetSwitcher` named `CosmeticsPanelSwitcher` whose `ActiveWidgetIndex` selects between three native panels. Swap target is the Emote panel (`WBP_Panel_StrikerEmoticons_C`). The 7-slot equipped row is a hard-coded named-child list (`DropTile1..DropTile7`). Verified via runtime probe — see [`docs/learnings/customization-screen-widgetswitcher-architecture.md`](../learnings/customization-screen-widgetswitcher-architecture.md) and [`docs/engine/widgets.md` → "Customization screen"](../engine/widgets.md#customization-screen-home-hub--customize). **Verdict input: High.**

- **A1 — swap mechanism + reinstall reliability** *(pending — collapses two questions into one experiment)*. (1) Does the engine accept us replacing a child of `CosmeticsPanelSwitcher` at all? (2) Does the swap survive the player navigating away and back? **Cheapest experiment is the swap itself, Lua-only, no cook, no pak.** Re-order or replace `CosmeticsPanelSwitcher`'s native children at runtime via UE4SS reflection (`SetChildAt` / `RemoveChild` + `InsertChildAt`), e.g. swap the Skins and Emoticons panels, then navigate the customization page (Affinity → Cosmetics → Emote → Cosmetics → Skins → exit page → re-enter via home hub) and observe whether the swap persists. If existing children swap cleanly and persist → mechanism works, install pattern is "one-shot at page-construct"; proceed to cook a stub OSPlus widget. If they don't persist → narrow with a hook on the likely re-render UFunction (tab-activate / `WBP_Panel_StrikerCosmetics_C.Construct`), determine whether re-application on every fire is viable. If they don't accept at all → engine validates child types; re-evaluate (likely shifts to `R-Replace` of the Cosmetics panel body wholesale, expanding scope).

- **A2 — equip write-back into native compatibility** *(pending — depends on A1's verdict)*. ADR 0004 commits to OSPlus relay being canonical for the 7-slot loadout, with a one-time bootstrap read of `PMPlayerState.GetEquippedReactions()`. Open question: does the player's equipped emote *render correctly in the in-match wheel* if OSPlus owns the loadout state but never writes through to native? A2's predecessor in Feature 2 (custom emotes) re-checks the in-match render path; for *this* feature, the simpler test is "equip a native emote in the OSPlus UI, queue a match, do native UE wheel buttons 1–7 still resolve to the equipped emotes?" If the in-match wheel reads from native state instead of OSPlus state, we either accept that behavior (vanilla emotes in vanilla slots remain vanilla-bound) or commit to an in-match hook now (collapsing Feature 1 + Feature 2 partially). Probably surfaces in Pass-2.

**Assumptions (named, not buried):**

- `UWidgetSwitcher.SetChildAt` (or equivalent) is reachable from Lua via UE4SS reflection — *unverified*. Worst case: swap by `RemoveChild` + `AddChildAt` with a constructed-from-pak widget instance.
- The host page (`WBP_Menu_Striker_C`) is constructed *once per session* and not torn down on every customization-page exit — *unverified*. If it's torn down, our swap install needs `NotifyOnNewObject(WBP_Menu_Striker_C)` instead of a one-shot.
- The OSPlus widget can scrape the player's native loadout via `PMPlayerState.GetEquippedReactions()` at first launch (B-Seed in ADR 0004) — *partially verified*. The function exists; calling it from Lua needs a Pass-2 test.
- Click-to-equip / drag-and-drop interactions inside our cooked widget don't fight the native input mode (page is keyboard/gamepad-navigable in the native UI) — *unverified*. Chat already handles a similar input-mode dance; the pattern carries.

**Evidence trail.**

- 2026-05-02 — probe A0 run on the live game: 479 live `UserWidget` instances enumerated; tree-dump of the customization page identified the verified hierarchy. Throwaway probe (`mod/OSPlus/scripts/probe_subtab_a0.lua`) deleted in the same change as this Brief lands. Output captured to `UE4SS.log [01:54:10]`.
- 2026-05-01 — ADR 0004 accepted with full options-considered analysis. Locks the parallel-layer architecture and rules out cross-writing to Prometheus.

**Promoted findings.**

- [`docs/learnings/customization-screen-widgetswitcher-architecture.md`](../learnings/customization-screen-widgetswitcher-architecture.md) — verified widget tree + UE4SS-3.0.1 probe-methodology corollaries (`GetFullName` parsing). New canonical-doc section in [`docs/engine/widgets.md`](../engine/widgets.md).
- ADR 0004 *Notes* — earlier `bHideFromEnemyTeam` mistake recorded so the next agent doesn't reach for it; mirror in [`docs/learnings/native-reaction-showemoticon-pmemoticondata.md`](../learnings/native-reaction-showemoticon-pmemoticondata.md).

**Recommended Stage 5 path:** `thin slice first`. The Lua-only swap experiment in A1 *is* the first slice — it answers feasibility and the install-pattern question simultaneously without spending a cook cycle. Second slice: cook a stub OSPlus widget (Border + TextBlock — "OSPlus loaded here") into `OSPlus.pak` and perform the production swap, displacing `WBP_Panel_StrikerEmoticons_C`. Third+ slice: the actual UI content — search bar, per-Striker grouping, preview-then-equip flow, equipped 7-slot row with hotkey labels.

---

## Design
*(Stage 4 — Feature design. Not started — gated on Pass-2 A1 + A2 closing and sign-off.)*

---

## Outcome
*(Stage 6 — Land. Not started.)*

---

## Notes

- **Branch.** Currently sharing `feat/first-unlock-emote-lvl10` with the sibling Feature 2 (`custom-emotes-in-game-ui`). The branch name is now stale for this feature (the lvl-10 unlock condition is a Feature 2 concern). Open question for the maintainer: split into `feat/emote-loadout-ui` (this feature) + retain `feat/first-unlock-emote-lvl10` for Feature 2, or rename the existing branch and create a new one when Feature 2 starts. Will surface this on the next conversational checkpoint.
- **Sibling feature.** [`custom-emotes-in-game-ui`](./custom-emotes-in-game-ui.md) *(brief not yet drafted — pending Pass-2 B + C)*. The two features share ADR 0004 as ground; this one ships the menu-side, the sibling ships in-match render + relay broadcast + the first cooked OSPlus emote asset.
- **Probe vs experiment — methodology note (2026-05-02).** First draft of this Brief framed A1 as a separate readonly probe (hook UFunction, log fires). User correctly pointed out the question is behavioral, not observational — the cheapest answer is to just do the swap and watch what happens. Codified rule of thumb: *probes test what's there; experiments test what changes when you change it.* A0 was a probe (readonly observation of the live tree). A1 is an experiment (do the swap, observe persistence). The Brief was updated; if a comparable mis-framing recurs in another feature, this is worth promoting from Notes to a learning entry on Stage-3 methodology.
- **Pass-2 todo numbering** — A0 (probe) closed; A1 (experiment, this feature) is the next move. The original feature-1+feature-2 unified "Pass-2 A1 / A2 / A3" numbering from before the split is replaced by per-feature lettering (A1 here is *this* feature's swap experiment; the in-match render unknown that was previously called "Probe B" is owned by the sibling feature `custom-emotes-in-game-ui` once that Brief is drafted).
