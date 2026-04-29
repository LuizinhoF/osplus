# UE4SS type stubs are the canonical source — check them BEFORE reflecting

| Field | Value |
|---|---|
| Date | 2026-04-28 |
| Area | re |
| Tags | ue4ss, type-stubs, re-workflow, reflection, prometheus, ui-data |
| Status | confirmed |

## Symptom

The "where does the local player's display name live?" question burned five back-to-back iterations of in-game probes against the Lua/UE4SS reflection surface (`PMPlayerModel.GetCachedMeResponseV1`, `GetCachedPlayerPublicProfile`, `NotifyOnNewObject` on `PMPlayerPublicProfile`, walking `FindAllOf("PMPlayerPublicProfile")` by PID, two-class-chain field/function dumps with `ForEachProperty`/`ForEachFunction`). The fifth iteration **crashed the game** mid-dump. The user finally said *"Why don't you go looking at the previous massive dumps?"* — at which point a 30-second grep against an on-disk file would have produced the answer immediately.

The answer was on disk the entire time.

## Root cause

UE4SS ships a built-in mod called `Mods/shared` that, on startup, dumps **every UClass it loads** into `<game>/Binaries/Win64/Mods/shared/types/<Module>.lua` as Lua type-annotation stubs. These stubs contain:

- Every UProperty: name, type, parent class
- Every UFunction: name, parameter types, return types
- Inheritance chain (`---@class Child : Parent`)

For Omega Strikers, the relevant artifacts are:

| File | Size | Contents |
|---|---|---|
| `Prometheus.lua` | ~597KB | Every `PM*` / `UPM*` / `FPM*` Prometheus class, struct, and enum |
| `OdyUI.lua` | ~50KB | The `FOdy*Binding` struct family + `UOdy*BindingFunctionLibrary` accessors |
| `PMUIData_*.lua` | small | Each BP-derived UI data subclass |
| `Engine.lua`, `CoreUObject.lua`, etc. | varies | Engine bases |

Grepping `Prometheus.lua` for `^---@class UPMPlayerUIData` returns the whole answer in one screen:

```
---@class UPMPlayerUIData : UOdyUIData
---@field IsLocalPlayer FOdyUIBoolBinding
---@field Username FOdyUITextBinding
---@field PlayerId FString
---@field Profile FPlayerPublicProfile
...
```

That's the data model the in-game widget binds to. `PlayerId` is the disambiguation key, `Username` is the answer. `OdyUI.lua` shows `FOdyUITextBinding` is a struct with `InitialValue : FText` (line 121-123) and that the canonical accessor is `UOdyUITextBindingFunctionLibrary:TextBinding_GetValue(binding) → FText` (line 633).

Total elapsed time from "open Prometheus.lua" to "we know the resolver shape": ~5 minutes. Compare with the ~3 hours of in-game probing that preceded it.

## Fix

The mechanical fix is `mod/OSPlus/scripts/identity.lua` v41 — `readLocalPlayerUIData(prometheusId)` walks `FindAllOf("PMPlayerUIData")`, matches by `PlayerId`, and reads `Username.InitialValue`. See the v41 header docstring there for the discovery story.

The **process fix** is the workflow change captured in this learning:

> **Before reaching for any in-game reflection probe** (`ForEachProperty`, `ForEachFunction`, `FindAllOf` on guessed class names, `NotifyOnNewObject` to capture instances), **first grep the type-stub dump**.

Concretely, the two-step probe checklist is now:

1. Grep `<game>/Binaries/Win64/Mods/shared/types/*.lua` for the noun you're chasing. Examples:
   - "Where does the local player's name live?" → grep `Username` + `Local`
   - "What event fires when a match starts?" → grep `MatchStart` / `BeginMatch`
   - "What's the call shape for X UFunction?" → grep `function .*:X(`
2. Only if the stubs are silent, fall back to in-game reflection — and even then, prefer cheap probes (`FindFirstOf`, direct field reads) over heavyweight enumeration that risks crashes.

## Lesson

**The cheapest, safest, and most exhaustive UE/Prometheus reflection surface is on disk, not in the running game.** UE4SS already enumerated every class for us; re-deriving it via in-game probes is paying twice and risks crashes. Always grep the type stubs first.

The transferable meta-rule: when an external tool ships a static dump of the data you're trying to discover dynamically, *use the static dump*. In-game reflection is for confirming runtime values, not for discovering schemas.

Two corollaries:

- **The "BP-derived class hides the parent's properties" trap.** `UPMUIData_Player_C` (the BP child of `UPMPlayerUIData`) only declares its own added fields. The base class — where `Username` actually lives — is in a different file (`Prometheus.lua` vs. `PMUIData_Player.lua`). Always follow `---@class Child : Parent` annotations to the parent file when the field you want isn't on the child.
- **The "binding wrapper" pattern.** Prometheus UI data uses `FOdy*Binding` structs to wrap raw values (FText, bool, int) so the BP layer can subscribe to changes. Direct read of `binding.InitialValue` works when the binding has been initialized; `<TypeName>BindingFunctionLibrary:<Type>Binding_GetValue` is the canonical live accessor. The BlueprintFunctionLibrary class name follows the pattern `UOdyUI<Type>BindingFunctionLibrary`.

## Related

- Files: `mod/OSPlus/scripts/identity.lua` (v41 resolver), `<game>/Binaries/Win64/Mods/shared/types/` (the stubs)
- Prior learnings (chain of failures this learning supersedes for the *display-name* path):
  - `docs/learnings/identity-display-name-substrate-replaces-heuristics.md` — superseded for the resolver mechanism (PMPlayerPublicProfile.Username is the wrong source); the rationale-for-removing-heuristics half is still valid.
  - `docs/learnings/os-runtime-data-model.md` — the "construction order is reliable" claim was empirically falsified in this session (`NotifyOnNewObject` captured "Greedom" — a friend in the cache — not the local player). To be updated separately.
- UE4SS shared dumps documentation: [`UE4SS-RE/RE-UE4SS` repo](https://github.com/UE-Native-Source-Framework/RE-UE4SS) → `Mods/shared/` (UHT-Compatible-Header-Generator)
