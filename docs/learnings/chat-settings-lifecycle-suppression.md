# `WBP_InGameMenu_PC` is the match HUD, not the Escape menu

| Field | Value |
|---|---|
| Date | 2026-07-09 |
| Area | mod / UI |
| Tags | chat, settings, escape-menu, widget-lifecycle, ue4ss |
| Status | confirmed |

## Symptom

The rebuilt chat widget loaded successfully but never appeared in Practice. Enter was rejected because chat believed a native menu was active for the entire match.

## Root cause

`WBP_InGameMenu_PC_C:OnNavigatedTo` looks like an Escape-menu lifecycle signal by name, but the class is the normal in-match HUD. Its widget tree contains the ability HUD, reaction panel, practice prompt, performance display, and other always-on match elements. `OnNavigatedTo` fires during normal match startup and does not mean that a modal menu is covering gameplay.

The actual Escape/settings surface is `WBP_SettingsHub_C`. In a live Practice pass, pressing Escape fired `WBP_SettingsHub_C:OnNavigatedTo`; closing it fired `WBP_SettingsHub_C:OnNavBack`.

## Fix

Chat suppression now tracks only `WBP_SettingsHub_C` navigation. It hides or closes chat on `OnNavigatedTo` and restores the normal passive presentation after `OnNavBack`, `OnNavigatedAway`, or `OdyMenu:CloseSelf`.

## Lesson

Do not infer a widget's player-facing purpose from its class name. Confirm its runtime tree and lifecycle timing. For Omega Strikers, `WBP_InGameMenu_PC_C` means the in-game HUD; `WBP_SettingsHub_C` is the Escape/settings screen that should suppress additive chat UI.

## Related

- Files: `mod/OSPlus/scripts/chat.lua`, `docs/engine/widgets.md`
- Feature: `docs/features/chat-usability-overhaul.md`
