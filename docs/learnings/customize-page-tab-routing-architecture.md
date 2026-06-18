# Customize-page tab routing goes through `SetActivePanel`, not the widget switcher

| Field | Value |
|---|---|
| Date | 2026-05-16 |
| Area | re |
| Tags | ui, customize-page, tab-routing, interface-wbp-panel, set-active-panel, register-custom-event |
| Status | confirmed |

## Symptom

ADR 0004 originally framed the OSPlus emote sub-tab override as a widget-tree replacement problem: replace `WBP_Panel_StrikerEmoticons_C` inside `CosmeticsPanelSwitcher` with our cooked widget. Multiple iterations of probing the widget switcher (SetActiveWidgetIndex, SetActiveWidget, RemoveChild/AddChild, all with invalidation triplets) showed UMG-side mutations succeed but Slate never reflects them. We then dragnet-hooked twelve native UMG/UPanelWidget functions — `SetVisibility`, `SetRenderOpacity`, `AddChild`, `RemoveChild`, etc. — and zero of them fire when a user clicks a sub-tab button. The switch mechanism is somewhere else entirely from where the widget tree lives.

## Root cause / mechanism

Static extraction of the cooked Widget Blueprint assets (`tools/_bin/uassetgui/UAssetGUI.exe tojson`) revealed the routing layer. The NameMap of `WBP_Panel_StrikerCosmetics` exposes custom UFunctions (`SetActivePanel`, `SetActivePanelFromArgs`, `SetActiveTab`, `SetActiveWidget`) and an interface (`Interface_WBP_Panel`) that is the actual control flow.

**The complete call chain:**

```
User clicks sub-tab button (WBP_TabHeader_IconAndTextItem.TabHeaderButton)
  → fires native OnButtonClickedEvent delegate
  → bound delegate handler inside the tab-header item fires its OnClicked
  → WBP_TabHeaderGroup_IconAndText listens, updates ActiveTabHeader,
    fires its own OnActiveHeaderChanged(TabId Name) multicast delegate
  → WBP_Panel_StrikerCosmetics has a bound handler (OnCosmeticTabChanged)
  → Handler switches on the TabId Name ("skins" / "emoticons" / "goalexplosions")
  → Each case calls self:SetActivePanel(<corresponding sub-panel ref>) — pure BP UFunction
  → SetActivePanel performs the display switch internally and (presumably)
    calls panel:OnPanelActivated() via the Interface_WBP_Panel contract
```

**Same pattern at the level above:** the host page `WBP_Menu_Striker_C` also implements `SetActivePanel` for routing between the top-level Affinity / Overview / Cosmetics tabs. Both observation confirmed by RegisterCustomEvent — clicking the Cosmetics top-level tab fires `SetActivePanel` on `WBP_Menu_Striker_C`, then clicking a sub-tab fires `SetActivePanel` on `WBP_Panel_StrikerCosmetics_C`. The Interface_WBP_Panel routing pattern is reused at every hierarchy level in this UI tree.

**Key facts about the contract:**

- `Interface_WBP_Panel` declares exactly one function: `OnPanelActivated`. It's a callback fired when a panel becomes active. No `SetActivePanel`, `SetUIData`, or anything else on the interface.
- `SetActivePanel(panel)` is a *private* function on each routing widget (the parent panel that hosts sub-panels), not part of the interface.
- `SetUIData(NewUIData)` / `OnUIDataSet` is the **separate** data-injection path. Different from activation. Not part of Interface_WBP_Panel — appears to come from the OdyWidget base class.
- Tab IDs are Names (`"skins"`, `"emoticons"`, `"goalexplosions"`), not indices. The routing dispatches on Name equality, not array position.
- `WBP_TabHeaderGroup_IconAndText.Headers` is an ArrayProperty of `S_IconAndTextHeaderEntry` structs — the tab strip is data-driven. Adding a fourth tab is theoretically just an array extension plus routing wire-up.

## Validation

Hooked `WBP_Panel_StrikerCosmetics_C:SetActivePanel` via `RegisterCustomEvent` (see related learning on the API choice) and confirmed:

- Three clicks on three sub-tabs each fire the hook exactly once with `cls = WBP_Panel_StrikerCosmetics_C` and `arg[2] = <expected sub-panel reference>`.
- Recursively calling `self_:SetActivePanel(otherPanelRef)` from inside the callback (recursion-guarded) successfully redirects the display: clicking Skins or Goal Explosion now visually shows the Emoticons panel content. Tab button highlights stay on the originally-clicked tab because those are managed at the tab-header layer (separate concern).

