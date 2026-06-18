# Customization screen uses a `UWidgetSwitcher` for sub-tabs, with a 7-slot named-child equipped row

| Field | Value |
|---|---|
| Date | 2026-05-02 |
| Area | re |
| Tags | ui, customization-screen, widget-switcher, emote-loadout, probe, widgets-md |
| Status | confirmed |

## Symptom

Designing ADR 0004 (*Emote loadout as an OSPlus-canonical parallel layer*) committed us to "replace the Cosmetics → Emote sub-tab content with an OSPlus widget" without verified widget paths. The relevant section in `docs/engine/widgets.md` ("The game's own widget tree") catalogued only the *persistent + menu* widget tree (`GameInstance_Base_C` children, `WBP_HomeHub_PC_C` cluster). Nothing in `docs/`, `AGENTS.md`, or `KNOWLEDGEBASE.md` covered:

- The host widget for the per-Striker customization page.
- The mechanism that switches between Cosmetics sub-tabs (Skins / Emote / Goal Explosion).
- Whether the equipped emote loadout was a fixed 7-slot row or a dynamic array.

The original UE4SS-dump-based static analysis (`UE4SS_ObjectDump.txt`) lists the WBP classes but not their *runtime parent-child relationships* — a class can exist in the dump and never be instantiated, or be instantiated as a child of any of N candidate parents.

## Root cause

The static UObject dump is a class-level inventory, not an instance-level tree. To learn "where does WBP_X actually live in the live UI when the player is on screen Y," runtime evidence is required. Two earlier probe attempts on this question failed:

1. **First attempt** — `mod/OSPlus/scripts/probe_subtab_a0.lua` was authored but the `require` line in `main.lua` was left commented out. F8 did nothing because the probe never loaded.
2. **Second attempt** — probe loaded (479 live `UserWidget` instances detected) but produced *zero* matching candidates. Cause: `obj:GetClass():GetName()` and `obj:GetName()` returned UE4SS userdata wrappers (not Lua strings) for 100% of widgets on UE4SS 3.0.1; the substring filter silently failed to match anything. Symptoms looked like "no widgets exist" — actually "every name is unprintable."

The working probe pattern routes both class-name and instance-name through `obj:GetFullName()` (which has been a known-string-returning path in `log.lua` for months — see `safeFullName` in any prior chat-debug telemetry) and parses the leading token as the class short name and the trailing path component as the leaf name. Once that switch was made, the probe found the target on the first F8 press.

## Fix

Two artifacts:

1. **New canonical-doc section** at [`docs/engine/widgets.md` → "Customization screen (Home Hub → Customize)"](../engine/widgets.md#customization-screen-home-hub--customize) carrying the verified tree:

   ```text
   WBP_Menu_Striker_C
   └── WBP_Panel_StrikerCosmetics_C
       └── CosmeticsPanelSwitcher (UWidgetSwitcher)
           ├── WBP_Panel_StrikerSkins_C
           ├── WBP_Panel_StrikerEmoticons_C
           │   ├── EmoticonEquippedContainer (DropTile1..DropTile7)
           │   └── EmoticonsTileView
           └── WBP_Panel_StrikerGoalExplosions_C
   ```

2. **Cascade updates** to the docs that touched stale or absent claims (`docs/game/screens.md` row added, `docs/game/lobby.md` "TBD: cosmetic access flow" closed, `docs/engine/strikers.md` open question refined, `docs/glossary.md` Striker entry + Emoticon row enriched, ADR 0004 *What this commits us to* cross-linked to the verified tree).

The probe (`mod/OSPlus/scripts/probe_subtab_a0.lua`) and its load line in `main.lua` are throwaway and disarmed in the same change as this learning lands.

## Lesson

Three transferable rules:

1. **For "what is the runtime widget tree of screen X" questions, the static UObject dump is a starting filter, not the answer.** The static dump tells you which classes *can* exist; only a runtime probe with `WidgetTree:GetRootWidget()` traversal tells you which instances *do* exist and how they're parented. Always plan for an instance-level probe before committing UI-replacement features.

2. **On UE4SS 3.0.1, `obj:GetClass():GetName()` and `obj:GetName()` return userdata, not strings, for live `UserWidget` instances.** Any substring/regex filter applied to those values silently fails. Canonical workaround: route everything through `obj:GetFullName()` (returns a Lua string of the form `"<ClassShortName> <FullPath>"`) and parse the leading token + trailing path component. Codify in any future widget-walking probe.

3. **Sub-tab navigation in OS's UI is a `UWidgetSwitcher` pattern, not a tab-button-cluster pattern.** Detect the active sub-tab via `<switcher>.ActiveWidgetIndex`. The *equipped emote loadout is a 7-slot fixed named-child row* (`DropTile1..DropTile7`), not a dynamic array — any "8th slot" feature ships its own widget surface. These two facts are the load-bearing constraints any future emote-loadout / cosmetic-loadout work must respect.

The 7-slot constraint at the UI layer matches the wire-format constraint already documented (`PMReactionIds.Emoticons` is `Array<FName>` length 7, `PMGameInstance.GetNumEmoticonsToEquip` returns 7). Both layers agree.

## Related

- Files:
  - [`docs/engine/widgets.md`](../engine/widgets.md) — canonical home for the new widget-tree section.
  - [`docs/decisions/0004-emote-loadout-as-osplus-layer.md`](../decisions/0004-emote-loadout-as-osplus-layer.md) — ADR that forced this probe; *What this commits us to* now cross-links here.
  - [`docs/game/screens.md`](../game/screens.md), [`docs/game/lobby.md`](../game/lobby.md), [`docs/engine/strikers.md`](../engine/strikers.md), [`docs/glossary.md`](../glossary.md) — cascade updates per `correct-knowledge` skill.
  - `mod/OSPlus/scripts/probe_subtab_a0.lua` — throwaway probe (disarmed in the same change).
- Prior learnings:
  - [`ue4ss-type-stubs-as-canonical-source`](./ue4ss-type-stubs-as-canonical-source.md) — meta-rule "use static dumps before live reflection." This learning is the corollary: *for instance-level questions*, static dumps aren't enough; the runtime probe is necessary. The two coexist — you start with the static dump to filter the candidate class set, then probe live to disambiguate.
  - [`ue4ss-cold-start-hook-install-pattern`](./ue4ss-cold-start-hook-install-pattern.md) — same UE4SS 3.0.1 surface; reinforces "run UE4SS lookups against the shipping version" discipline.
- Skill: this entry was produced by following [`.cursor/skills/correct-knowledge/SKILL.md`](../../.cursor/skills/correct-knowledge/SKILL.md) (Phase 5).
