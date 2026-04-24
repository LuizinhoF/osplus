---
applyTo: "{mod/**,ue-assets/**,KNOWLEDGEBASE.md}"
---

# OSPlus mod architecture — Lua/BP boundary

Source of truth: [.cursor/rules/mod-architecture.mdc](../../.cursor/rules/mod-architecture.mdc) and [docs/architecture/state-contract.md](../../docs/architecture/state-contract.md).

Every piece of mod state has **one canonical owner** (no mirroring):

| Bucket | Owner | Examples |
|---|---|---|
| UI-reactive state | Blueprint | `IsTyping`, `IsExpanded`, current channel/tab, focus state |
| Domain / operational state | Lua | message arrays, IPC queues, sidecar PID, room codes, timers, cached widget refs |
| Derived display values | BP holds, Lua pushes | `ChatHistory` text, currency display, badge counts |

Before writing a new feature, declare its boundary in the Lua module header (BP-owned / Lua-owned / Lua→BP push / BP→Lua events). If a piece of state doesn't fit cleanly into one bucket, the design is wrong.

**Cooker:** always cook with `CanUseUnversionedPropertySerialization=False` in `[Core.System]` of `DefaultEngine.ini`. Without it, complex widgets (ScrollBox etc.) crash on deserialization. See [KNOWLEDGEBASE.md](../../KNOWLEDGEBASE.md) for the full RCA.

**`ModActor`** at the root of `Content/Mods/OSPlus/` — do not rename or move. BPModLoaderMod hardcodes the path.
