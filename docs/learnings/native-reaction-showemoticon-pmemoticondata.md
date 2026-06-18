# native-reaction-showemoticon-pmemoticondata

| Field | Value |
|---|---|
| Date | 2026-04-21 |
| Area | re |
| Tags | native-reaction, emote, emoticon, pmemoticondata, showemoticon |
| Status | confirmed |

## Symptom

We needed OSPlus emotes to render through the same native Omega Strikers reaction path as the `1`-`7` hotkeys, but the first instinct was to probe that path with an arbitrary shipped `PMEmoteData` asset.

## Root cause / context

The native reaction stack is data-driven and typed, not a single generic "play emote" path:

- `WBP_ReactionButton`, `WBP_ReactionModal`, and `WBP_ReactionModalItem` all reference both `PMEmoteData` and `PMEmoticonData`.
- `BTT_UseReactionAndWait` contains native gameplay-side calls named `ShowEmote` and `ShowEmoticon`.
- Live runtime probing confirmed that a no-arg `ShowSelectedReaction` call on `WBP_ReactionModal_C` renders a native reaction, so the modal is a real owner/path in practice rather than just a UI shell.
- Parsed `EmoteData_Asher_Delighted` shows `PMEmoteData` includes character-specific animation references (`/Game/Prometheus/Characters/Shieldz/.../AM_ShieldUser_Default_Emote_Happy`) plus icon art.
- Parsed `EmoticonData_JulietteComfy` shows `PMEmoticonData` is the lighter-weight icon/audio path: texture + Wwise event, no striker animation dependency.
- `PMEmoticonData.bHideFromEnemyTeam` (Bool) gates **gameplay-layer team-only callouts** in-match (e.g. "Spread out!" / goalie defends-callout). It is **NOT** a cross-client / mod-installation visibility gate. Setting it to `true` on a custom asset would make the emote half-broken (own team sees, enemy team doesn't, regardless of who has the mod). Confirmed by maintainer 2026-05-01 during ADR 0004 drafting; an earlier draft mis-used the flag for "graceful vanilla-peer fallback" and was corrected.

That means a random shipped `PMEmoteData` is a bad generic probe for the hotkey reaction pipeline because it bakes in striker-specific animation assumptions. The safer first probe is a `PMEmoticonData` plus `ShowEmoticon`.

## Fix

Added a Lua-side native reaction spike that:

1. resolves a custom mod asset path first,
2. falls back to a shipped `PMEmoticonData` (`/Game/Prometheus/DataAssets/EmoticonData/EmoticonData_JulietteComfy`),
3. prefers `ShowEmoticon` when the resolved asset class contains `Emoticon`,
4. treats `WBP_ReactionModal_C` as the first-class runtime path and tries to match the resolved asset against the modal's `ReactionItemWidgets` / `Reactions` before driving `SelectedReactionIndex` and calling `ShowSelectedReaction`,
5. still falls back to broader target probing before leaving the existing chat-line fallback in place.

See `mod/OSPlus/scripts/native_emotes.lua`, `mod/OSPlus/scripts/emotes.lua`, and `mod/OSPlus/scripts/config.lua`.

## Lesson

When testing the native Omega Strikers reaction pipeline, start with `PMEmoticonData` unless you already have character-compatible animation assets, and treat `WBP_ReactionModal_C` as a likely live owner of the render call. A successful no-arg modal call does not prove asset control by itself; if you need a specific reaction, match and drive the modal's selected reaction state explicitly.

## Related

- Files: `mod/OSPlus/scripts/native_emotes.lua`, `mod/OSPlus/scripts/emotes.lua`, `mod/OSPlus/scripts/config.lua`, `scratch/reaction-re/EmoticonData_JulietteComfy.names.txt`, `scratch/reaction-re/EmoteData_Asher_Delighted.names.txt`, `scratch/reaction-re/BTT_UseReactionAndWait.names.txt`
- Prior learnings (if this supersedes or extends one): none
- Upstream sources / docs / discussions, if any: native asset names parsed from the shipped `OmegaStrikers-Windows.pak`