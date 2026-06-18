# Emote loadout UI improvement

| Field | Value |
|---|---|
| Slug | `emote-loadout-ui-improvement` |
| Status | `data-layer-validated` (2026-05-17) — Lua-side data plumbing complete (catalog read, equip write, soft-ptr texture resolution, OnUIDataSet refresh hook); BP visual layout next |
| Created | 2026-05-02 |
| Last updated | 2026-05-17 |
| Owner | Claude Code session + maintainer |
| Branch | TBD — see *Notes* (currently sharing `feat/first-unlock-emote-lvl10` with the sibling feature) |

---

## PoC complete — 2026-05-17

End-to-end override mechanism validated in-game. The R1/R2/R3 framing from the 2026-05-02 evening update is now superseded — the actual production mechanism is the routing-layer hook documented in ADR 0004's 2026-05-16 revision and the [tab routing learning](../learnings/customize-page-tab-routing-architecture.md).

**Production stack (working):**

- Cooked `WBP_OSPlusEmoteLoadout` (UserWidget parent in UE5.1 dev project) shipped via `OSPlus.pak` to `LogicMods/`. Class memory-resident via hard-class-reference on `ModActor` (BPModLoaderMod transitive load).
- Lua module `mod/OSPlus/scripts/emote_loadout.lua` hooks `WBP_Panel_StrikerCosmetics_C:SetActivePanel` via `RegisterCustomEvent`. When target is the native emoticons panel, constructs/caches our widget instance via `WidgetBlueprintLibrary:Create`, adds to `CosmeticsPanelSwitcher`, recursively calls `SetActivePanel(ourInstance)` (guarded). Data pushed via `OSPlus_SetContext` BP function.
- Native Skins / Goal Explosion sub-tabs untouched. Tab buttons, highlights, animations all native.
- Pattern documented as template: see [`docs/learnings/osplus-widget-integration-pattern.md`](../learnings/osplus-widget-integration-pattern.md).

## Data layer validated — 2026-05-17

**Read side (cheapest test the user asked for first):**

- Live `UIDataModel` reached via `FindFirstOf("PMUISubsystemBase").UIDataModel` (`Prometheus.lua` line 15211). `FindFirstOf("PMUIDataModel")` returns the CDO, not the live instance — *avoid*.
- Catalog containers exposed at `.UIDataModel.Catalog`:
  - `OwnedEmoticons` — `TArray<UPMEmoticonUIData>`, 282 entries on the test account.
  - `ReactionsByCharacterId` — `TMap<FName, UPMReactionsUIData>`, 21 entries (one per striker). Each value's `.Emoticons` is a 7-entry `TArray<UPMEmoticonUIData>` (the equipped loadout). **The live game has 7 slots per striker, not 8.**
- Container API confirmed (UE4SS 3.0.1; canonical reference: [`ue4ss-3.0.1-tarray-tmap-lua-api.md`](../learnings/ue4ss-3.0.1-tarray-tmap-lua-api.md)):
  - TArray: `arr:GetArrayNum()` for length, `arr[1..N]` 1-indexed. No `#`, no `:Num()` / `:Length()`.
  - TMap: `#tmap` for count, `tmap:ForEach(function(k, v) ... end)` for iteration. The `(k, v)` are `RemoteUnrealParam` wrappers — must `:get()` to unwrap before accessing fields.

**Write side:**

- Canonical equip path: `catalog:EquipEmoticonToSlot(Emote: UPMEmoticonUIData, Character: UPMCharacterUIData, SlotIndex: int32) → boolean` (`Prometheus.lua` line 9002). Validated in-game; the call returned `true` cleanly. UI-layer function — handles local state and backend roundtrip transparently.

**Striker-ID extraction (no binding cliff):**

- `characterUIData.DataAsset:GetIdentifierString() → FString` (`Prometheus.lua` line 10296). Returns strings in `"<Type>:<Name>"` format (e.g. `"CharacterData:CD_NimbleBlaster"`); `catalog.lua` strips the type prefix to match the bare `FName` keys in `ReactionsByCharacterId`.

**Display-data extraction (Lua → BP primitives, no binding wrappers needed):**

