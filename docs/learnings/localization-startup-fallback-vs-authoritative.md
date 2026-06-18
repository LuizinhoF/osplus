# Localization startup fallback vs authoritative locale

| Field | Value |
|---|---|
| Date | 2026-05-20 |
| Area | mod |
| Tags | localization, startup, culture, ue4ss |
| Status | confirmed |

## Symptom

OSPlus localized text updated correctly when the player changed language in the
game options, but did not respect the saved language on game restart. Example:
switch to `pt-BR`, restart, open the emote screen, and OSPlus still used
English until the language option was changed again.

## Root cause

`localization.lua` treated its fallback locale (`en`) as if it were an
authoritative game read. On cold start, `PMGameInstance:GetTextLanguage()` can
be unavailable or can report the default before the saved culture has finished
applying. Once `currentLocale` became `en`, later reads skipped detection unless
`SetTextLanguage` fired.

The language-change path worked because the hook parameter from
`PMGameInstance:SetTextLanguage` carries the new locale directly. Re-reading
`GetTextLanguage()` inside that callback is stale and has already returned `en`
while the game was switching to `pt-BR`.

## Fix

`mod/OSPlus/scripts/localization.lua` now distinguishes fallback locale from an
authoritative locale source. It:

- Polls PMGameInstance language fields before Unreal's active culture, because
  Kismet culture can reflect the OS/user environment rather than the game's
  saved UI language during cold boot.
- Uses Kismet culture only as a non-locking fallback while startup probing is
  still active.
- Keeps probing briefly during startup even after the first culture read, so a
  saved language that applies a few ticks later can still replace the default.
- Uses the `SetTextLanguage` hook parameter as authoritative for runtime
  language changes.
- Hooks Unreal's `KismetInternationalizationLibrary` culture setters as a
  second global notification path. When those hooks do not expose a readable
  locale parameter, re-read Kismet directly only as an immediate notification,
  not as a permanent authoritative lock. The hook can fire before Omega
  Strikers' own text-language getter has settled.
- Keeps cheap runtime polling alive after startup, but after the startup probe
  window it polls only `PMGameInstance` (plus `OSPLUS_LOCALE` override), not
  Kismet. This catches in-session language changes even if UE4SS misses or
  stale-reads a culture hook, without letting OS/user culture overwrite the
  game's selected text language.

`mod/OSPlus/scripts/main.lua` initializes and ticks localization globally, so
future screens can subscribe to locale changes without owning startup detection.

## Lesson

Fallback text is not state. Do not let a default language close the detection
loop. Global UI infrastructure should own initial detection, retry, and runtime
change notifications once, with screens only subscribing and rendering.

Unreal culture is also not automatically the same thing as the game's selected
text language. On startup, prefer the game instance's saved text-language state
when it is readable; keep all poll reads non-authoritative until a runtime
language-change hook parameter gives a known-selected locale.

Kismet culture hooks are notifications, not truth by themselves. If a Kismet
hook has no readable locale parameter, do not lock the locale from its immediate
getter result; continue polling the game instance so the final in-game language
state can win a few ticks later.

## Related

- Files: `mod/OSPlus/scripts/localization.lua`, `mod/OSPlus/scripts/main.lua`
- Feature: `docs/features/emote-loadout-ui-improvement.md`
