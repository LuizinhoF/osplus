# `docs/engine/` — engine reality of Omega Strikers

The canonical answer to *"how does this game work in UE / UE4SS
terms?"* — UClasses, UFunctions, runtime data shapes, hook patterns,
phase models. Everything below the `docs/game/` player-perception
layer.

This subtree is the **destination** for the engine-side contents
of [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md). KB started as one
~850-line monolith and was migrated topic-by-topic into the
per-topic files listed below across three batches in 2026-05; the
migration is now complete and **KB itself is a redirect index**.
The OSPlus-internal architecture sections of the original KB
(Lua module architecture, network relay) landed in
[`docs/architecture/`](../architecture/) instead — see the
[migration history](#migration-history) below for the full mapping.

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

Per-topic files migrated out of `KNOWLEDGEBASE.md`. Migration
complete as of batch 3 (2026-05-01); every topic below is **live
and canonical** (KB itself is now a redirect index).

| Doc | Status | What it owns |
|---|---|---|
| [`overview.md`](./overview.md) | **migrated** (batch 1, 2026-05-01) | Engine + UE4SS primer (UE 5.1.0, UE4SS 3.0.1, Prometheus module, OdyUI, project paths) |
| [`setup.md`](./setup.md) | **migrated** (batch 1, 2026-05-01) | Paths, install layout, INI config, pak packaging, maps table |
| [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md) | **migrated** (batch 1, 2026-05-01) | 3.0.1 anchor, Lua API, common pitfalls, version-sensitive bugs (out-param marshaling, multicast delegate no-op, `ExecuteInGameThread` corruption, etc.) |
| [`widgets.md`](./widgets.md) | **migrated** (batch 1, 2026-05-01) | UMG-only HUD model, BPModLoaderMod lifecycle, asset loading, actor spawning, material setup, widget catalog, ScrollBox crash root-cause, EditableText/Input Mode/Visibility quirks, GameInstance persistence, the game's own widget tree |
| [`game-state.md`](./game-state.md) | **migrated** (batch 2, 2026-05-01) | `GameState_Game_C` / `GameState_Tutorial_C`: phase model, UFunctions, detection patterns, `CurrentMatchSeed` |
| [`player-state.md`](./player-state.md) | **migrated** (batch 2, 2026-05-01) | `PlayerState_Game_C`: UFunctions, `DamageChanged`, `SpawnEffectsOnCharacterKnockedOut`, etc. |
| [`identity-and-api.md`](./identity-and-api.md) | **migrated** (batch 2, 2026-05-01) | `PMIdentitySubsystem`, Clarion / Prometheus API, `MeResponseV1`, `PlayerNamePrivate` caveats |
| [`data-model.md`](./data-model.md) | **migrated** (batch 2, 2026-05-01) | `PMPlayerMatchSummary`, `EPMEndOfGameStat` enum, runtime data shapes |
| [`rock-and-strike.md`](./rock-and-strike.md) | **migrated** (batch 3, 2026-05-01) | `PMRockCharacter`, `LastRedirectKnockBack`, `EKnockBackType::Redirect = 2`, `StrikeReleased` / `StrikeDragged` |
| [`strikers.md`](./strikers.md) | **migrated** (batch 3, 2026-05-01) | Internal Striker name table + `C_<InternalName>_C` runtime pattern, content folder layout, utility folders |
| [`open-questions.md`](./open-questions.md) | **migrated** (batch 3, 2026-05-01) | Cross-cutting RE TODO catalog + resolved-questions table |

**Engine surface for Awakenings is intentionally not in this
folder.** Per [glossary → "Awakening"](../glossary.md#awakening),
the engine surface is **blocked on probe** — no `awakenings.md`
exists yet. The first feature that touches Awakenings forces a
Stage-3 RE pass, the result of which lands as a new doc here
alongside its sibling per-topic files. Until then,
[`docs/game/awakenings.md`](../game/awakenings.md) covers the
player-side reality.

The OSPlus-internal architecture sections of the original KB
landed in [`docs/architecture/`](../architecture/) instead, since
they describe the *mod's* shape (Lua modules, IPC, sidecar, relay)
rather than the underlying engine. See [migration history](#migration-history)
for the full mapping.

## Reading orders for common tasks

| Task | Suggested reads |
|---|---|
| New-to-engine onboarding | [`overview.md`](./overview.md) → [`setup.md`](./setup.md) → [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md) → [`game-state.md`](./game-state.md) |
| Adding/changing identity-related code | [`identity-and-api.md`](./identity-and-api.md) → [`player-state.md`](./player-state.md) → relevant learnings on `PlayerNamePrivate` |
| Working on Core / puck mechanics | [`rock-and-strike.md`](./rock-and-strike.md) → [`data-model.md`](./data-model.md) → [`game-state.md`](./game-state.md) (for match-state context) |
| Targeting a specific Striker | [`strikers.md`](./strikers.md) → [`player-state.md`](./player-state.md) (for Pawn handle) → [glossary → "Striker"](../glossary.md#striker) |
| Building new in-match UI | [`widgets.md`](./widgets.md) → [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md) (for ScrollBox crash + EditableText bugs) |
| Capturing per-match stats | [`data-model.md`](./data-model.md) → [`player-state.md`](./player-state.md) → [`game-state.md`](./game-state.md) |
| Writing a new UE4SS hook | [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md) → relevant [`game-state.md`](./game-state.md) / [`player-state.md`](./player-state.md) UFunction list |
| Picking up an RE probe | [`open-questions.md`](./open-questions.md) → the per-topic doc the question belongs to |

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

Migration from `KNOWLEDGEBASE.md` happened topic-by-topic, one
branch per batch of 3–5 related topics, completed across three
batches in 2026-05. Each batch:

1. Lifted the relevant KB section into a new per-topic file under this folder (or into [`docs/architecture/`](../architecture/) when the content belonged there).
2. Improved structure on the way (TOC, conventions above, cross-references to `docs/game/` and `docs/glossary.md`).
3. Replaced the corresponding KB section with a short stub.
4. Updated this README's status table from **TBD** to **migrated**.
5. Updated [`docs/glossary.md`](../glossary.md) cross-references where applicable.

| Batch | Date | Topics migrated | Branch |
|---|---|---|---|
| Batch 1 (foundations) | 2026-05-01 | `overview.md`, `setup.md`, `ue4ss-version-and-gotchas.md`, `widgets.md` | `docs/engine-migration-batch-1` |
| Batch 2 (state + identity) | 2026-05-01 | `game-state.md`, `player-state.md`, `identity-and-api.md`, `data-model.md` | `docs/engine-migration-batch-2` |
| Batch 3 (content + catalog + wrap) | 2026-05-01 | `rock-and-strike.md`, `strikers.md`, `open-questions.md`; KB's "Lua Module Architecture" + "Network Relay Architecture" sections redirected to [`docs/architecture/mod-scripts.md`](../architecture/mod-scripts.md) and the new [`docs/architecture/relay.md`](../architecture/relay.md). Awakenings deferred — engine surface blocked on probe; player-side covered by [`docs/game/awakenings.md`](../game/awakenings.md). | `docs/engine-migration-batch-3` |

KB itself is now a **redirect index** (every section is a stub
pointing to its new home). New engine knowledge lands in the
per-topic file, not in KB. If a future probe creates a need for
a new engine topic (e.g. `awakenings.md` once the engine surface
is catalogued), add it under this folder and update the table
above.

## When this subtree lies

These docs are only as accurate as the most recent migration pass /
probe. If you find something here that contradicts what the engine
actually does:

1. The engine is the truth. Open the doc, fix the inaccuracy in the same branch as the work that exposed it.
2. If a TBD doc is blocking your feature work, promote it: cut a `docs/engine-<topic>` branch, do a migration pass (or a fresh probe pass for genuinely-new content), ship.
3. Update [`docs/glossary.md`](../glossary.md) in the same branch if your change invalidates a glossary entry's claim.

This subtree is referenced from [`AGENTS.md`](../../AGENTS.md)
pre-work reading as the canonical engine reference; see the
batch-3 migration history above for the full mapping back to
the (now-stubbed) sections of `KNOWLEDGEBASE.md`.
