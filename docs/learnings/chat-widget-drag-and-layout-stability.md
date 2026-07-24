# Chat widget drag and layout stability

| Field | Value |
|---|---|
| Date | 2026-07-24 |
| Area | mod / ue-editor |
| Tags | `chat, umg, scrollbox, sizebox, pointer-capture, resize` |
| Status | `confirmed` |

## Symptom

Opening the composer moved a full message history upward, short histories started at the top of the expanded panel, and the resize edge stopped tracking when the cursor left its narrow strip. After pointer capture was added, upward resize still did nothing and downward resize appeared to snap only after mouse release.

## Root cause

Four independent Slate behaviors combined:

1. `SBox::ComputeDesiredSize` returns zero when its only child is `Collapsed`, before considering `HeightOverride`. A 40 px `SizeBox` around the collapsed composer therefore did not reserve 40 px.
2. A `ScrollBox` keeps its previous scroll offset when its viewport height changes. Expanding the panel without another `ScrollToEnd()` could move the newest rows out of view.
3. `SButton` with `ClickMethod=MouseDown` does not capture the mouse; `OnMouseLeave` releases its pressed state. It cannot own a drag beyond the original hit strip.
4. `APlayerController:GetMousePosition` did not update continuously while Slate owned the captured UMG drag. It caught up on release, producing the visible snap.

## Fix

`WBP_ModChat` now keeps a visible `ComposerLayer` inside the 40 px `ComposerSize`. The layer contains an always-present `ComposerReserve` spacer plus the `Hidden` composer panel, so the same space exists in passive and focused modes. History content is bottom-aligned, and `mod/OSPlus/scripts/chat.lua` re-anchors `ChatScroll` after open, close, and resize layout passes.

The resize surface is a 12 px transparent hit target with a 2 px visible grip. Its button uses `DownAndUp` so Slate captures the pointer, while Blueprint owns pressed/released state and restores input focus. During the bounded drag, Lua reads `UWidgetLayoutLibrary:GetMousePositionOnViewport`, which follows Slate's cursor continuously, and applies the clamped 220-420 px height immediately.

## Lesson

Do not infer reserved layout from a `SizeBox` whose only child may be `Collapsed`, and do not use `MouseDown` buttons or player-controller cursor data for captured UMG drags. Reserve space with a visible layout child, capture with `DownAndUp`, read the Slate cursor, and explicitly restore a follow-tail scroll position after viewport-size changes.

## Related

- Files: `mod/OSPlus/scripts/chat.lua`, `docs/features/chat-usability-overhaul.md`
- Asset: `/Game/Mods/OSPlus/Chat/WBP_ModChat`
- Engine sources: `Slate/Private/Widgets/Layout/SBox.cpp`, `Slate/Private/Widgets/Input/SButton.cpp`, `UMG/Private/WidgetLayoutLibrary.cpp`
- Prior learning: `docs/learnings/umg-scrollbox-chip-buttons.md`
