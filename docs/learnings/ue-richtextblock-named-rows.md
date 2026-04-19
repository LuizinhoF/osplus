# ue-richtextblock-named-rows

| Field | Value |
|---|---|
| Date | 2026-04-18 |
| Area | ue-editor |
| Tags | umg, richtextblock, ue5.1, decorators, text-style-set |
| Status | confirmed |

## Symptom

Tried to color portions of a chat history line with `<color value="#ff8800">orange</> plain` in a `URichTextBlock` configured with a `Text Style Set` DataTable and an empty `BP_DefaultRichDecorator` Blueprint subclass in the Decorator Classes list. The `<color>` tag was rendered as literal text in the widget — angle brackets and all — instead of being parsed and applied as a style.

Burned roughly an hour assuming this was a decorator setup or asset visibility problem before tracing it to the actual UE 5.1 stock behavior.

## Root cause

Stock `URichTextBlock` in UE 5.1 has **no built-in `<color>` tag**. The default markup parser (`FDefaultRichTextMarkupParser`) recognizes a tag if and only if its name matches a row name in the assigned `RichTextStyleRow` DataTable. There is no engine-side fallback that interprets `value="#RRGGBB"` as a color.

Adding an empty Blueprint subclass of `URichTextBlockDecorator` to the Decorator Classes array also does nothing — decorators are handlers for tags whose names *they* claim, not a generic enabler. Common online tutorials that show `<color>` working are either:

- Using Common UI's `UCommonRichTextBlock`, which adds bundled decorators including a color one, or
- Using a custom C++ decorator that authors `<color>`/`<font>`/etc. handlers, or
- On a different UE version where Epic shipped a stock color decorator.

UE 5.1.0's stock `URichTextBlock` is none of those.

## Fix

Define each visual style as a **named row** in the Text Style Set DataTable and reference it by name in markup. For OSPlus chat:

- Create `Content/Mods/OSPlus/Chat/DT_ChatRichTextStyles` (DataTable, row type `RichTextStyleRow`).
- Add row `Default` (Font: Roboto Regular 14, Color: white). Used for any text not wrapped in a tag — i.e. message bodies.
- Add row `Sender` (same Font, accent color, full size). Used for sender labels in the chat history.
- Add row `PresenceName` (same Font, accent hue but lighter weight / smaller size). Used for names in the presence roster, so the eye can tell "this is the roster" apart from "this is who said the message".
- Lua wraps sender text in chat history as `<Sender>[Alice]</> hello world` via `mod/OSPlus/scripts/chat.lua` `senderTag()`, and presence-list names as `<PresenceName>Alice</>` via `presenceTag()`. The `[...]` brackets and message body sit outside the tag and inherit the `Default` row.
- Both `ChatHistory` and `PresenceList` `RichTextBlock`s reference the same DataTable. No Decorator Classes entries needed — adding an empty `BP_DefaultRichDecorator` subclass crashes the engine on first SetText (verified on UE 5.1.0); leave the array empty.
- Lua-side `escapeForRichText()` converts user-typed `<` / `>` to `&lt;` / `&gt;` so user content can't accidentally form tags.

If we ever want per-player colors, the upgrade path is local: add `Color1`..`ColorN` rows to the same DataTable and emit `<ColorX>...</>` from Lua. No BP code change required.

Bumped `M.VERSION` to `v16-chat-presence-and-rich-text` in `mod/OSPlus/scripts/config.lua`.

## Lesson

`URichTextBlock`'s tag space is **defined by the rows of the assigned DataTable**, not by attribute syntax. If your tag name isn't a row name and you haven't shipped a custom decorator that claims it, the markup is rendered as literal text. When picking colors / styles for a stock `URichTextBlock`, design a small named palette up front and reference it; don't reach for inline color attributes.

If you need true arbitrary-color inline styling without writing C++, switch to `UCommonRichTextBlock` (requires the Common UI plugin per `.cursor/skills/ue-ui-umg-slate/references/common-ui-setup.md`).

## Related

- Files: `mod/OSPlus/scripts/chat.lua` (Rich text formatting block at top), `docs/architecture/state-contract.md` (`ChatHistory` / `PresenceList` rows of the BP-owned table)
- Skill: `.cursor/skills/ue-ui-umg-slate/SKILL.md`
- DataTable: `Content/Mods/OSPlus/Chat/DT_ChatRichTextStyles` in the editor project at `F:\Omegamod\OmegaStonkers 5.1\`
