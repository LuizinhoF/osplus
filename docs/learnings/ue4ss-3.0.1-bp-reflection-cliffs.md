# UE4SS 3.0.1 Lua: BP struct property reflection cliffs

| Field | Value |
|---|---|
| Date | 2026-05-17 |
| Area | ue4ss |
| Tags | ue4ss-3.0.1, reflection, struct-property, fname, ftext, foreach-property, bp-only, register-custom-event |
| Status | confirmed |

## ⚠️ Read [`ue4ss-type-stubs-as-canonical-source.md`](./ue4ss-type-stubs-as-canonical-source.md) FIRST

The cliffs below were ALL avoidable. The repo already had a learning saying "check UE4SS type stubs at `<game>/Binaries/Win64/Mods/shared/types/*.lua` before any runtime reflection" — but this session ignored it and walked into the same trap that learning was written about. The type stubs contain every UProperty + UFunction + class hierarchy of every loaded UClass. Grep them.

For the striker-name case specifically: `PMUIData_Character.lua` shows `UPMUIData_Character_C : UPMCharacterUIData`; following the chain in `Prometheus.lua` to `UPMCharacterUIData : UPMEntitlementUIData` reveals `Name FOdyUITextBinding` on the entitlement base. The correct access is `panel.UIData.Name.InitialValue:ToString()` — the binding-wrapper pattern from the type-stubs learning. We were one `.InitialValue` away from a working extraction the whole time.

