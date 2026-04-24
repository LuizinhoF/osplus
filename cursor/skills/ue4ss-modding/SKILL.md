---
name: ue4ss-modding
description: "Use this skill when working with UE4SS Lua scripts, Blueprint mods via BPModLoaderMod, custom pak files, or widget creation in OSPlus. Covers the Lua/BP boundary decision, thread context, and points at reference sheets for full Lua API (lua-api.md), ModActor pattern + cooking/packaging (mod-actor-pattern.md), and common crashes (pitfalls.md)."
metadata:
  version: 2.0.0
---

# UE4SS modding — OSPlus context

OSPlus is a UE4SS Lua + BPModLoaderMod mod for Omega Strikers (UE 5.1.0). If you're reading this, you're about to do one of:

- Call into UE from Lua (find objects, invoke UFunctions, hook events).
- Design a new widget / UI surface (Blueprint-owned, Lua-driven).
- Load or cook assets for the pak.
- Debug a native crash.

This skill gives you the *decision* and the *entry points*. Depth is in the references and in the live codebase.

## Read before acting

1. **Live reference implementations.** OSPlus has working Lua mods — read them instead of writing new patterns from scratch:
   - `mod/OSPlus/scripts/main.lua` — tick loop, hook registration, module wiring.
   - `mod/OSPlus/scripts/chat.lua` — widget discovery, property reads, native-crash avoidance via ref-drop.
   - `mod/OSPlus/scripts/ipc.lua` — file IPC, Lua ↔ Blueprint function calls.
2. **`KNOWLEDGEBASE.md`** (repo root) — engine/game-internals reference. Search here before asking anything about UE 5.1 or Omega Strikers specifics.
3. **`docs/architecture/state-contract.md`** — the Lua/BP boundary rules (who owns what state). Mandatory before designing a new UI-touching feature.
4. **`.cursor/rules/mod-architecture.mdc`** and **`lua-conventions.mdc`** — always-loaded rules for the mod. If this skill and those rules disagree, the rules win.

## The core decision: Lua vs Blueprint vs Hybrid

For any new functionality, pick by asking: *"who owns the authoritative state?"*

| Lives in | Lua | Blueprint | Both |
|---|---|---|---|
| Owns | Operational / domain state, timers, IPC, logging, map-transition reset | UI-reactive state (visibility, focus, text bindings), widget tree, animations | Display values (BP holds, Lua pushes via function call) |
| Files | `mod/OSPlus/scripts/*.lua` | Cooked assets under `/Game/Mods/OSPlus/` | Both sides talk via UFunctions the BP exposes |
| Examples | `chat.isTyping()`, `chat.pending[]`, tick counters | `IsVisible`, `MessageList` ListView, input FocusPolicy | `MessageRows` list, `IsTyping` flag |

**If you can do it in Blueprint, do it in Blueprint.** Lua is the escape hatch for things BP can't do (native hooks, file I/O, string manipulation, cross-map persistence). Complex widgets (`ScrollBox`, `ListView`, `EditableTextBox`) **must** be created by Blueprint — creating them from Lua crashes. See `references/mod-actor-pattern.md`.

## Thread context — the silent crash source

| Callback / API | Runs on | Safe to call engine functions? |
|---|---|---|
| `RegisterHook` callbacks | Game thread | Yes |
| `RegisterLoadMapPostHook` | Game thread | Yes |
| `RegisterKeyBind` callbacks | **Not** game thread | **No — wrap in `ExecuteInGameThread(fn)`** |
| `RegisterConsoleCommandHandler` | Game thread | Yes |
| `LoopAsync(ms, fn)` | **Not** game thread | **No — wrap in `ExecuteInGameThread(fn)` if touching UObjects** |
| `LoadAsset` | **Must** be called from game thread | — |

OSPlus's main tick uses `LoopAsync(30, ...)`, so any UObject access inside the tick is already wrapped via the chat/ipc module helpers. Don't reinvent the wrap — call the module-level API that already does it.

## Native crashes are NOT caught by `pcall`

`pcall` catches Lua-level errors. It does **not** catch C++ access violations when the engine has freed a UObject (map transition, BPModLoader respawn, GC). The only defense is **ref-drop discipline**: drop the reference *before* it goes stale. Canonical case: `chat.lua:reset()` called from `RegisterLoadMapPostHook`. Full pattern in `lua-conventions.mdc` (load-bearing rule; read it).

## References (load on demand)

- [`references/lua-api.md`](references/lua-api.md) — full Lua API: finding objects, loading assets (`GetAsset` vs `LoadAsset`), creating objects, calling UFunctions, hook registration, `NotifyOnNewObject`.
- [`references/mod-actor-pattern.md`](references/mod-actor-pattern.md) — the ModActor + BPModLoaderMod pattern (community-standard for complex UI), UE editor setup, pak packaging, Lua ↔ BP communication via custom events and UFunctions, cooking + UnrealPak.
- [`references/pitfalls.md`](references/pitfalls.md) — common pitfalls table (what crashes and why), debugging techniques, UE4SS log location, widget-class discovery snippets.

## External docs

- UE4SS: https://docs.ue4ss.com/ — API reference.
- UE4SS GitHub: https://github.com/UE4SS-RE/RE-UE4SS — source, issues, releases.
- Palworld Modding Wiki (BP+Lua integration): https://pwmodding.wiki/docs/developers/ue4ss-modding/ — community patterns.
