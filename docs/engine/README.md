# `docs/engine/` — engine reality of Omega Strikers

The canonical answer to *"how does this game work in UE / UE4SS
terms?"* — UClasses, UFunctions, runtime data shapes, hook patterns,
phase models. Everything below the `docs/game/` player-perception
layer.

This subtree is the **destination** for the contents of
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). KB started as one
~850-line monolith and is being migrated topic-by-topic into the
per-topic files listed below; until each topic is migrated, **KB
remains the canonical source for that topic**. See
[migration history](#migration-history) below for what's been
promoted out of KB and what's still in flight.

This subtree exists because OSPlus is a mod **layered onto a UE 5.1.0
+ UE4SS 3.0.1 game**, and the engine internals are the bedrock every
feature design eventually touches. The existing knowledge substrates
cover everything *but* the engine reality at navigable granularity:

| Substrate | Covers | Doesn't cover |
|---|---|---|
| [`docs/game/`](../game/) | Player-side reality: screens, UX, match flow, what the player perceives | UClass / UFunction names, runtime data shapes, hook patterns |
| [`docs/glossary.md`](../glossary.md) | Bidirectional concept catalog: player concept ↔ engine representation(s) | Detailed engine internals (catalog, not reference) |
| [`docs/architecture/`](../architecture/) | OSPlus-internal architecture: Lua/BP boundary, script ownership, per-tick discipline | The native UE/UE4SS layer OSPlus is a mod *on top of* |
| [`docs/learnings/`](../learnings/) | Single-finding diaries: one bug, one investigation, one outcome each | Synthesized engine reference for cross-cutting topics |
| **`docs/engine/` (this subtree)** | **Engine + UE4SS reality, organized for targeted reads** | **Player perception (above), OSPlus internals (above), single-finding diaries (above)** |

## What's in this folder

Per-topic files migrated out of `KNOWLEDGEBASE.md`. Items marked
**migrated** are live; items marked **TBD** are planned slots that
still resolve to KB until promoted.

| Doc | Status | KB section it owns |
|---|---|---|
| [`overview.md`](./overview.md) | **migrated** (batch 1, 2026-05-01) | Engine + UE4SS primer (UE 5.1.0, UE4SS 3.0.1, Prometheus module, OdyUI, project paths) |
| [`setup.md`](./setup.md) | **migrated** (batch 1, 2026-05-01) | Paths, install layout, INI config, pak packaging, maps table |
| [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md) | **migrated** (batch 1, 2026-05-01) | 3.0.1 anchor, Lua API, common pitfalls, version-sensitive bugs (out-param marshaling, multicast delegate no-op, `ExecuteInGameThread` corruption, etc.) |
| [`widgets.md`](./widgets.md) | **migrated** (batch 1, 2026-05-01) | UMG-only HUD model, BPModLoaderMod lifecycle, asset loading, actor spawning, material setup, widget catalog, ScrollBox crash root-cause, EditableText/Input Mode/Visibility quirks, GameInstance persistence, the game's own widget tree |
| `game-state.md` | **TBD** (batch 2) | `GameState_Game_C` / `GameState_Tutorial_C`: phase model, UFunctions, detection patterns, `CurrentMatchSeed` |
| `player-state.md` | **TBD** (batch 2) | `PlayerState_Game_C`: UFunctions, `DamageChanged`, `SpawnEffectsOnCharacterKnockedOut`, etc. |
| `identity-and-api.md` | **TBD** (batch 2) | `PMIdentitySubsystem`, Clarion / Prometheus API, `MeResponseV1`, `PlayerNamePrivate` caveats |
| `data-model.md` | **TBD** (batch 2) | `PMPlayerMatchSummary`, `EPMEndOfGameStat` enum, runtime data shapes |
| `rock-and-strike.md` | **TBD** (batch 3) | `PMRockCharacter`, `RedirectRock`, knockback types, Strike input events |
| `strikers.md` | **TBD** (batch 3) | Internal Striker name table + character-class mapping |
| `awakenings.md` | **planned, blocked on probe** (batch 3) | Awakening data class + draft UI widget — TBD per [glossary entry](../glossary.md#awakening) |
| `open-questions.md` | **TBD** (batch 3) | RE TODO list (current "Pass-N candidates") |

Items marked **TBD** are slots reserved by intent, not yet drafted.
Don't add a feature that depends on a TBD doc without first promoting
that doc out of TBD via its own `docs/engine-<topic>` branch (or by
migrating the relevant KB section as part of the feature work).

## Reading orders for common tasks

Items in **bold** are migrated and live; non-bold names are still
**TBD** and resolve to the linked KB section until promoted.

| Task | Suggested reads |
|---|---|
| New-to-engine onboarding | **[`overview.md`](./overview.md)** → **[`setup.md`](./setup.md)** → **[`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md)** → `game-state.md` (TBD) |
| Adding/changing identity-related code | `identity-and-api.md` (TBD) → `player-state.md` (TBD) → relevant learnings on `PlayerNamePrivate` |
| Working on Core / puck mechanics | `rock-and-strike.md` (TBD) → `game-state.md` (TBD, for match-state context) |
| Building new in-match UI | **[`widgets.md`](./widgets.md)** → **[`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md)** (for ScrollBox crash + EditableText bugs) |
| Capturing per-match stats | `data-model.md` (TBD) → `player-state.md` (TBD) → `game-state.md` (TBD) |
| Writing a new UE4SS hook | **[`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md)** → relevant `game-state.md` / `player-state.md` UFunction list (TBD) |

## Conventions across this subtree

- **Engine names use the runtime form.** `PlayerState_Game_C` (with
  the `_C` suffix), not `PlayerState_Game`. `WBP_ReactionModal_C`,
  not `WBP_ReactionModal`. The `_C` matters when you grep / probe.
- **Cross-reference player-side concepts** when they're known. *"`PMRockCharacter` is what the player calls the Core (see [glossary](../glossary.md#core-aka-rock))"* is one click of value; *"`PMRockCharacter` is the puck"* is half of one.
- **Don't duplicate player-side reality** that already lives in
  `docs/game/`. Link to it. This subtree describes what the engine
  exposes; `docs/game/` describes what the player perceives. They
  cross-reference; they don't restate each other.
- **Don't restate single-finding diaries.** Learnings live in
  `docs/learnings/<slug>.md`; engine docs link to them when relevant.
  If a learning's content has hardened into a stable engine fact,
  promote the fact into the engine doc and have the learning point
  forward to it.
- **Probe-confirmed vs. inferred.** When a fact comes from a runtime
  probe / dump, say so (*"observed via F4 dump in active gameplay"*).
  When it's inferred from naming, say so (*"likely a status effect,
  inferred from `Banish` enum value name"*). The reader needs to
  know which they can trust.
- **Open questions are first-class.** Each engine doc has an "Open
  questions" section at the bottom listing TBDs. These are work
  items, not noise — they're how the next agent knows what to probe.

## Migration history

Migration from `KNOWLEDGEBASE.md` happens topic-by-topic, one branch
per batch of 3-5 related topics. Each batch:

1. Lifts the relevant KB section into a new per-topic file under this folder.
2. Improves structure on the way (TOC, conventions above, cross-references to `docs/game/` and `docs/glossary.md`).
3. Replaces the corresponding KB section with a short stub: *"Migrated to [`docs/engine/<topic>.md`](./engine/<topic>.md)"*.
4. Updates this README's status table from **TBD** to **migrated**.
5. Updates [`docs/glossary.md`](../glossary.md) cross-references so they point at the new file (when applicable).

| Batch | Date | Topics migrated | Branch |
|---|---|---|---|
| Batch 1 (foundations) | 2026-05-01 | `overview.md`, `setup.md`, `ue4ss-version-and-gotchas.md`, `widgets.md` | `docs/engine-migration-batch-1` |
| Batch 2 (state + identity) | TBD | `game-state.md`, `player-state.md`, `identity-and-api.md`, `data-model.md` | TBD |
| Batch 3 (content + catalog + wrap) | TBD | `rock-and-strike.md`, `strikers.md`, `awakenings.md`, `open-questions.md`; redirect-stub the architecture-belonging KB sections (`Lua Module Architecture`, `Network Relay Architecture`) to `docs/architecture/` | TBD |

Once every section in KB has been migrated, KB itself becomes a
redirect index (similar to what
[`docs/game/OMEGA_STRIKERS_GAME.md`](../game/OMEGA_STRIKERS_GAME.md)
became after the player-side migration completed). Until then,
**KB is canonical for any topic still marked TBD here**.

## When this subtree lies

These docs are only as accurate as the most recent migration pass /
probe. If you find something here that contradicts what the engine
actually does:

1. The engine is the truth. Open the doc, fix the inaccuracy in the same branch as the work that exposed it.
2. If a TBD doc is blocking your feature work, promote it: cut a `docs/engine-<topic>` branch, do a migration pass (or a fresh probe pass for genuinely-new content), ship.
3. Update [`docs/glossary.md`](../glossary.md) in the same branch if your change invalidates a glossary entry's claim.

This subtree is referenced from [`AGENTS.md`](../../AGENTS.md)
pre-work reading as the planned successor to `KNOWLEDGEBASE.md`.
