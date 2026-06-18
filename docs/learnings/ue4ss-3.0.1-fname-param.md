# UE4SS 3.0.1 Lua: FName params to BP UFunctions require explicit `FName(...)` wrap

| Field | Value |
|---|---|
| Date | 2026-05-17 |
| Area | ue4ss |
| Tags | ue4ss-3.0.1, lua, fname, nameproperty, ufunction, bp-call, marshaling, hard-crash |
| Status | confirmed (empirically validated against UE4SS 3.0.1, Omega Strikers shipping branch) |

## Symptom

A cooked Blueprint UFunction with a `NameProperty` (FName) input parameter, called from Lua via `widget:BPFunc(luaString, ...)`, **hard-crashes the game process** (silent termination — no Lua error, `pcall` does not catch it). The same widget responds normally to UFunctions whose inputs are zero-arg, all-`StrProperty`, or other types we tested.

Concrete crash signature, isolated via a 4-step diagnostic:

```
[DIAG] OSPlus_BeginEquippedRow returned: ok=true err=nil      -- no-arg, works
[DIAG] OSPlus_BeginOwnedGrid returned: ok=true err=nil         -- no-arg, works
[DIAG] OSPlus_SetStrikerHeader('','') returned: ok=true err=nil-- (FString, FString) works
[DIAG] OSPlus_SetStrikerHeader real returned: ok=true err=nil  -- (FString, FString) works
[DIAG] about to call OSPlus_AddOwnedEmote with empty strings    -- (FName, FString, FString)
<process terminates, no return-log line>
```

Even passing `""` (an FString that would resolve to `NAME_None` if coerced) for the FName slot triggers the crash. So it isn't bad data — it's the type slot itself.

## Root cause

UE4SS 3.0.1's BP-UFunction caller has per-type marshalers on a per-param-slot basis. `StrProperty` has an auto-coerce path from Lua string → `FString`. `NameProperty` does **not** — it expects an already-constructed UE4SS `FName` userdata.

When a Lua string is handed to the `NameProperty` slot, the property handler interprets the raw Lua-string pointer as if it were an in-memory `FName` struct and writes 12 bytes from it into the params buffer at that slot's offset. The result is corrupted alignment for the *following* slot — typically a `StrProperty` whose marshaler then sees a garbage `FString` destination pointer and does a null-pointer write. The C++ access violation is fatal: no UE4SS-level exception, no Lua error, no `pcall`-catchable trap. The process dies between Lua's "call" and any return path.

This matches the upstream-documented failure class in `RE-UE4SS#938` (KismetSystemLibrary.PrintString marshalling corruption) and is the same pattern flagged in `#368` (FName parameter handling on UFunction calls).

## Fix

Wrap every Lua arg destined for a `NameProperty` BP input slot with the global `FName(...)` constructor before the call.

```lua
-- WRONG — silent hard-crash, no pcall-catchable error
widget:OSPlus_AddOwnedEmote(d.Id or "", d.Name or "", d.Icon or "")

-- RIGHT — explicit FName wrap on the NameProperty slot
widget:OSPlus_AddOwnedEmote(FName(d.Id or ""), d.Name or "", d.Icon or "")
```

`FName()` accepts a string or integer; in 3.0.1 the default `findType` is `FNAME_Add`, so unknown strings are added to the name table rather than silently becoming `NAME_None`. Passing `""` resolves to `NAME_None` safely.

Applied in `mod/OSPlus/scripts/emote_loadout.lua` to two call sites:
- `pushStrikerContext` → `widget:OSPlus_AddEquippedSlot(i, FName(d.Id or ""), …)`
- `pushOwnedEmotesOnce` → `widget:OSPlus_AddOwnedEmote(FName(d.Id or ""), …)`

## Lesson

For BP UFunctions called from UE4SS 3.0.1 Lua: **read the cooked uasset's `LoadedProperties` for every `CPF_Parm` flagged entry and check the `SerializedType` of each**. If any input slot is `NameProperty`, the Lua call site must use `FName(...)` for that arg. The marshaler is per-slot and fail-silent at the C++ level — a wrong type produces a hard process crash, not a Lua error.

The diagnostic recipe that found this in one game run: probe with no-arg → all-FString-empty → all-FString-real → the suspect signature. The first three pin which type combinations work; the fourth confirms the new type is the trigger. Inspect the UAssetGUI JSON dump of the function's `LoadedProperties` to see the exact `SerializedType` of each `CPF_Parm` slot.

The general rule: **`StrProperty` auto-coerces, `NameProperty` does not, and the failure mode is silent process termination — not an error.** Assume every non-string scalar UE type may need an explicit Lua-side constructor and verify via the JSON dump rather than trial-and-error at runtime (each failed trial is a full game restart).

## Related

- Discovery context: emote loadout v1 drip-feed (this commit's `emote_loadout.lua` `pushStrikerContext` / `pushOwnedEmotesOnce`)
- Sibling marshaling cliff (TArray Lua→BP): `docs/learnings/ue4ss-3.0.1-tarray-tmap-lua-api.md` and `docs/learnings/ue4ss-ufunction-out-param-marshaling-3-0-1.md`
- UE4SS docs: [FName global constructor](https://docs.ue4ss.com/lua-api/global-functions/fname.html)
- Upstream issue (same failure family): [RE-UE4SS#938](https://github.com/UE4SS-RE/RE-UE4SS/issues/938)
- Upstream issue (FName-specific): [RE-UE4SS#368](https://github.com/UE4SS-RE/RE-UE4SS/issues/368)