- Display name: `entitlement.DataAsset.InGameName:ToString() → FString` — direct FText field on `UPMEntitlementBaseData` (line 10285). No `FOdyUITextBinding` wrapper to fight.
- Icon: `entitlement.DataAsset.<IconField>` is a `TSoftObjectPtr<UTexture2D>`. Resolution goes through `UKismetSystemLibrary` (Conv non-blocking → LoadAsset_Blocking fallback). For characters, the IconField is `CharacterPortrait` (line 9013); for emoticons it's `Image` (line 10176). Full resolution pattern documented in [`ue4ss-3.0.1-tarray-tmap-lua-api.md`](../learnings/ue4ss-3.0.1-tarray-tmap-lua-api.md).

**Refresh-on-striker-switch ordering trap:**

The customize page fires `SetActivePanel` **before** `OnUIDataSet` on striker switch — `self_.UIData` inside `SetActivePanel` callback reads stale character data. Fix: hook both, but only push from `SetActivePanel` on first widget construction (no cached character yet); `OnUIDataSet` owns subsequent updates. Pattern documented in [`customize-page-tab-routing-architecture.md`](../learnings/customize-page-tab-routing-architecture.md).

## Decision — 2026-05-17: Path A (full replacement, BP-side binding reads)

Superseding the May 2 architectural-options block. Path B (hybrid) ruled out by the May 2 evening session's subobject-embedding wall finding. Path C (static catalog) rejected as fragile against Odyssey emote updates.

**Path A as implemented:** Lua reads the catalog (live UIDataModel) and pushes raw `UPMEmoticonUIData` / `UPMCharacterUIData` / `UPMReactionsUIData` UObjects into the cooked widget via BP-callable functions. The widget reads `Name` / `Icon` bindings *inside BP* (where they work natively, sidestepping the Lua-side reflection cliffs documented in [`ue4ss-3.0.1-bp-reflection-cliffs.md`](../learnings/ue4ss-3.0.1-bp-reflection-cliffs.md)). User actions flow back to Lua via pure-BP event functions Lua subscribes to with `RegisterCustomEvent`.

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

**Verdict so far:** `Low` for R1 (replace at the widget level); `Medium-High` for R2 (side-load OSPlus screen). **Tentative path-of-record: R2.** *(See **R1 vs R2 verdict — 2026-05-02 evening update** below.)*

**Confidence rationale.** Pass-1 closed the "what's the UI shape" question. Pass-2 *attempted* widget-level replacement (R1) and surfaced a hard blocker (the subobject-embedding wall in cooked `WBP_Panel_StrikerCosmetics`). Pass-2 then ran a community-priors check ([`docs/learnings/os-modding-community-priors.md`](../learnings/os-modding-community-priors.md)) which strongly negative-signals R1 as uncharted territory in OS modding. R2 (a side-loaded OSPlus screen, chat-pattern) sidesteps the wall entirely. The verdict moves from `Medium-High` to `High` for R2 if a Discord query in "Opening the Prometheus" returns no counter-evidence within ~48h; the verdict re-opens R1 only if the Discord returns a working widget-level technique we can adopt.

### R1 vs R2 verdict — 2026-05-02 evening update

**Summary.** R1 was the original ADR 0004 commitment (replace `WBP_Panel_StrikerEmoticons_C` inside the native customization page). The 2026-05-02 evening session attempted R1 via cooked-asset replacement — extracted the native uasset, cooked an OSPlus stub with the same path, packaged into a `_P` priority pak, patched the import table to point at `OdyWidget` (the native parent class) — and hit a `Serial size mismatch: Got 149, Expected 31` from the parent panel `WBP_Panel_StrikerCosmetics`. That parent records the *exact serialized byte size* of its embedded child's default-property block; replacement requires byte-compatible layout, which we cannot produce without the native source.

**The user surfaced** a methodological gap: OSPlus had been operating from "OS internal code is unexplored" when the community has demonstrably shipped mods. Triggered a community-priors investigation.

