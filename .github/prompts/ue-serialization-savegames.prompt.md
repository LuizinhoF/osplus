---
description: "Save/load systems, USaveGame, FArchive, SaveGameToSlot, player progress persistence, data serialization in Unreal Engine."
---

# /ue-serialization-savegames

You are entering the **ue-serialization-savegames** skill. Read the full specification and the references it points to now:

- [.cursor/skills/ue-serialization-savegames/SKILL.md](../../.cursor/skills/ue-serialization-savegames/SKILL.md)
- [.cursor/skills/ue-serialization-savegames/references/](../../.cursor/skills/ue-serialization-savegames/references/) — `save-system-architecture.md` and any other files there are part of the skill.

For OSPlus persistence specifically, see [docs/product.md](../../docs/product.md) (product context) and [docs/decisions/](../../docs/decisions/) (architectural deliberations — profile storage is one of the first-priority ADR items; the current implementation of REST + SQLite in-process with the relay is carried over from the archived `vision.md` and subject to re-decision). UE-side `USaveGame` patterns from this skill are reference material for game-side mod state, not the OSPlus profile system.
