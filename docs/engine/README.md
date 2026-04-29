# `docs/engine/` — engine reality of Omega Strikers

The canonical answer to *"how does this game work in UE / UE4SS
terms?"* — UClasses, UFunctions, runtime data shapes, hook patterns,
phase models. Everything below the `docs/game/` player-perception
layer.

This subtree is the **planned destination** for the contents of
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md), which currently holds all
of this knowledge in one ~750-line monolith. KB is being migrated
topic-by-topic into the per-topic files listed below; until each topic
is migrated, **`KNOWLEDGEBASE.md` remains the canonical source for
that topic**. See [migration sequence](#migration-sequence) below for
what's been promoted out of KB and what's still in flight.

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

## What's in this folder (planned)

Per-topic files migrated out of `KNOWLEDGEBASE.md`. Items marked
**migrated** are live; items marked **TBD** are planned slots that
still resolve to KB until promoted.

| Doc | Status | KB section it owns |
|---|---|---|
| `overview.md` | **TBD** | Engine + UE4SS primer (UE 5.1.0, UE4SS 3.0.1, Prometheus module, OdyUI, project paths) |
| `setup.md` | **TBD** | Paths, install layout, build modules, maps table |
| `ue4ss-version-and-gotchas.md` | **TBD** | 3.0.1 anchor + version-sensitive bugs (out-param marshaling, multicast delegate no-op, etc.) |
| `game-state.md` | **TBD** | `GameState_Game_C` / `GameState_Tutorial_C`: phase model, UFunctions, detection patterns, `CurrentMatchSeed` |
| `player-state.md` | **TBD** | `PlayerState_Game_C`: UFunctions, `DamageChanged`, `SpawnEffectsOnCharacterKnockedOut`, etc. |
| `identity-and-api.md` | **TBD** | `PMIdentitySubsystem`, Clarion / Prometheus API, `MeResponseV1`, `PlayerNamePrivate` caveats |
| `data-model.md` | **TBD** | `PMPlayerMatchSummary`, `EPMEndOfGameStat` enum, runtime data shapes |
| `rock-and-strike.md` | **TBD** | `PMRockCharacter`, `RedirectRock`, knockback types, Strike input events |
| `widgets.md` | **TBD** | WBP hierarchy, persistent widgets, `WBP_ReactionButtonPanel_C`, ChatBox, ScrollBox usage |
| `strikers.md` | **TBD** | Internal Striker name table + character-class mapping |
| `awakenings.md` | **planned, blocked on probe** | Awakening data class + draft UI widget — TBD per [glossary entry](../glossary.md#awakening) |
| `open-questions.md` | **TBD** | RE TODO list (current "Pass-N candidates") |

Items marked **TBD** are slots reserved by intent, not yet drafted.
Don't add a feature that depends on a TBD doc without first promoting
that doc out of TBD via its own `docs/engine-<topic>` branch (or by
migrating the relevant KB section as part of the feature work).

## Reading orders for common tasks

Most of these still bottom out at `KNOWLEDGEBASE.md` until migration
completes; the file names below are the *destinations* — read the
linked KB section instead until each file lands.

| Task | Suggested reads |
|---|---|
| New-to-engine onboarding | `overview.md` → `setup.md` → `ue4ss-version-and-gotchas.md` → `game-state.md` |
| Adding/changing identity-related code | `identity-and-api.md` → `player-state.md` → relevant learnings on `PlayerNamePrivate` |
| Working on Core / puck mechanics | `rock-and-strike.md` → `game-state.md` (for match-state context) |
| Building new in-match UI | `widgets.md` → `ue4ss-version-and-gotchas.md` (for ScrollBox crash + EditableText bugs) |
| Capturing per-match stats | `data-model.md` → `player-state.md` → `game-state.md` |
| Writing a new UE4SS hook | `ue4ss-version-and-gotchas.md` → relevant `game-state.md` / `player-state.md` UFunction list |

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

## Migration sequence

Migration from `KNOWLEDGEBASE.md` happens topic-by-topic, one branch
per batch of 3-5 related topics. Each migration:

1. Lifts the relevant KB section into a new per-topic file under this folder.
2. Improves structure on the way (TOC, conventions above, cross-references to `docs/game/` and `docs/glossary.md`).
3. Replaces the corresponding KB section with a short stub: *"Migrated to [`docs/engine/<topic>.md`](./engine/<topic>.md)"*.
4. Updates this README's status table from **TBD** to **migrated**.
5. Updates [`docs/glossary.md`](../glossary.md) cross-references so they point at the new file.

Once every section in KB has been migrated, KB itself gets archived
with a final learning entry capturing what (if anything) was
consciously dropped in the migration. Until then, **KB is canonical
for any topic still marked TBD here**.

## When this subtree lies

These docs are only as accurate as the most recent migration pass /
probe. If you find something here that contradicts what the engine
actually does:

1. The engine is the truth. Open the doc, fix the inaccuracy in the same branch as the work that exposed it.
2. If a TBD doc is blocking your feature work, promote it: cut a `docs/engine-<topic>` branch, do a migration pass (or a fresh probe pass for genuinely-new content), ship.
3. Update [`docs/glossary.md`](../glossary.md) in the same branch if your change invalidates a glossary entry's claim.

This subtree is referenced from [`AGENTS.md`](../../AGENTS.md)
pre-work reading as the planned successor to `KNOWLEDGEBASE.md`.