**Findings (full record at [`docs/learnings/os-modding-community-priors.md`](../learnings/os-modding-community-priors.md)):**
- 4 mods identified in the GameBanana OS UI category. 2 statically inspected via `UnrealPak -List`: Demon Drive Menu Restoration (211 files, all under `/Game/Prometheus/Maps/`, **zero widgets** — visual-asset replacement, not UI), UNIB Character Select + Pre Match (2 paks, one `.wem` each under `/Game/WwiseAudio/Media/`, **zero widgets** — pure audio swap). 2 inferred to be text-replacement (Skill Issue, UwUified) — technique class doesn't transfer to widget-tree work.
- **Not a single confirmed widget-tree replacement in OS public modding.** R1 is genuinely uncharted territory; the subobject-embedding wall we hit is consistent with no community workaround having been demonstrated publicly.
- **Two corollaries kept regardless**: pak `_P` suffix is one of *several* priority mechanisms (alphabetical-after-base also wins — relevant if OSPlus ever needs a non-`_P`-named pak). Path taxonomy: `/Game/Prometheus/Maps/EnvironmentArt/Lobby/...` and `/Game/Prometheus/Maps/MainMenuMap/MainMenuMap.umap` — `Maps/` is a non-obvious parent for environment art.

**Decision (path-of-record):** R2 — side-loaded OSPlus screen, chat-pattern, fresh top-level widget added to the viewport via Lua at the right lifecycle moment. No asset replacement, no embedding wall. The OSPlus screen acts as a unified hub that reads the native loadout (via `PMPlayerState.GetEquippedReactions()`) and writes back via the relay-canonical loadout — which the user explicitly required must seamlessly support both vanilla and OSPlus emotes equipped in any slot.

**Outstanding fast-close move (parallel, non-blocking):** post in the "Opening the Prometheus" Discord asking *"has anyone done widget-level replacement on OS — replacing a `WBP_*` that's embedded in a parent's `WidgetTree`? Or is the working pattern Lua injection + side-loaded widgets?"* If a working R1 technique surfaces, the verdict re-opens. If silence or "no", R2 is locked. Tomorrow's design work proceeds on R2 either way.

