# Native emoticon panel data model — what OSPlus's replacement widget consumes

| Field | Value |
|---|---|
| Date | 2026-05-16 |
| Area | re |
| Tags | ui, emoticon, pm-ui-data-model, ody-widget, osplus-emote-tab-rework, native-data-model |
| Status | confirmed |

## Symptom

Designing the OSPlus emote-tab-rework feature: the cooked replacement widget needs to render every striker's emote catalog, the player's equipped 7-slot loadout, ownership/visibility filters, sort orders, search, and so on. Open question: does it reinvent the data model end-to-end, or can it consume the existing native PMUIDataModel that the native emoticon panel already uses? Cooking duplicate state-management infrastructure would be wasteful and risks drift from the wire format ADR 0002 commits us to.

## Root cause / findings

Static extraction of cooked `WBP_Panel_StrikerEmoticons` (`tools/_bin/uassetgui/UAssetGUI.exe tojson`) and a NameMap read revealed the native panel's entire surface — data sources, mutation APIs, filter/sort helpers, lifecycle events, and widget tree composition. OSPlus's replacement widget consumes the same data model unchanged; only the UI layer is OSPlus.

**Data sources (consume directly):**

- `PMUIDataModel.Catalog` — master emoticon catalog. Array of EmoticonData. **Account-bound** — same list across all strikers, the player owns emotes via their account, not via individual strikers. Accessed via `GetPMUIDataModel().Catalog` chain (NameMap shows `GetPMUIDataModel`, `GetUIDataModel`).
- `ReactionsByCharacterId` — `Map<CharacterId, Reactions>`. **Per-striker EQUIPPED loadout, NOT a per-striker catalog.** Every striker can equip any account-owned emote; this map keys each striker's currently-equipped 7-slot loadout by CharacterId (so switching to Drek'ar's customize page shows Drek'ar's equipped row, Asher's shows Asher's). The catalog above is the same across all strikers. **Correction 2026-05-17:** an earlier version of this learning framed `ReactionsByCharacterId` as the "per-striker grouping the mockup needs" — that was wrong. Per-striker tagging in the mockup (the "Drek'ar emotes" filter chip) is **OSPlus-side categorical metadata we maintain**, not a partition of the native catalog.
- `CharacterId`, `CharacterUIData` — striker context, passed in via `NewUIData` to the panel. The UIData object is a `UPMUIData_Character_C` whose inheritance chain (`UPMCharacterUIData` → `UPMEntitlementUIData`) carries the actual fields. Access path for the striker's display name: `panel.UIData.Name.InitialValue:ToString()` — `Name` is an `FOdyUITextBinding` on `UPMEntitlementUIData`, `.InitialValue` is the wrapped `FText`. See [type-stubs learning](./ue4ss-type-stubs-as-canonical-source.md) for the binding-wrapper pattern.

**Mutation API (call from the OSPlus widget for equip/unequip/reorder):**

- `EquipEmoticonToSlot(slot, emoticonAssetId)` — equip an emoticon to a specific slot.
- `SwapEmoticonSlots(slotA, slotB)` — swap two equipped slots.

These are the canonical mutation entry points. Wire format / replication / persistence are handled inside these calls — OSPlus doesn't touch them, which means wire compatibility is free for v1.