The recursive-call redirect is the production override mechanism. To slot in an OSPlus widget instead of the native Emoticons panel: cook the OSPlus widget (implementing `Interface_WBP_Panel`), ship as a LogicMods pak, and from the SetActivePanel hook callback, when arg[2] is the native Emoticons panel, recursively call `self_:SetActivePanel(osplus_widget_ref)`.

## Striker-switch ordering trap (added 2026-05-17)

When the player **switches to a different striker** from inside the customize page (the avatar selector at the top), the engine fires events in this surprising order:

1. `SetActivePanel(<currently-active-sub-panel>)` on `WBP_Panel_StrikerCosmetics_C` — fires *first*, with the parent panel's `UIData` still pointing at the **previous** striker.
2. Engine updates `WBP_Panel_StrikerCosmetics_C.UIData` to the newly-selected striker.
3. `OnUIDataSet(NewUIData)` fires — the BP-implementable callback exposed by `UOdyWidget` (see `OdyUI.lua` line 779).

**Consequence:** any RegisterCustomEvent hook on `SetActivePanel` that reads `self_.UIData` to derive striker context will read **stale data** during a striker switch. The right state only arrives via `OnUIDataSet` afterwards. Reading `self_.UIData` inside `SetActivePanel` is only safe on the *initial* customize-page open (when there is no previous striker) and on **re-clicks of the same sub-tab** (UIData hasn't changed).

**Fix pattern (used in `mod/OSPlus/scripts/emote_loadout.lua`):**

- Hook **both** `SetActivePanel` and `OnUIDataSet` via `RegisterCustomEvent` (both are pure-BP — `SetUIData` itself is native on OdyWidget and not catchable via RegisterCustomEvent).
- In the `SetActivePanel` callback, only push initial striker context if no cached character exists for the OSPlus widget instance (first-visit case where UIData is correctly set already).
- In the `OnUIDataSet` callback, always re-push striker context — this is the authoritative update path during striker switches.

This avoids a one-frame flash of the previous striker's name/icon/equipped slots when the user clicks a different striker while on a substituted sub-tab.

## Lesson

Three transferable rules:

1. **For "how does this UI switch" questions, find the routing function, not the widget tree.** UMG widget switchers / panel widgets are visual containers; the routing logic that drives them lives in BP graphs as custom UFunctions on the parent widget. Static extraction (UAssetGUI tojson + NameMap read) reveals these custom functions in seconds, and a single RegisterCustomEvent hook validates the entire upstream chain transitively.

2. **`Interface_WBP_Panel + SetActivePanel(panel)` is the canonical OS UI routing pattern.** It's used at multiple hierarchy levels (top-level customize tabs, sub-tabs within Cosmetics). Future panel-substitution work — additional sub-tabs in other contexts, custom OSPlus screens that need internal routing — should default to implementing this pattern rather than inventing a new one. The contract is minimal (one function: OnPanelActivated) and the routing function on the host is the chokepoint to hook.

3. **The separation of concerns matters.** `SetActivePanel` switches *what's displayed*; `SetUIData` / `OnUIDataSet` *injects data*. These are different code paths. OSPlus's replacement widget must handle both — `OnPanelActivated` for "you're now visible, refresh anything time-sensitive," and `OnUIDataSet` for "here's your striker context, build the UI from this." Don't conflate them.

## Related

- ADR 0004 (revised 2026-05-16): [`docs/decisions/0004-emote-loadout-as-osplus-layer.md`](../decisions/0004-emote-loadout-as-osplus-layer.md)
- API choice: [`docs/learnings/ue4ss-registerhook-vs-registercustomevent.md`](./ue4ss-registerhook-vs-registercustomevent.md)
- Data model the replacement widget consumes: [`docs/learnings/emoticon-panel-data-model.md`](./emoticon-panel-data-model.md)
- Prior (now superseded in its prescriptive details): [`docs/learnings/customization-screen-widgetswitcher-architecture.md`](./customization-screen-widgetswitcher-architecture.md) — the verified widget tree it documents is still correct; the implication that the switcher's active-child mechanism drives display is wrong (switcher is just visual; SetActivePanel does the routing).
- Extracted cooked assets (gitignored scratch): `scratch/WBP_Panel_StrikerCosmetics.cosmetics-parent.json`, `scratch/Interface_WBP_Panel.json`, `scratch/WBP_TabHeaderGroup_IconAndText.json`, `scratch/WBP_TabHeader_IconAndTextItem.json`, `scratch/WBP_Panel_StrikerEmoticons.native.json`
