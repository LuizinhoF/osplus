# FOdy*Binding.InitialValue is the constructor default, NOT the live value

| Field | Value |
|---|---|
| Date | 2026-04-28 |
| Area | mod |
| Tags | prometheus, odyui, binding, ue4ss, ufunction, struct, ui-data |
| Status | confirmed |

## Symptom

`identity.lua` v41 walked `FindAllOf("PMPlayerUIData")`, matched the local player's instance by `PlayerId`, found the `Username : FOdyUITextBinding` field as expected, and read `binding.InitialValue` — but the read returned an empty FText. Telemetry log line on the user's machine:

```
[IDENTITY] [waiting] resolveDisplayName: username-binding-InitialValue-empty
```

The value was clearly *somewhere* on the binding (the in-game widget rendered "Ispicas" in the same UI surface) — just not in `InitialValue`.

## Root cause

`FOdy<Type>Binding` (a family covering Bool, Color, DPIScalingSettings, Int, Name, Object, Text, Texture, Timespan — all in `OdyUI.lua` lines ~70-140) is a wrapper struct that stores **only one reflected UPROPERTY: `InitialValue`**. The struct's *live* current value lives in non-reflected C++ members and is not visible to UE4SS field reads.

`InitialValue` literally means what its name says: the value the binding was constructed with. There are two ways the BP layer populates a binding:

1. **Construction-time default**: the BP passes the value as an argument to the binding's constructor. Subsequent `binding.InitialValue` reads return that value directly. Typical for static UI text (titles, button labels).
2. **Post-construction `SetValue` call**: the BP creates the binding with no argument (so `InitialValue` is the FText/FString/bool default — empty for FText), then calls `U<Type>BindingFunctionLibrary:<Type>Binding_SetValue(binding, NewValue)` to populate the live value. Typical for *dynamic* UI bindings driven by data updates — like a player's username, which has to wait for the identity bootstrap to complete.

The local player's `Username` binding is path 2. `InitialValue` was never set, so it stayed empty. Every visible "Ispicas" on screen was rendered by the BP reading the live value via `TextBinding_GetValue` — the canonical accessor in `UOdyUITextBindingFunctionLibrary` (declared on `OdyUI.lua` line 632-633 with `---@return FText`).

The transferable misread on our part: we treated the `---@field InitialValue FText` annotation as documenting "the binding's value" rather than "the binding's *initial* value." The name is honest; we just didn't read it carefully.

## Fix

`mod/OSPlus/scripts/identity.lua` v42 — three-path resolver in `readLocalPlayerUIData`, ordered cheapest-first:

1. **`ui.Profile.Username`** — `UPMPlayerUIData` carries an embedded `Profile : FPlayerPublicProfile` struct (Prometheus.lua line ~13703), and `FPlayerPublicProfile.Username : FString` (Prometheus.lua line 6749) is a plain string with no binding indirection. This is the v42 production path. Confirmed working on first attempt: `[IDENTITY] Resolved display name: Ispicas (PMPlayerUIData.Profile.Username)` at +13ms after the Prometheus ID resolved.

2. **`ui.Username.InitialValue`** — kept as the second path because it's still cheap (one field read) and would catch the case where some future BP populates `Username` as a construction-time default but leaves `Profile` empty.

3. **`UOdyUITextBindingFunctionLibrary:TextBinding_GetValue(ui.Username)`** — final fallback. The CDO is resolved via `StaticFindObject("/Script/OdyUI.Default__OdyUITextBindingFunctionLibrary")` (with `FindFirstOf("OdyUITextBindingFunctionLibrary")` as a backup) and cached for reuse. The library is a `UBlueprintFunctionLibrary` so all its UFunctions are static-style — call them on the CDO, pass the binding struct as the first argument.

In practice path 1 wins. Paths 2 and 3 exist for defense in depth and to make the failure breadcrumb specific (`username-binding-empty-on-all-paths(GetValue=...)`) when something genuinely goes wrong.

## Lesson

**For Prometheus UI data, prefer the embedded raw struct over the binding wrapper.** Every Prometheus `UPM*UIData` class that exposes a `FOdy<Type>Binding` field also tends to carry the source-of-truth struct as a sibling field (`Profile : FPlayerPublicProfile` on `UPMPlayerUIData`, `Player : APMPlayerState` on lobby/match UI data, etc.). The bindings are a UI-layer abstraction for change notification; the raw struct is the data. When you need the data, read the struct.

Two corollaries:

- **Field-name parity is a hint, not a guarantee.** The presence of `Username : FOdyUITextBinding` *and* `Profile : FPlayerPublicProfile` on the same class is the BP author's "you can read this two ways" pattern. Always check whether the data also lives in plain form on a sibling field before reaching for the binding accessor.
- **`FOdy*Binding.InitialValue` reads are diagnostic, not authoritative.** A non-empty `InitialValue` tells you the binding had a constructor default; an empty one tells you nothing about the live value. Do not write `if binding.InitialValue then ... else fallback() end` as the binding's value-presence check — the absence of `InitialValue` is the *common* case for dynamically-driven bindings.

The meta-meta-lesson: this and `ue4ss-type-stubs-as-canonical-source.md` (the same-day learning that surfaced the `UPMPlayerUIData` schema) are paired. The type-stubs lesson is *how to find the schema*; this lesson is *how to read it correctly*. Both apply to every future Prometheus UI investigation.

## Related

- Files:
  - `mod/OSPlus/scripts/identity.lua` (v42 resolver, header docstring)
  - `<game>/Binaries/Win64/Mods/shared/types/Prometheus.lua` (line 6747 `FPlayerPublicProfile`, line ~13679 `UPMPlayerUIData`)
  - `<game>/Binaries/Win64/Mods/shared/types/OdyUI.lua` (lines 70-140 `FOdy<Type>Binding` family, line 632-633 `TextBinding_GetValue`)
- Sibling learning (paired): `docs/learnings/ue4ss-type-stubs-as-canonical-source.md`
- Prior superseded:
  - `docs/learnings/identity-display-name-substrate-replaces-heuristics.md` (resolver mechanism only — the heuristic-removal lesson stands)
  - `docs/learnings/os-runtime-data-model.md` (display-name source claim — see the 2026-04-28 update header on that file)
- Verification: relay log line `[PROFILE] upsert prometheusId=632680c154686dedd6522b09 displayName=Ispicas` at 2026-04-29T00:08:43.045Z (local 21:08).