**Hard-coded constraints (respect, don't fight):**

- `GetNumEmoticonsToEquip` returns **7** at the runtime layer. Matches the wire-format constraint (`PMReactionIds.Emoticons` is `Array<FName>` length 7) already documented. The 7-slot constraint is consistent across data, wire, and UI layers — adding slot 8+ requires changes at every layer, not just UI. Deferred to a future feature.
- The native equipped row is a hard-coded named-child list: `DropTile1..DropTile7` inside `EmoticonEquippedContainer` (a HorizontalBox). Not a dynamic array. OSPlus's widget can either reuse the same naming (lets us reuse native drag-drop logic if we keep `WBP_EmoticonDragTile` / `WBP_EmoticonDropTile`) or define its own.

**Existing filter/sort helpers (reuse, don't reinvent):**

- `IsHidden`, `IsOwnedByEntitlement` — boolean predicates per-emoticon. The native panel already uses these for filtering; OSPlus surfaces them as user-facing filter chips.
- `HelperApplyFilter(emoticon) → ShouldShow` — generic filter helper.
- `SortEntitlementFunc(emoticonA, emoticonB) → ABeforeB` — sort by ownership status (owned first).
- `SortEmoticonListFunc` — general sort order.

The native panel was already filtering and sorting internally — just not exposing UI controls. The OSPlus mockup's search bar, filter chips, and sort dropdown are wiring these existing predicates to user-facing surfaces, not building new logic.

**Lifecycle events (handle in the OSPlus widget):**

- `OnUIDataSet(NewUIData)` — the data injection path. Fires when `SetUIData` is called with new striker context. The handler should populate the widget from `NewUIData.CharacterId`, `NewUIData.CharacterUIData`, etc. **This is separate from `OnPanelActivated`** — see the customize-page tab routing learning.
- `OnEmoticonsChanged(AddedEmoticons, RemovedEmoticons)` — fires when the equipped loadout changes. OSPlus subscribes to refresh the equipped row.
- `OnInitialized` — UMG construction event. Native panel uses this for one-time setup.

**Widget tree composition (informs the OSPlus widget's structure):**

- `EmoticonsTileView` — UTileView for the catalog grid. OSPlus's widget will have an equivalent (UTileView or UScrollBox + UGridPanel — design choice).
- `EmoticonEquippedContainer` — HorizontalBox with `DropTile1..DropTile7` named children.
- `WBP_EmoticonDragTile` / `WBP_EmoticonDropTile` — individual tile widgets with drag-and-drop machinery. **OSPlus can reuse these** by referencing them from its cooked widget, which avoids reimplementing drag-drop. Alternative is custom tile widgets if the OSPlus mockup needs richer hover/preview behavior than the native tiles support.

## What this means for the OSPlus replacement widget

The cooked OSPlus widget must:

1. **Implement `Interface_WBP_Panel`** — provide `OnPanelActivated()`. Minimum interface contract.
2. **Implement `OnUIDataSet(NewUIData)`** — receive striker context, query `PMUIDataModel.Catalog` and `ReactionsByCharacterId[CharacterId]` to build the displayed lists.
3. **Inherit from OdyWidget** — same base class the native panels use. Required for `SetUIData` plumbing.
4. **Render the OSPlus mockup UI** — search bar, filter chips (All / Favorites / per-striker / categories / Recent), sort dropdown, sectioned grid (per-striker section from `ReactionsByCharacterId[CharacterId]`, general section from the residual `Catalog`), preview footer, 7-slot equipped row.
5. **Wire UI controls to existing helpers** — search filters by name match plus `HelperApplyFilter`; filter chips by combinations of `IsOwnedByEntitlement`, `IsHidden`, and category metadata; sort dropdown by `SortEntitlementFunc` / `SortEmoticonListFunc`.
6. **Call native mutation APIs** — equip clicks call `EquipEmoticonToSlot`; drag-drop reorders call `SwapEmoticonSlots`. Wire format / persistence handled natively.
7. **Subscribe to `OnEmoticonsChanged`** to refresh the equipped row when the player equips elsewhere or via gameplay.

The OSPlus widget is a **UI layer** on top of an unchanged data model. No new persistence, no new state, no new wire-format. v1 deliverable scope locked.

## Lesson

For "what does this panel actually do under the hood" questions, the NameMap of a cooked WBP is a complete enumeration of the widget's surface: data properties, custom UFunctions, event names, bound delegates, widget tree composition, referenced assets. Reading the NameMap before designing a replacement reveals every public API and internal helper, making it obvious which parts to reuse and which parts to replace.

For OSPlus specifically: **OSPlus features default to "additive UI surface on top of unchanged native data model."** If a feature's design requires changes to native data state, that's a real architectural commitment (own wire format, persistence, etc., see ADR 0002 / 0004's S-Relay decision). UI-only features should never require it.

## Related

- ADR 0004 (revised 2026-05-16): [`docs/decisions/0004-emote-loadout-as-osplus-layer.md`](../decisions/0004-emote-loadout-as-osplus-layer.md) — the emote loadout feature this data model serves
- Routing layer: [`docs/learnings/customize-page-tab-routing-architecture.md`](./customize-page-tab-routing-architecture.md) — how the OSPlus widget gets activated via SetActivePanel hook
- API for the hook: [`docs/learnings/ue4ss-registerhook-vs-registercustomevent.md`](./ue4ss-registerhook-vs-registercustomevent.md)
- Native emote dispatch (in-match wheel, separate concern): [`docs/learnings/native-reaction-showemoticon-pmemoticondata.md`](./native-reaction-showemoticon-pmemoticondata.md)
- Customize screen widget tree: [`docs/learnings/customization-screen-widgetswitcher-architecture.md`](./customization-screen-widgetswitcher-architecture.md)
- Source JSON (gitignored scratch): `scratch/WBP_Panel_StrikerEmoticons.native.json`
