# Engine overview

The *"what is Omega Strikers built on, and what does that constrain"*
doc — first read for any agent touching engine code. Distilled from
[`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md) §"Game Engine Facts" and
§"Engine & Modules" (under "Omega Strikers — Game Internals").

> **Status:** seeded 2026-05-01 from
> [`KNOWLEDGEBASE.md`](../../KNOWLEDGEBASE.md).
>
> **Stability:** the engine + UE4SS version pins are stable across
> seasons (Odyssey hasn't re-engined the game since launch). The
> module / class naming conventions are also stable. Re-validate
> only on major engine bump (would be a `KNOWLEDGEBASE.md`-shaking
> event, not a normal patch).

This doc is the *facts*; the *patterns and gotchas* of working
against UE4SS 3.0.1 specifically live in
[`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md);
the *paths and project-config* live in [`setup.md`](./setup.md).

## TL;DR

- **Engine: Unreal Engine 5.1.0 runtime.** Not 5.1.1, not 5.2,
  not anything from the launcher — Odyssey ships against UE 5.1.0
  source-built. Modding requires the source-built 5.1.0 editor
  too; the launcher 5.1.1 will silently corrupt complex widgets.
- **Two gameplay modules: `Prometheus` (game logic) + `OdyUI`
  (UI framework).** Anything starting with `PM*` is a Prometheus
  class. Anything in the `OdyUI` namespace is the UI substrate.
  These names are everywhere in cooked content paths and runtime
  class names; recognizing them is half of navigating the engine.