**ADR 0004 status:** queued for revision (currently `accepted` but committed to R1's `R-Hook` shape, which assumes widget-level replacement is feasible — which the evening session contradicted). Revision will be drafted as an ADR supersession in the same change that promotes R2 to a designed feature.

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
*(Stage 4 — Feature design. v1 scope locked 2026-05-17.)*

### v1 scope

Four features ship:

1. **Listing** — scrollable grid of every owned emote, rendered inside the OSPlus widget.
2. **Equip** — click an emote to assign it to a chosen slot (1–7). Replaces whatever was previously in that slot.
3. **Swap** — moving an equipped emote between slots, or replacing one equipped with another. Implemented in the widget as one or two `EquipEmoticonToSlot` calls depending on the gesture; same Lua handler as plain equip.
4. **Search** — BP-internal text box that filters the rendered grid by emote name. No Lua coupling — the widget reads each emote's `Name` binding and substring-matches against the query string. No new interface surface needed.

Filter chips (Cute / Meme / etc.) are *deferred to v1.1* — they need the OSPlus-side tag dictionary built first, plus a chunked push API to work around BP's no-nested-containers limit on `TMap<FName, TArray<FName>>`.

### v1 BP interface

Defined on `WBP_OSPlusEmoteLoadout`. Every function prefixed `OSPlus_` per the convention in [`osplus-widget-integration-pattern.md`](../learnings/osplus-widget-integration-pattern.md).

**Lua → Widget (data push).** BP-callable functions Lua invokes via `widget:OSPlus_<name>(args)`. BP graph implements with nodes that update the visible state.

- `OSPlus_SetStrikerContext(Character: UPMCharacterUIData, Reactions: UPMReactionsUIData)`
  - Called when the redirect fires (user navigated to a striker's Emote sub-tab) or when the player switches striker without leaving the page.
  - `Character` drives the header — BP reads `Character.Name` (a `FOdyUITextBinding`) to display the striker's display name.
  - `Reactions` drives the 7-slot equipped row — BP iterates `Reactions.Emoticons[1..7]` and reads each emote's `Name` + `Icon` bindings to render slot tiles.

- `OSPlus_SetOwnedEmotes(Emotes: TArray<UPMEmoticonUIData>)`
  - Called once after first redirect, and re-called if/when we subscribe to `Catalog.OnOwnedEmoticonsChanged` for live refresh.
  - BP builds the scrollable grid; reads `Name` + `Icon` on each entry.

**Widget → Lua (user-action events).** Empty pure-BP functions on the widget. Lua subscribes via `RegisterCustomEvent("OSPlus_<Name>", callback)` per the FUNC_Native: 0 selection rule. Widget graph calls them when the user takes the corresponding action.

- `OSPlus_OnEmoteEquipRequested(Emote: UPMEmoticonUIData, SlotIndex: int32)`
  - Fires when the user assigns an emote to a slot (whether the emote came from the catalog grid or another slot — same event).
  - Lua handler: `catalog:EquipEmoticonToSlot(Emote, currentCharacter, SlotIndex)`. On success, Lua re-calls `OSPlus_SetStrikerContext(...)` with the refreshed `Reactions` so the widget redraws.

**Widget-internal state (BP only).**

- Search query string (TextBox bound to a member variable; filter runs in BP graph).
- Selected/hovered emote, scroll position, modal preview state.

### Lua-side striker-context derivation

In the `SetActivePanel` redirect callback:

```lua
local character = parentPanel.UIData                            -- UPMCharacterUIData
local idStr = character.DataAsset:GetIdentifierString()         -- "CD_AngelicSupport"
local reactions
catalog.ReactionsByCharacterId:ForEach(function(k, v)
    if reactions then return end
    if k:get():ToString() == idStr then reactions = v:get() end
end)
widget:OSPlus_SetStrikerContext(character, reactions)
```

Owned-emote push happens once per Lua state on first redirect (or on `OnOwnedEmoticonsChanged` if subscribed):

```lua
local owned = catalog.OwnedEmoticons   -- TArray, 282 entries on the test account
widget:OSPlus_SetOwnedEmotes(owned)
```

### v1 UI requirements

**Surface.** Full body of the Emote sub-tab inside Cosmetics — whatever Slate gives the OSPlus widget. Design responsive, not fixed-pixel; the parent panel is what shapes the available area.

**Top-down regions.**

1. **Striker header (compact strip).** Small portrait + striker display name on the left. Optional secondary text on the right (e.g., "7 of 7 equipped").
2. **Equipped row.** Exactly 7 slot tiles in a horizontal row. Each tile shows the equipped emote's icon. Below each slot a small numeric label `1`–`7` (corresponds to the in-game hotkey). Empty slots show a `+` placeholder.
3. **Search bar.** Single-line text input spanning the row width. Placeholder "Search emotes…".
4. **Owned grid.** Scrollable uniform-tile grid of all owned emotes (~282 on a maxed account). ~10–12 columns depending on container width. Each tile shows icon + name.

**Tile states (reusable across equipped row + owned grid).**

| State | Trigger | Visual treatment |
|---|---|---|
| Default | resting | icon + name |
| Hovered | mouse over | light border / brightness bump |
| Selected | clicked | strong border / glow — only ONE tile selected at a time, anywhere |
| Equipped badge | owned-grid tile whose emote is currently equipped | small corner badge with the slot number (`1`–`7`) |

**Interactions.**

1. **Equip an emote.** Click a slot in the equipped row → it becomes selected (any prior selection clears). Click any emote tile in the owned grid → that emote equips to the selected slot, slot deselects, equipped-badge updates. Lua call: `OSPlus_OnEmoteEquipRequested(EmoteId, SelectedSlotIndex)`.
2. **Swap two equipped emotes.** No special swap UI — performed via two equip actions. Click slot A → click the emote currently in slot B (visible in the grid by its slot-2 badge) → it moves to A. Click slot B (now showing previous-A content) → click the original slot-A emote in the grid → it goes to B.
3. **Default slot fallback.** Clicking a grid tile with NO slot selected equips to slot 1. Smooths the "just try this emote" flow; optional.
4. **Search filter.** Typing in the search bar live-filters the owned grid via case-insensitive substring match on the tile's name. Empty query shows all tiles. No submit button; reactive on every keystroke.

**Data sources (Lua → widget).**

| Region | Source field |
|---|---|
| Header name | `OSPlus_SetStrikerContext.StrikerName` (FString) |
| Header portrait | `OSPlus_SetStrikerContext.StrikerIcon` (UTexture2D) |
| Equipped row | `OSPlus_SetStrikerContext.EquippedSlots[0..6]` (TArray<FOSPlusEmoteDisplay>, length 7) |
| Owned grid | `OSPlus_SetOwnedEmotes.OwnedEmotes` (TArray<FOSPlusEmoteDisplay>, length ~282) |
| Equip back to Lua | fire `OSPlus_OnEmoteEquipRequested(EmoteId: Name, SlotIndex: int32)` |

`FOSPlusEmoteDisplay` carries `Id` (Name), `Name` (String), `Icon` (Texture2D). The `Id` is what comes back through `OSPlus_OnEmoteEquipRequested` so Lua can resolve to the underlying UObject and call the engine's equip path.

**Open visual choices (your call — not load-bearing for the Lua side).**

- Color palette (suggest harmonizing with native OS customize page so OSPlus reads as "native+").
- Tile size, spacing, corner radius.
- Selected-state visual treatment (border color, glow, scale).
- Whether tile name shows always, on hover only, or as a permanent caption beneath icon.
- Whether the equipped row gets a section header ("Equipped Loadout") or stands alone.
- Empty-state copy if the search returns zero matches.

**Out of scope for v1 (deferred).**

- Filter chips (Cute / Meme / etc.) — needs the OSPlus tag dictionary first; see "v1.1 / later" below.
- Drag-and-drop equip — click-to-equip is the v1 pattern.
- Hover-tooltip previews — basic hover highlight only.
- Slot-clear / explicit unequip — equipping replaces; no empty action.
- Per-striker sectioning — owned grid is flat; striker context only affects the header + equipped row.

### v1.1 / later

- **Filter chips** (Cute / Meme / etc.) — needs the OSPlus tag table + a chunked push API: `OSPlus_BeginTagPush()` / `OSPlus_AddEmoteTag(EmoteId: FName, Tag: FName)` / `OSPlus_EndTagPush()` (BP doesn't allow `TMap<FName, TArray<FName>>` directly, so we push pairs and BP builds the structure internally).
- **Slot 8** — mockup had 8 slots; live game exposes 7. Adding an OSPlus-only 8th slot would need its own equip path beyond `EquipEmoticonToSlot`. Design decision deferred until v1 ships.
- **Slot clear / explicit unequip** — `OSPlus_OnEmoteUnequipRequested(SlotIndex)`. Not in mockup; deferred.
- **Live refresh on catalog changes** — subscribe to `Catalog.OnOwnedEmoticonsChanged` and `Catalog.ReactionsUIDataChanged` so the widget reflects state changes that originate outside OSPlus (battlepass tier-up unlocking a new emote, etc.).

---

### Current build handoff (2026-05-19)

This section is the short resume point for agents/chats. If it conflicts with older sections above, prefer this section and the live code in `mod/OSPlus/scripts/`.

**Runtime shape.**

- Lua module: `mod/OSPlus/scripts/emote_loadout.lua`.
- Metadata module: `mod/OSPlus/scripts/emote_metadata.lua`.
- Localization module: `mod/OSPlus/scripts/localization.lua`.
- Screen widget: cooked `WBP_OSPlusEmoteLoadout` mounted inside the native `WBP_Panel_StrikerCosmetics_C` Emote sub-tab via `RegisterCustomEvent("SetActivePanel")`.
- Tile widget: cooked `WBP_OSPlusEmoteTile`; filter chip widget exists in BP and is created by `OSPlus_AddFilterChip`.
- Lua/data-only iteration uses `deploy.ps1`; BP/widget changes still require UE cook + `ue-assets/package_logicmod.ps1`.

**Current Lua to BP API.**

- `OSPlus_SetStrikerHeader(StrikerName: String, StrikerIcon: String)`
- `OSPlus_BeginEquippedRow()`
- `OSPlus_AddEquippedSlot(SlotIndex: Integer, EmoteId: Name, EmoteName: String, EmoteIcon: String, Description: String, TagsPacked: String, SearchText: String, Source: String, VisualAssetPath: String)`
- `OSPlus_BeginOwnedGrid()`
- `OSPlus_AddOwnedEmote(EmoteId: Name, EmoteName: String, EmoteIcon: String, Description: String, TagsPacked: String, SearchText: String, Source: String, VisualAssetPath: String)`
- `OSPlus_BeginFilterChips()`
- `OSPlus_AddFilterChip(FilterKey: String, Label: String)`
- `OSPlus_SetSelectedEmoteDetails(EmoteName: String, Description: String, TagsDisplay: String, VisualAssetPath: String)`
- Widget-to-Lua event remains `OSPlus_OnEmoteEquipRequested(EmoteId: Name, SlotIndex: Integer)`.

**Working behavior.**

- Header, 7 equipped slots, owned grid, search, click-to-equip, drag owned-to-slot, and drag slot-to-slot swap are working.
- Static and animated native emotes render through one visual path. Lua pushes `VisualAssetPath`; BP uses the UObject brush/resource path so `UTexture2D` and `UAnimatedTexture2D` both render. Do not split static and animated UI branches unless this assumption is falsified by a probe.
- Filter chips are data-driven. `All` is fixed in Lua; configured priority chips from `data/emotes/catalog.json` render first, then every remaining distinct present tag is appended. `OSPlusTagFilterRow` stays the bound `HorizontalBox`, but it is wrapped in a horizontal `ScrollBox` named `OSPlusTagFilterScroll` so the row scrolls sideways rather than paging or wrapping. The scrollbar style is intentionally transparent. BP owns chip interaction: left-click selects a chip, left-clicking the active chip clears the filter, and left-drag scrolls the strip horizontally. `WBP_OSPlusEmoteLoadout` handles background strip drags by polling left-button state and applying mouse delta to the parent `ScrollBox`; `WBP_OSPlusFilterChip` handles drags that begin on a chip by polling `Button_41.IsPressed()` and notifying the loadout through its exposed-on-spawn `OwnerLoadoutTyped` reference. Lua only pushes chip data through `OSPlus_BeginFilterChips` / `OSPlus_AddFilterChip`; it must not hook tag mouse events, write `ActiveFilterKey`, or call `RefreshOwnedFilter()` because a chip was clicked. `WBP_OSPlusFilterChip` uses a dynamic-width `SizeBox` (min 44, max 148), `TextOverflowPolicy.Ellipsis`, `ButtonClickMethod.PreciseClick`, and runtime `HorizontalBoxSlot` padding so chips do not glue together or wrap long localized labels.
- Footer selected-emote text is bridged through `RegisterCustomEvent("OSPlus_OnEmoteSelected", ...)` for first-click updates, with the older `HandleSlotTileClicked` hook kept as backup. The current BP function populates name, description, and tag display text; Lua also attempts to set the preview square brush from the selected emote visual asset. If that preview path fails in-game, replace the preview square with the same unified emote visual widget used by tiles.
- The footer starts collapsed on widget/header refresh and is revealed by
  `OSPlus_SetSelectedEmoteDetails(...)` when the player selects an emote. This
  keeps the pre-selection state out of the way without asking Lua to own UI
  visibility. The reveal is currently a visibility transition, not a authored
  UMG animation.
- Footer selection no longer keeps the equipped-row frame in destination mode.
  The footer remains visible as inspection state, while destination treatment is
  reserved for transient drag feedback. The loadout widget polls
  `WidgetBlueprintLibrary.IsDragDropping()` from its tick path and toggles the
  equipped-row destination state only while a UMG drag operation is active. The
  equip-confirm flash clears the internal drag-destination flag before pulsing,
  so drop confirmation is not immediately stomped by the tick reset path.
- Every equip path in the widget calls `OSPlus_FlashEquipConfirm()` before
  firing `OSPlus_OnEmoteEquipRequested(...)`: owned-to-slot drop, slot-to-slot
  swap, direct equipped-slot destination click, footer quick equip, and footer
  picker choice. `OSPlus_FlashEquipConfirm()` owns the shared equip sound
  (`SFX_OSPlus_UI_Equip`) and the visual pulse, so drag/drop and button/picker
  equip paths stay consistent. The flash is a high-opacity hot-pink row pulse
  and resets itself shortly afterward through
  `OSPlus_ResetEquipConfirmVisual()` so the row returns to the default
  treatment instead of sticking pink.
- The footer slot picker is now hosted as a `WBP_OSPlusSlotPickerPopover`
  instance inside the old `OSPlusFavoriteStar` compatibility host. The parent
  keeps that host for existing visibility/geometry logic, but the popover owns
  the seven mini-card layout and thumbnail painting. `OSPlus_AddEquippedSlot`
  still calls `OSPlus_SetSlotPickerChoiceVisual(SlotIndex, VisualAssetPath)` on
  the loadout; that function now simply casts the hosted content to
  `WBP_OSPlusSlotPickerPopover` and delegates to
  `OSPlus_SetSlotVisual(SlotIndex, VisualAssetPath)`. The old inline graph that
  drilled through the host's child hierarchy has been removed.
- `WBP_OSPlusSlotPickerPopover` is a compiled reusable visual widget: root
  overlay, purple popover background, horizontal row, seven square mini cards,
  slot-number badges, and a public thumbnail setter that uses the same soft
  visual-asset path flow as the main emote tiles. The loadout parent still owns
  opening/closing, outside-click close, and the equip event because selected
  emote state belongs to the screen.
- The picker popover visual pass keeps the old loadout host as a non-visual
  anchor and lets the extracted popover own the chrome: rounded Slate-brush
  frame, dark inner panel, equal-width mini slot cards, compact number badges,
  and a small magenta accent lip. Horizontal spacing stays inside the equal
  seven-slot layout. The parent no longer maps click position to slot index
  from the popover geometry; slot choice is emitted by the popover/card
  dispatcher path.
- Slot picker clicks now use the reusable popover path instead of parent
  geometry hit testing. `WBP_OSPlusSlotPickerPopover` owns seven invisible
  `WBP_OSPlusSlotPickerCard` hit widgets (`OSPlusSlotPickerHitCard_1..7`);
  each card forwards `OnSlotCardChosen(SlotIndex)` to the popover
  `OnSlotChosen(SlotIndex)` dispatcher. The loadout binds the hosted
  `OSPlusSlotPickerPopover.OnSlotChosen` event, calls the existing
  `HandleSlotTileClicked(SelectedEmoteId, SlotIndex)` flow, then closes the
  picker host. This keeps slot-choice input inside the reusable widget while
  leaving selected-emote state and equip dispatch in the screen.
- Optional UI sound hooks are wired through
  `OSPlus_PlayOptionalUiSound(SoundPath)`. The helper loads a soft path,
  casts it to `SoundBase`, and plays it as a UI sound only when the asset
  exists; missing assets compile and remain silent. Current hook points are
  selected-emote click, tile hover, slot-picker open, and equip confirmation.
  Planned asset names:
  `/Game/Mods/OSPlus/UI/Sounds/SFX_OSPlus_UI_Click.SFX_OSPlus_UI_Click`,
  `/Game/Mods/OSPlus/UI/Sounds/SFX_OSPlus_UI_Open.SFX_OSPlus_UI_Open`,
  `/Game/Mods/OSPlus/UI/Sounds/SFX_OSPlus_UI_Equip.SFX_OSPlus_UI_Equip`, and
  `/Game/Mods/OSPlus/UI/Sounds/SFX_OSPlus_UI_Hover.SFX_OSPlus_UI_Hover`.

**Data ownership.**

- Cross-game emote metadata lives in `data/emotes/catalog.json`. It should stay reusable anywhere emotes appear, not tied to this screen.
- Priority filter chips are configured in `data/emotes/catalog.json` beside the reusable emote/tag metadata because chip ordering is an emote-domain browsing choice, not screen-local text. The runtime may append additional discovered tags after those configured priorities.
- Screen-specific localized UI text lives in `data/localization/screens/emote_loadout.json`.
- `deploy.ps1`, `build_dist.ps1`, and `dist/install.bat` copy `mod/data/**` into the game install/distribution.

**Localization constraints.**

- `localization.lua` is global infrastructure initialized from `main.lua`, not owned by this screen. It polls PMGameInstance language fields before Unreal/Kismet culture on startup, keeps a short startup probe alive so saved culture can settle, and hooks both `/Script/Prometheus.PMGameInstance:SetTextLanguage` and Unreal's `KismetInternationalizationLibrary` culture setters. Kismet culture is treated as a non-locking fallback because it can reflect the OS/user environment instead of the game's saved UI language during cold boot.
- In the `SetTextLanguage` callback, use the hook parameter as the authoritative new locale. Do not immediately re-read `GetTextLanguage()` during that callback; it returned stale `en` while the game was switching to `pt-BR`.
- Runtime polling remains active after startup and reads PMGameInstance only
  (plus `OSPLUS_LOCALE`) so missed/stale language-change hooks are corrected
  without letting Kismet/OS culture override the game's selected language.
- Existing safe localized paths: filter chip labels and any emote metadata fields pushed as Lua strings.
- Static widget text is pushed through cooked BP function `OSPlus_SetLocalizedText(SearchHint, EquippedHeading, OwnedHeading, EmptyTitle, EmptyKind, EmptyDescription, EquipLabel, FavoriteLabel)`. Direct Lua calls to UMG `SetText` / `SetHintText` crashed on UE4SS 3.0.1 due FText marshaling; do not reintroduce that fallback. Current BP wiring covers search hint, equipped heading, owned heading, footer empty state, Equip text, and favorite tooltip.

**Known next work.**

- Cook and package the updated `WBP_OSPlusEmoteLoadout` so the localized static text function reaches the game.
- Verify cooked filter-chip styling and horizontal tag scrolling after the next pak cook.
- Verify selected footer preview in-game; if the direct brush set is not enough, replace the preview square with the same unified emote visual widget used by tiles.
- If another screen needs this picker, reuse `WBP_OSPlusSlotPickerPopover`
  directly and bind its `OnSlotChosen(SlotIndex)` dispatcher from that screen.
  The parent screen should still own whatever selected item/loadout state is
  specific to that surface.
- Import the optional UI sound assets listed above. Missing assets are expected
  to remain silent, not fatal.
- Keep category/tag buttons dynamic from Lua metadata; no hardcoded tag list in BP.

---

## Outcome
*(Stage 6 — Land. Not started.)*

---

## Notes

- **Branch.** Currently sharing `feat/first-unlock-emote-lvl10` with the sibling Feature 2 (`custom-emotes-in-game-ui`). The branch name is now stale for this feature (the lvl-10 unlock condition is a Feature 2 concern). Open question for the maintainer: split into `feat/emote-loadout-ui` (this feature) + retain `feat/first-unlock-emote-lvl10` for Feature 2, or rename the existing branch and create a new one when Feature 2 starts. Will surface this on the next conversational checkpoint.
- **Sibling feature.** [`custom-emotes-in-game-ui`](./custom-emotes-in-game-ui.md) *(brief not yet drafted — pending Pass-2 B + C)*. The two features share ADR 0004 as ground; this one ships the menu-side, the sibling ships in-match render + relay broadcast + the first cooked OSPlus emote asset.
- **Probe vs experiment — methodology note (2026-05-02).** First draft of this Brief framed A1 as a separate readonly probe (hook UFunction, log fires). User correctly pointed out the question is behavioral, not observational — the cheapest answer is to just do the swap and watch what happens. Codified rule of thumb: *probes test what's there; experiments test what changes when you change it.* A0 was a probe (readonly observation of the live tree). A1 is an experiment (do the swap, observe persistence). The Brief was updated; if a comparable mis-framing recurs in another feature, this is worth promoting from Notes to a learning entry on Stage-3 methodology.
- **Pass-2 todo numbering** — A0 (probe) closed; A1 (experiment, this feature) is the next move. The original feature-1+feature-2 unified "Pass-2 A1 / A2 / A3" numbering from before the split is replaced by per-feature lettering (A1 here is *this* feature's swap experiment; the in-match render unknown that was previously called "Probe B" is owned by the sibling feature `custom-emotes-in-game-ui` once that Brief is drafted).