**This learning still documents real cliffs that exist** in case you must do live reflection (the cooked uasset isn't loaded, the class is C++-only without stubs, etc.) — but those cases should be rare. Default to type stubs.

## Symptom

Trying to extract a string value (the current striker's display name) from a BP-typed property `parentPanel.UIData` of type `PMUIData_Character_C` via UE4SS 3.0.1 Lua reflection hit a chain of dead ends. Every approach that should work in theory failed in a distinct way. Documented here so future struct-property work doesn't re-walk the rakes — the cliffs are reproducible, not transient. **But:** see the warning above — most of these failures would not have happened if we'd checked the type stubs first.

## The cliffs

### Cliff 1: `obj.fieldname` returns a wrapper for any name

Accessing a UObject's properties via Lua `.` syntax returns a userdata wrapper regardless of whether the field actually exists on the class. Confirmed by trying nonsense field names (`FriendlyName`, `Title`, `Id`, `ShortName` — none of which were declared on `PMUIData_Character_C`); each returned a unique userdata that stringified as `UObject: <addr>` or `UScriptStruct: <addr>`.

Implication: you cannot tell whether a property exists by checking if access returns nil. Every access returns *something*.

### Cliff 2: FName / FText / FString unwrap methods all return nil

For wrappers returned by `.` access on what should be string-bearing fields (`DisplayName`, `Name`, `CharacterId`, etc.), every unwrap method probed returned nil:

- `:ToString()` → nil
- `:Get()` → nil
- `:GetText()` → nil
- `:GetString()` → nil
- `:ToText()` → nil

All wrapped in `pcall`, none of which threw an error — they returned nil values silently. The wrappers acknowledge the method exists but the call doesn't yield a usable value.

### Cliff 3: `UClass:ForEachProperty` errors past first iteration

```lua
cls:ForEachProperty(function(prop)
    pcall(function() ... end)  -- per-property body wrapped
    return false  -- continue
end)
```

Iterated exactly one property (`UberGraphFrame` — the BP graph's internal frame, not user data) then the outer `pcall` caught an error and the iteration stopped. Wrapping the inner body in additional `pcall` didn't help — the error happens at the iteration-state level, not the per-property handler. Reproducible.

### Cliff 4: `GetSuperStruct` chain-walk crashes the game

Trying to walk the class hierarchy by recursively calling `cls:GetSuperStruct()` and enumerating properties from each parent class (intent: catch inherited properties since the BP class only declares UberGraphFrame) **crashed the game outright**. No Lua error message — process termination. Avoid.

### Cliff 5: `RegisterCustomEvent` doesn't fire for native parent-class functions

Tried `RegisterCustomEvent("SetUIData", cb)` to hook the data-injection call when the player switches strikers. The callback never fired despite the function clearly being called (the panel's UIData property updated, the UI re-rendered). `SetUIData` is evidently native on `OdyWidget` (the game-side C++ base class for all OS widgets), and `RegisterCustomEvent` only catches BP-VM dispatch via `UObject::ProcessInternal` — not native function entry. See [`docs/learnings/ue4ss-registerhook-vs-registercustomevent.md`](./ue4ss-registerhook-vs-registercustomevent.md) for the API-selection rule.

We *could* try `RegisterHook` on `/Script/OdyUI.OdyWidget:SetUIData` if OdyWidget's SetUIData is `FUNC_Native: 1`, but we have no access to the OdyUI C++ symbols to confirm. Skipped for v1.

## What DOES work

Three reliable alternatives we've validated:

### 1. Read rendered UTextBlock values

The game renders strings into `UTextBlock` widgets. Those are native UMG, with documented stable methods:

```lua
local textBlocks = FindAllOf("TextBlock")
-- ... filter for the one we want by leaf name or parent path ...
local fText = textBlock:GetText()   -- returns FText (native)
local str = fText:ToString()        -- ToString on FText DOES work for rendered text
```

`FText:ToString()` on FText *from a rendered UTextBlock* works, even though `FText:ToString()` on the wrapper returned by `obj.SomeProperty` doesn't. The difference is presumably the wrapper layer UE4SS injects for property access vs. direct method-return values.

This is the "read what's already on screen" fallback. Brittle (requires the widget to be rendered), but it works when you absolutely need the string.

### 2. Call BP functions on UObjects directly

Method-call syntax on UObjects works fine, validated by our SetActivePanel redirect:

```lua
panel:SetActivePanel(otherPanel)  -- BP function call with object arg — works
```

If the data model exposes a BP function returning the string (e.g., a hypothetical `GetEmoticonDisplayName(emoticonId) → FText`), calling it via direct invocation bypasses the property-access layer entirely. This is the path to evaluate when the cliffs block direct property reads.

### 3. Static asset extraction

For "what's actually on this class" questions, `UAssetGUI tojson` on the cooked uasset reveals the NameMap and property declarations without runtime reflection at all. We did this successfully for `WBP_Panel_StrikerCosmetics`, `Interface_WBP_Panel`, `WBP_Panel_StrikerEmoticons`. The static dump is authoritative for "what fields and functions exist."

## Lesson

For field-extraction tasks on UE4SS 3.0.1, the priority order is:

1. **Static extraction first** — read the cooked uasset NameMap. Authoritative, no runtime risk. Already the [extract-before-hypothesizing](../README.md) methodology rule.
2. **Direct function calls on UObjects** if the class exposes BP functions that return what you want.
3. **Rendered UTextBlock / UImage / etc.** if the value is being displayed on screen and you can find the rendering widget.
4. **Property reflection via `obj.fieldname`** as last resort — and expect to hit cliffs.

The cliffs may resolve in newer UE4SS versions (3.0.3+ documented improved reflection). Until we upgrade or have a feature that forces solving them, **don't navigate struct properties via reflection**.

## Related

- API selection rule: [`docs/learnings/ue4ss-registerhook-vs-registercustomevent.md`](./ue4ss-registerhook-vs-registercustomevent.md)
- Validated production pattern: [`docs/learnings/osplus-widget-integration-pattern.md`](./osplus-widget-integration-pattern.md)
- ADR 0004 (revised 2026-05-16): [`docs/decisions/0004-emote-loadout-as-osplus-layer.md`](../decisions/0004-emote-loadout-as-osplus-layer.md)
- Code locations of the cliffs encountered: `mod/OSPlus/scripts/emote_loadout.lua` (the `extractStrikerName` deferred-comment block documents the specific failures at the call sites)
