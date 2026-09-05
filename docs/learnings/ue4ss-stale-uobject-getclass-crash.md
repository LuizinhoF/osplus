# UE4SS stale UObject wrappers make `GetClass()` a native crash boundary

| Field | Value |
|---|---|
| Date | 2026-07-28 |
| Area | mod / UE4SS |
| Tags | `ue4ss-3.0.1, uobject, getclass, stale-wrapper, access-violation, lifecycle, home-hub` |
| Status | `confirmed` |

## Symptom

The first event-driven update notice reached the Home Hub, but the game crashed
about five seconds after its first one-hertz presentation probe. Lua logged no
error because the process died in native UE4SS code:

- `EXCEPTION_ACCESS_VIOLATION`, reading address `0x10`
- `UE4SS.dll+0x229E17`
- process uptime: 35 seconds
- crash signature:
  `DB2AE62162891D73923BD46FE8535527A76655D2`

The active game log was then overwritten when `CrashReportClient.exe` loaded
the same UE4SS proxy. The Unreal crash folder, rather than the current
`UE4SS.log`, is the canonical artifact for this incident.

## Root cause

The update module polled `Router_OutOfGame_C:GetTopOfStack(...)`, then filtered
the returned object with:

```lua
object:GetClass():GetFName():ToString()
```

A top-of-stack Lua wrapper survived after its remote Unreal object had been
destroyed. Lua still saw non-nil userdata, but UE4SS's remote pointer was null.
`pcall` could not catch the resulting C++ access violation.

The exact matching experimental UE4SS archive
`zDEV-UE4SS_v3.0.1-944-g0196ef29.zip` was recovered from the upstream release
archive. Its `UE4SS.dll` SHA-256 exactly matches the installed DLL. Symbolizing
the minidump with its PDB resolves the fault to:

- `RC::LuaType::construct_uclass`
- `UE4SS/src/LuaType/LuaUObject.cpp:384`
- `lua_object.get_remote_cpp_object()->GetClassPrivate()`

The calling bridge is the Lua `UObject:GetClass()` registration at
`UE4SS/include/LuaType/LuaUObject.hpp:536-539`. That bridge does not null-check
the remote object before dereferencing it.

This falsifies the leading loading-widget-property hypothesis. The crashing
process also predated the later `LoadingScreenOdyWidget` unwrap deployment, so
that one-line change was not running in this session.

## Fix

`update_notification.lua` no longer continuously polls the router or reads a
loading-widget property:

- Home Hub navigation and
  `OdyUIRouter:OnMenuDisplayStateChanged` own visit lifetime.
- The collapsed notice is reparented into
  `WBP_HomeHub_PC_C.UIContainer`, alongside the native `PlayPanel`, before it
  is shown. The Home Hub/loading transition therefore covers it naturally.
- Router `AnimatingIn` prepares the native attachment and `Showing` permits
  the sound and one-shot presentation.
- A map load performs one immediate read of the Home Hub's own `DisplayState`
  to cover a missed startup event. There is no delayed confirmation and no
  repeated router-object lookup.
- An async `update_available` IPC fact queues at most one game-thread
  presentation attempt after the Home Hub reports `Showing`.
- Match completion reuses chat's already-proven match detector through a
  callback instead of adding a second reflected polling loop.

Lifecycle callback class filters now parse the leading class token from
`UObject:GetFullName()`. In this pinned UE4SS build that bridge checks whether
the remote pointer is null and returns `nil`; it does not blindly dereference
the pointer like `GetClass()`.

## Lesson

Lua userdata truthiness and `pcall` are not UObject-lifetime guarantees.
Against this UE4SS build:

1. Prefer engine lifecycle events over repeated discovery of transient UI
   objects. When an event can be missed at startup, read the lifecycle owner's
   current state once rather than inventing a settle timer.
2. Never call `GetClass()` merely to filter a lifecycle callback or a router
   result. Use the null-guarded `GetFullName()` path and parse its class token.
3. Treat every periodic reflected lookup as an allocation and stale-reference
   opportunity. If an event already owns the state transition, do not poll it.
4. Preserve the Unreal crash folder before relaunching; CrashReportClient can
   overwrite the useful UE4SS log.

## Related

- Files: `mod/OSPlus/scripts/update_notification.lua`,
  `mod/OSPlus/scripts/chat.lua`, `mod/OSPlus/scripts/main.lua`
- Corrects:
  [`home-hub-visibility-requires-router-and-loading-state`](./home-hub-visibility-requires-router-and-loading-state.md)
- Companion:
  [`customization-screen-widgetswitcher-architecture`](./customization-screen-widgetswitcher-architecture.md),
  [`profile-tick-userdata-allocation-leak`](./profile-tick-userdata-allocation-leak.md)
- Crash artifact:
  `%LOCALAPPDATA%/OmegaStrikers/Saved/Crashes/UECC-Windows-250BDF694F4725C67996BC8BA35A3161_0000`
