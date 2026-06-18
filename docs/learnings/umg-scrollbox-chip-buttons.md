# UMG ScrollBox Chip Buttons

| Field | Value |
|---|---|
| Date | 2026-05-22 |
| Area | ue-editor |
| Tags | `umg, scrollbox, widget-blueprint, button, filter-chips` |
| Status | `confirmed` |

## Symptom

Filter chips inside the emote-loadout horizontal tag strip rendered with no visual gap, long localized tag names spilled into neighboring chips, and behavior became hard to reason about once selection lived partly in Lua hooks and partly in Blueprint widget events.

## Root Cause

`WBP_OSPlusFilterChip` needed bounded dynamic sizing and explicit text overflow, but the larger issue was ownership drift. Lua was hit-testing widgets, writing `ActiveFilterKey`, calling `RefreshOwnedFilter()`, and configuring the ScrollBox while BP also had `OnChipClicked` and filter state. That split made right-click/left-drag bugs opaque and violated the UI-reactive-state boundary.

## Fix

In the UE project asset `/Game/Mods/OSPlus/UI/WBP_OSPlusFilterChip`, clear fixed width behavior, keep bounded dynamic sizing (`min_desired_width = 44`, `max_desired_width = 148`, height around `28`), set `LabelText` to no-wrap + `TextOverflowPolicy.Ellipsis` + `ClipToBounds`, and keep `Button_41` visible, not focusable, clipped, and configured for precise click/tap. In `WBP_OSPlusEmoteLoadout.OSPlus_AddFilterChip`, set the returned `HorizontalBoxSlot` padding so runtime-created chips have real spacing.

BP owns strip behavior. `WBP_OSPlusFilterChip` fires `OnChipClicked(FilterKey)` on normal left-click. `WBP_OSPlusEmoteLoadout.HandleFilterChipClicked` toggles `ActiveFilterKey` to `""` when the active chip is clicked again, otherwise sets it to the clicked key, then calls `RefreshOwnedFilter()`. Lua owns only the data push (`OSPlus_BeginFilterChips`, `OSPlus_AddFilterChip`) and localized labels; it must not hook UMG mouse events, hit-test chip children, write `ActiveFilterKey`, or poke ScrollBox runtime properties for chip interaction.

For drag-to-scroll, follow the owned-emote grid's input split: left-click selects, right-click drag scrolls. In `WBP_OSPlusEmoteLoadout`, poll while right mouse is down, check whether the pointer is under `OSPlusTagFilterRow`, then scroll the row's parent `ScrollBox` horizontally from the mouse delta. This keeps chip selection and strip dragging separate enough that no click-suppression flag is needed in the selection path. A previous attempt to make left-click both select and drag by polling `Button_41.IsPressed()` inside each chip caused ownership and event-consumption problems; leave that path disconnected.

## Lesson

For horizontally scrollable chip rows, keep UI-reactive behavior in BP and data in Lua. A chip should be scroll-box-friendly through bounded width, explicit text overflow, precise click behavior, runtime slot padding, and an input model that does not overload one mouse button with both selection and drag. Avoid Lua mouse hooks for widget gestures; once both Lua and BP can change the same UI state, bugs stop having an obvious home. If Python's normal `WidgetBlueprint.WidgetTree` property is protected, source widget subobjects are still loadable by object path, e.g. `/Game/Mods/OSPlus/UI/WBP_OSPlusFilterChip.WBP_OSPlusFilterChip:WidgetTree.Button_41`.

## Related

- Files: `docs/features/emote-loadout-ui-improvement.md`, UE asset `/Game/Mods/OSPlus/UI/WBP_OSPlusFilterChip`
- Prior learnings: `docs/learnings/ue-cook-additional-asset-dirs.md`