- **Two meanings of "Prometheus" — distinguish them.** The UE
  module is one thing; the Odyssey backend HTTP API the
  community calls "Prometheus" is a separate thing. Both meanings
  are active in this codebase. See [§"The two 'Prometheus'es"](#the-two-prometheuses).
- **DX11 + SM5 only.** No Lumen, no virtual shadow maps, no mesh
  distance fields, no DX12 (even if your hardware supports it).
  Cook against this baseline or assets break in-game.
- **UMG-only HUD.** The game uses UMG widgets via `OdyHUD` +
  `UIRouter` exclusively — Canvas-based HUD drawing is
  unreachable. The implications for mod UI rendering are
  documented in [`widgets.md`](./widgets.md).
- **UE4SS 3.0.1 runtime.** The Lua marshaling layer is the most
  patch-volatile surface OSPlus depends on; every UE4SS docs /
  issue lookup must be anchored to this version. Detail in
  [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md).

## The engine pin

| Property | Value | Source |
|---|---|---|
| Engine version (runtime) | **UE 5.1.0** | Sentry crash metadata (confirmed) |
| Engine version (modding editor) | **UE 5.1.0 source-built** | Empirically required — see [§"Why source-built 5.1.0"](#why-source-built-510) |
| Internal project name | `OmegaStrikers` | Cooked content paths |
| Shipping config | `Shipping`, DX11 / SM5 | `DefaultEngine.ini` constraints |
| UE4SS runtime | **3.0.1** | `Binaries/Win64/ue4ss/` install on the user's machine; pinned 2026-04-25 |

The engine + UE4SS version pins are load-bearing for every other
fact in this subtree. When *any* fact here turns out to be wrong,
the first question is "did either of these versions move?"

### Why source-built 5.1.0

Two engine builds matter for OSPlus:

1. **The runtime** — UE 5.1.0, what the *player* runs. Locked
   by Odyssey; we don't get a vote.
2. **The editor used for cooking** — must also be UE 5.1.0
   source-built. **Not** the Epic-launcher 5.1.1.

The launcher 5.1.1 will *appear* to cook content correctly:
simple widgets (CanvasPanel, VerticalBox, SizeBox, Border)
serialize identically across the 5.1.x line so a quick smoke
test passes. The trap is complex widgets — `ScrollBox` is the
known canary — whose schema differs by even a single property
between launcher 5.1.1 and Odyssey's 5.1.0 fork. Schema drift
+ unversioned property serialization (the cooker's default) =
silent FName-index garbage at deserialization, which crashes
the game during pak load.

The fix has two prongs:
- **Cook with source-built 5.1.0** to minimize the schema drift
  surface area.
- **Set `CanUseUnversionedPropertySerialization=False`** in
  `DefaultEngine.ini` to embed property names in serialized
  data, making the deserializer match by name instead of by
  index. See [`setup.md` → "DefaultEngine.ini"](./setup.md#defaultengineini)
  and [`widgets.md` → "ScrollBox crash"](./widgets.md#scrollbox-crash--root-cause).

Even with `CanUseUnversionedPropertySerialization=False`, schema
drift still causes occasional surprises on complex widgets. The
source-built 5.1.0 editor minimizes this.

The full external-paths set (where the source-built editor lives,
where the game install is, where the UE project is) is in
[AGENTS.md → "External paths (non-discoverable)"](../../AGENTS.md#external-paths-non-discoverable).

## The two gameplay modules

| Module | Namespace | What lives there |
|---|---|---|
| **`Prometheus`** | `/Script/Prometheus.*`, `/Game/Prometheus/...` | All gameplay: characters (Strikers), abilities, the Core (called "Rock" internally), goals, barriers, match state, player state, identity, awakenings, gear, maps. Class prefix `PM*` (e.g., `PMRockCharacter`, `PMPlayerState`, `PMIdentitySubsystem`). |
| **`OdyUI`** | `/Script/OdyUI.*` | The widget framework, the HUD substrate (`OdyHUD`), the `UIRouter` for screen transitions, the binding system (`FOdy*Binding` family). The HUD class hierarchy chain that goes through `OdyHUD` lives here. |

In practice:

- **Almost every "where does this game data live?" question
  routes to `Prometheus`** — character internals, match state,
  identity, per-match counters.
- **Almost every "where does this UI element come from?"
  question routes to `OdyUI`** — widget framework, persistent
  widgets, HUD plumbing.
- **The OS-specific Blueprint content** (per-Striker BP classes,
  arena maps, Core actor, individual widget BPs like
  `WBP_HomeHub_PC_C`) lives at `/Game/Prometheus/...` paths. It
  uses both modules but is content, not code.

Class-name prefixes are the fastest grep:

- `PM*` → Prometheus
- `Ody*` → OdyUI (especially `OdyHUD`, `OdyUITextBinding`,
  `OdyPlayerController`)
- `WBP_*_C` → cooked Blueprint widget (UMG)
- `BP_*_C` → cooked Blueprint actor
- `C_*_C` → playable character class (e.g., `C_FlexibleBrawler_C`
  = Juliette; see [`strikers.md` → planned](./README.md))
- `GameMode_*_C`, `GameState_*_C`, `PlayerState_*_C`,
  `PlayerController_*_C`, `GameInstance_*_C` → standard UE
  framework classes, OS-specific subclasses

## The two "Prometheus"es

> *Naming note:* "Prometheus" refers to **two things** in the
> Omega Strikers universe, and both are Odyssey-chosen. This is
> a constant source of confusion in agent-driven RE work.

| Meaning | What it is | Where it shows up |
|---|---|---|
| **The UE client module** | The `Prometheus` UE gameplay module (above). | UClass names (`PM*`), cooked content paths (`/Game/Prometheus/...`), engine code. |
| **The backend HTTP API** | A separate JWT-authenticated HTTP API that the client talks to for player data, matchmaking, persistence. The community named it "Prometheus" because the schema/ID naming from the UE module leaks into the API responses. Every Omega Strikers tracker (stats.omegastrikers.gg, clarioncorp.net, strikr.gg) taps this same backend. | Network traffic, every external tracker, anything OSPlus might do that crosses into player-account-level data. |

When this docset says "Prometheus":

- In `docs/engine/` — defaults to **the UE module**, unless the
  context is clearly about HTTP / backend / `MeResponseV1` /
  player aggregates (which routes to `identity-and-api.md` for
  the backend side).
- In `docs/glossary.md` — both meanings appear, distinguished
  by entry context.
- In `KNOWLEDGEBASE.md` (the source) — the section
  ["Backend Ecosystem — Odyssey's 'Prometheus' API"](../../KNOWLEDGEBASE.md)
  is exclusively the backend; everything else means the module
  unless it explicitly says "API."

The single canonical bridge is the **Prometheus ID**: a 24-char
hex MongoDB ObjectID issued by the backend, exposed as
`PMPlayerPublicProfile.PlayerId` on the client. The same hex
string is the player's canonical identifier on the backend API.
That's *why* the community kept the name — the namespaces are
genuinely shared. See [glossary → "Player identity"](../glossary.md#player-identity)
and the planned `identity-and-api.md` for the full bridge.

## Engine-side architectural facts that cascade everywhere

### UMG-only HUD

The game's HUD does **not** use Canvas drawing. UI happens via
UMG widgets (UserWidgets) routed through `OdyHUD` →
`UIRouter`. Concretely:

- `ReceiveDrawHUD` is a `BlueprintImplementableEvent` that the
  game's HUD Blueprint (`HUD_Practice_C`) doesn't implement —
  hooking it from UE4SS registers but never fires.
- `DrawRect`, `DrawText`, `DrawLine`, `DrawTexture`,
  `DrawMaterial` etc. on `AHUD` are never called by the game.
- All game UI goes through `OdyHUD` → `UIRouter` →
  Blueprint widgets.

Consequences for OSPlus:

- A mod cannot add HUD elements via Canvas drawing.
- A mod must use UMG: cook a `WBP_*` widget Blueprint, ship it
  in the pak, instantiate it from Lua, add to viewport. The
  full pattern is in [`widgets.md`](./widgets.md).
- The HUD class hierarchy (`HUD_Practice_C → PMHUDBase → OdyHUD →
  AHUD → AActor → UObject`) is documented in
  [`widgets.md` → "HUD class hierarchy"](./widgets.md#hud-class-hierarchy).

### `GameInstance_Base_C` is the persistent root

`GameInstance_Base_C` persists across **all** map loads. Widgets
added to its viewport persist too. This is why OSPlus's chat
widget survives the lobby → match → post-match → lobby cycle:
it's parented to `GameInstance_Base_C`, not to the level player.
Detail in [`widgets.md` → "GameInstance persistence"](./widgets.md#gameinstance-persistence-the-persistent-root).

### Phase detection is not enum-based (yet)

The match progresses through phases (Main Menu → Character Select
→ Active Gameplay → Awakening Select → ...) but the *phase enum
values* are not catalogued. Phase detection is done by
**class-tuple inspection** instead — checking which combination
of `GameStateBase`, `PlayerController`, `PlayerState`, and `Pawn`
classes are currently live. Full machinery is in the planned
`game-state.md` (KB §"Game Lifecycle & Phase Detection" until
that doc lands).

### UE4SS has no networking

UE4SS Lua **cannot** open sockets, make HTTP requests, or do
WebSockets. The only "network" available from Lua is file IPC
(read/write to the local filesystem). Any feature that needs
networking must be split: Lua mod ↔ file IPC ↔ external sidecar
process ↔ network. This is why OSPlus has a Node.js sidecar in
the first place. Architecture is in
[`docs/architecture/`](../architecture/).

## Cross-references

- **Project paths, install layout, INI config:** [`setup.md`](./setup.md)
- **UE4SS Lua API + version-sensitive bugs:** [`ue4ss-version-and-gotchas.md`](./ue4ss-version-and-gotchas.md)
- **HUD / widget rendering details:** [`widgets.md`](./widgets.md)
- **Engine-side bridges to player concepts:** [`docs/glossary.md`](../glossary.md)
- **Player-side equivalent (what the player perceives):** [`docs/game/overview.md`](../game/overview.md)
- **OSPlus-internal architecture (Lua module split, IPC, sidecar, relay):** [`docs/architecture/`](../architecture/)
- **External non-discoverable paths (game install, UE editor, source-built UE):** [AGENTS.md → "External paths"](../../AGENTS.md#external-paths-non-discoverable)
- **Sibling docs index:** [`docs/engine/README.md`](./README.md)

## Open questions

(None at the overview layer. Module-specific open questions live
in their respective per-topic engine docs; cross-cutting RE TODOs
live in the planned `open-questions.md`.)
