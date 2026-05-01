# Omega Strikers Modding — Knowledgebase

> **Migration complete.** Per [ADR 0003](docs/decisions/0003-knowledge-substrate-structure.md),
> this monolithic doc has been fully decomposed into per-topic
> files under [`docs/engine/`](docs/engine/) (engine + UE4SS
> reality) and [`docs/architecture/`](docs/architecture/)
> (OSPlus-internal architecture). Every section here is now a
> redirect stub pointing at its new home; **read the new files,
> not this one.** This file is kept around so existing references
> in code comments, learnings, and old chat history still resolve
> to a recognizable heading.
>
> **Where to start instead:**
>
> - New agent / first-time engine read → [`docs/engine/overview.md`](docs/engine/overview.md)
> - OSPlus internal architecture (Lua modules, relay) → [`docs/architecture/`](docs/architecture/)
> - Engine ↔ player concept bridge → [`docs/glossary.md`](docs/glossary.md)
> - Full engine topic index → [`docs/engine/README.md`](docs/engine/README.md)
> - Engine RE TODO catalog → [`docs/engine/open-questions.md`](docs/engine/open-questions.md)
>
> **Migration history:**
>
> - **Batch 1 (2026-05-01):** §"Game Engine Facts", §"Game Paths",
>   §"UE Project Settings (Critical)", §"HUD System", §"Asset
>   Loading", §"Actor Spawning", §"Material Setup", §"Pak
>   Packaging", §"UE4SS Lua API", §"Common Pitfalls", §"Flipbook
>   Animation", and the "Engine & Modules" + "Maps" sub-sections of
>   §"Omega Strikers — Game Internals".
> - **Batch 2 (2026-05-01):** §"Backend Ecosystem — Odyssey's
>   'Prometheus' API", §"Per-match runtime data — what's reachable
>   from Lua", §"Game Lifecycle & Phase Detection", §"Player
>   Identity Reference", and the "Core Framework" + "Key UFunctions"
>   sub-sub-sections of "Class Hierarchy Reference".
> - **Batch 3 (2026-05-01):** §"Lua Module Architecture (v11+)"
>   (→ `docs/architecture/mod-scripts.md`), §"Network Relay
>   Architecture" (→ `docs/architecture/relay.md`), the "Characters"
>   sub-section of "Class Hierarchy Reference" (→
>   `docs/engine/strikers.md`), and §"Known Unknowns / Investigation
>   Needed" (→ `docs/engine/open-questions.md`). Strike-specific
>   detail centralized in `docs/engine/rock-and-strike.md`.

This was originally the single source of truth for "how things
work" in OSPlus's modding context. The historical context —
*"everything learned through trial and error while building the
custom ping system mod"* — explains why some of the early
prototype-era patterns (ping markers, sprite materials,
`CustomPings_P.pak`) appear throughout the older learnings.
That work *paid forward* the cooked-pak + UE4SS + sidecar
pipeline OSPlus runs on today; chat reused the substrate.

---

## Game Engine Facts

> **Migrated → [`docs/engine/overview.md`](docs/engine/overview.md).**
> Specifically: ["The engine pin"](docs/engine/overview.md#the-engine-pin)
> and ["The two gameplay modules"](docs/engine/overview.md#the-two-gameplay-modules).
> Section retained as a stub so existing references still resolve.

---

## Game Paths

> **Migrated → [`docs/engine/setup.md` → "Game install layout"](docs/engine/setup.md#game-install-layout-players-machine).**
> The KB's prototype-era paths (`CustomPings_P.pak`, `OmegaStonkers`
> minus the ` 5.1` suffix) were updated to current OSPlus paths
> during migration. Section retained as a stub so existing
> references still resolve.

---

## UE Project Settings (Critical)

> **Migrated → [`docs/engine/setup.md` → "DefaultEngine.ini"](docs/engine/setup.md#defaultengineini)
> and [→ "DefaultGame.ini"](docs/engine/setup.md#defaultgameini).**
> Both INI files are documented in full, including the
> "schema-stability cluster" (the `CanUseUnversionedPropertySerialization`
> trap, with the wrong-key-name false-friend called out) and the
> "renderer cluster" (DX11 / SM5 requirements).
> Section retained as a stub so existing references still resolve.

---

## HUD System — What Works and What Doesn't

> **Migrated → [`docs/engine/widgets.md` → "The cooked-pak rendering model"](docs/engine/widgets.md#the-cooked-pak-rendering-model).**
> Specifically: ["HUD class hierarchy"](docs/engine/widgets.md#hud-class-hierarchy),
> ["ReceiveDrawHUD does NOT fire"](docs/engine/widgets.md#receivedrawhud-does-not-fire),
> ["Canvas drawing functions are never called"](docs/engine/widgets.md#canvas-drawing-functions-are-never-called),
> ["What DOES work for UI"](docs/engine/widgets.md#what-does-work-for-ui).
> The engine reasoning ("UMG-only HUD") also lives in
> [`docs/engine/overview.md` → "UMG-only HUD"](docs/engine/overview.md#umg-only-hud).
> Section retained as a stub so existing references still resolve.

---

## Asset Loading — Proven Pattern

> **Migrated → [`docs/engine/widgets.md` → "Asset loading from cooked paks"](docs/engine/widgets.md#asset-loading-from-cooked-paks).**
> Includes the `findAsset` helper, the three-pattern Blueprint
> class loading recipe, and the rationale for falling back through
> multiple path formats. KB's prototype-era examples
> (`/Game/CustomPings/VFX/BP_PingMarker`) were replaced with the
> current OSPlus equivalents (`/Game/Mods/OSPlus/Chat/WBP_ModChat`)
> during migration, with a note about the rename.
> Section retained as a stub so existing references still resolve.

---

## Actor Spawning — Proven Pattern

> **Migrated → [`docs/engine/widgets.md` → "Actor spawning from cooked paks"](docs/engine/widgets.md#actor-spawning-from-cooked-paks).**
> Section retained as a stub so existing references still resolve.

---

## Material Setup — Lessons Learned

> **Migrated → [`docs/engine/widgets.md` → "Material setup"](docs/engine/widgets.md#material-setup).**
> Includes the master material requirements, the material instance
> override pattern (with the "override checkbox ON, value OFF"
> trap explained), and the common material bugs table.
> Section retained as a stub so existing references still resolve.

---

## Pak Packaging

> **Migrated → [`docs/engine/setup.md` → "Pak packaging"](docs/engine/setup.md#pak-packaging).**
> The KB's reference to a `package_pak.ps1` script is from the
> prototype era (`CustomPings_P.pak`); the current canonical
> harness is [`ue-assets/package_logicmod.ps1`](../../ue-assets/package_logicmod.ps1)
> per [`.cursor/rules/harnesses.mdc`](../../.cursor/rules/harnesses.mdc).
> Section retained as a stub so existing references still resolve.

---

## UE4SS Lua API — Key Functions

> **Migrated → [`docs/engine/ue4ss-version-and-gotchas.md` → "The Lua API surface"](docs/engine/ue4ss-version-and-gotchas.md#the-lua-api-surface).**
> Includes the UE4SS 3.0.1 build pin (and trust-ranking for sources
> of truth), lifecycle hooks, execution helpers, object lookup,
> class introspection, `RegisterHook` patterns, and `FVector` /
> `FRotator` creation via UEHelpers.
> Section retained as a stub so existing references still resolve.

---

## Common Pitfalls

> **Migrated → [`docs/engine/ue4ss-version-and-gotchas.md` → "Common pitfalls"](docs/engine/ue4ss-version-and-gotchas.md#common-pitfalls).**
> All twelve pitfalls preserved with cross-references to the
> deeper UE4SS-3.0.1-specific known bugs (`ExecuteInGameThread` +
> callback-registry corruption is now its own dedicated entry).
> Section retained as a stub so existing references still resolve.

---

## Lua Module Architecture (v11+)

> **Migrated → [`docs/architecture/mod-scripts.md`](docs/architecture/mod-scripts.md).**
> The KB section listed the prototype-era ping modules (`pings.lua`,
> `wheel.lua`, `assets.lua`) as live; the migrated doc reflects the
> current state — chat / profile / identity are the active features,
> the ping modules are dead-but-present (kept for a future revival
> attempt). The migrated doc also formalizes the two architecture
> principles ("features own their engine integration", "per-tick
> discipline") that were implicit in the original list.
> Section retained as a stub so existing references still resolve.

---

## Network Relay Architecture

> **Migrated → [`docs/architecture/relay.md`](docs/architecture/relay.md).**
> The KB section was a snapshot of the **ping-prototype** era and was
> stale — chat (not pings) is the live WebSocket payload, the relay
> also hosts a REST API for per-install profiles per
> [ADR 0002](docs/decisions/0002-profile-storage.md), and Caddy +
> systemd + TLS deployment is documented operationally in
> [`docs/ops/deploy-relay.md`](docs/ops/deploy-relay.md). The migrated
> doc covers the current four-process chain (Lua ↔ sidecar ↔ Caddy ↔
> relay), the file-IPC contract, the WebSocket + REST split, and the
> "why pings turned into chat" historical context.
> Section retained as a stub so existing references still resolve.

## Flipbook Animation (Sprite Sheets)

> **Migrated → [`docs/engine/widgets.md` → "Flipbook animation (sprite sheets)"](docs/engine/widgets.md#flipbook-animation-sprite-sheets).**
> Section retained as a stub so existing references still resolve.

---

## Omega Strikers — Game Internals

This H2 section is a container for several engine-side topics. As
each sub-section migrates to `docs/engine/`, it gets a redirect
stub here. The unmigrated sub-sections remain canonical until
they too move (per the migration banner at the top of this file).

### Engine & Modules

> **Migrated → [`docs/engine/overview.md`](docs/engine/overview.md).**
> Specifically: ["The engine pin"](docs/engine/overview.md#the-engine-pin)
> and ["The two gameplay modules"](docs/engine/overview.md#the-two-gameplay-modules).
> KB stated "UE editor (modding) 5.1.1" — this was *empirically
> wrong* (5.1.1 from launcher silently corrupts complex widgets;
> source-built 5.1.0 is the actual requirement). The migrated
> doc reflects the correction; see
> [`docs/engine/overview.md` → "Why source-built 5.1.0"](docs/engine/overview.md#why-source-built-510).
> Section retained as a stub so existing references still resolve.

### Maps

> **Migrated → [`docs/engine/setup.md` → "Maps"](docs/engine/setup.md#maps).**
> Section retained as a stub so existing references still resolve.

### Backend Ecosystem — Odyssey's "Prometheus" API

> **Migrated → [`docs/engine/identity-and-api.md` → "The backend API"](docs/engine/identity-and-api.md#the-backend-api).**
> The two-Prometheus disambiguation, auth (JWT pair from Fiddler
> capture or Steam-ticket handshake), exposed endpoints (per-
> character aggregates, ratings, mastery), and the OSPlus
> capture gap (no `redirects` field, no per-match event
> sequences, no in-match transient state) are all preserved.
> Section retained as a stub so existing references still resolve.

### Per-match runtime data — what's reachable from Lua

> **Migrated → [`docs/engine/data-model.md`](docs/engine/data-model.md).**
> Specifically: [`PMPlayerMatchSummary` field layout](docs/engine/data-model.md#pmplayermatchsummary)
> and [`EPMEndOfGameStat` enum](docs/engine/data-model.md#epmendofgamestat-enum),
> plus `PMRockCharacter:LastRedirectKnockBack`,
> `EKnockBackType::Redirect = 2`, the
> ["Rock" naming gotcha](docs/engine/data-model.md#the-rock-naming-gotcha),
> and the open questions about per-summary↔player mapping.
> Section retained as a stub so existing references still resolve.

### Game Lifecycle & Phase Detection

> **Migrated → [`docs/engine/game-state.md` → "Phase model"](docs/engine/game-state.md#phase-model)
> and [→ "Match detection"](docs/engine/game-state.md#match-detection).**
> All five phase class-tuples (Main Menu, Character Select,
> Active Gameplay, Awakening Select, Practice Mode) and the
> proven `isInMatch()` predicate are preserved. The "between
> rounds" terminology in the original was reconciled with the
> player-side canonical "between sets" — see migrated doc's
> note on the Awakening Select phase.
> Section retained as a stub so existing references still resolve.

### Class Hierarchy Reference

#### Core Framework

> **Migrated → [`docs/engine/game-state.md` → "The Core Framework class tree"](docs/engine/game-state.md#the-core-framework-class-tree).**

#### Characters (confirmed via F10 dump + runtime Pawn inspection)

> **Migrated → [`docs/engine/strikers.md`](docs/engine/strikers.md).**
> Specifically: [the internal-name → display-name table](docs/engine/strikers.md#internal-name--display-name-table)
> (26 catalogued names, 3 confirmed mappings, 3 likely-by-folder),
> [the `C_<InternalName>_C` runtime pattern](docs/engine/strikers.md#how-to-confirm-a-row),
> [content folder layout](docs/engine/strikers.md#content-folder-layout),
> and [utility folders](docs/engine/strikers.md#utility-folders)
> (`Shared/`, `GoalScore/`, `GradientGoal/` etc. — NOT playable
> Strikers). The migrated doc also catalogs the open question
> for cross-context Striker representation (combat Pawn vs
> striker-select preview vs lobby home-hub display).
> Section retained as a stub so existing references still resolve.

#### HUD Hierarchy

> **Migrated → [`docs/engine/widgets.md` → "HUD class hierarchy"](docs/engine/widgets.md#hud-class-hierarchy).**

#### Key UFunctions (hookable)

> **Migrated:**
>
> - `GameState_Game_C`, `GameState_Tutorial_C`,
>   `PlayerController_Game_C`, `PlayerController_Practice_C`,
>   `GameInstance_Base_C` UFunction tables →
>   [`docs/engine/game-state.md` → "Hookable UFunctions"](docs/engine/game-state.md#hookable-ufunctions)
> - `PlayerState_Game_C` UFunction table →
>   [`docs/engine/player-state.md` → "Hookable UFunctions"](docs/engine/player-state.md#hookable-ufunctions)
>
> Strike-specific UFunctions on `PlayerController_Game_C`
> (`StrikeReleased`, `StrikeDragged`) will additionally appear
> in batch 3's `rock-and-strike.md` for centralized Strike
> reference.

#### UI Widget Tree (menu — from F3 dump)

> **Migrated → [`docs/engine/widgets.md` → "Persistent widgets"](docs/engine/widgets.md#persistent-widgets-parented-to-gameinstance_base_c).**

#### ScrollBox Usage in Game (confirmed via F9 dump)

> **Migrated → [`docs/engine/widgets.md` → "ScrollBox usage in OS's own UI"](docs/engine/widgets.md#scrollbox-usage-in-oss-own-ui).**

### BPModLoaderMod Lifecycle

> **Migrated → [`docs/engine/widgets.md` → "BPModLoaderMod lifecycle"](docs/engine/widgets.md#bpmodloadermod-lifecycle).**
> The auto-load sequence, magic-name constraint
> (`/Game/Mods/<ModName>/ModActor`), timing characteristics
> (`~27s` post-start), and the duplicate-prevention check
> are all preserved. Section retained as a stub so existing
> references still resolve.

### Widget System — What Works in Cooked Paks

> **Migrated → [`docs/engine/widgets.md` → "Widget catalog (what works in cooked paks)"](docs/engine/widgets.md#widget-catalog-what-works-in-cooked-paks).**

### EditableText (ChatInput) — Known Bugs & Workarounds

> **Migrated → [`docs/engine/widgets.md` → "EditableText quirks (chat input)"](docs/engine/widgets.md#editabletext-quirks-chat-input).**

### Input Mode Management

> **Migrated → [`docs/engine/widgets.md` → "Input mode management"](docs/engine/widgets.md#input-mode-management).**

### Visibility Constants (ESlateVisibility)

> **Migrated → [`docs/engine/widgets.md` → "Visibility constants (ESlateVisibility)"](docs/engine/widgets.md#visibility-constants-eslatevisibility).**
> The HitTestInvisible vs SelfHitTestInvisible distinction and
> the BP-function-name resolution rule (display name without
> spaces) are preserved in the migrated doc; the latter also
> appears in
> [`docs/engine/ue4ss-version-and-gotchas.md` → "BP function name resolution"](docs/engine/ue4ss-version-and-gotchas.md#4-bp-function-name-resolution-display-name-without-spaces).

### GameInstance Persistence

> **Migrated → [`docs/engine/widgets.md` → "GameInstance persistence"](docs/engine/widgets.md#gameinstance-persistence-the-persistent-root).**

---

## Known Unknowns / Investigation Needed

> **Migrated → [`docs/engine/open-questions.md`](docs/engine/open-questions.md).**
> The KB's flat list was reorganized into the cross-cutting
> categories that survived (Game state / UI / Networking and
> player data / Audio / Input) plus a "Resolved (kept for
> reference)" table that catalogs every question previously
> open in KB and where the answer now lives. Items that fit
> cleanly into a per-topic engine doc (the majority) were also
> added to that doc's *Open questions* section — the cross-cutting
> file is the landing page for the rest.
> Section retained as a stub so existing references still resolve.

### Player Identity Reference

> **Migrated → [`docs/engine/identity-and-api.md`](docs/engine/identity-and-api.md).**
> Specifically: [the three identifier namespaces](docs/engine/identity-and-api.md#the-three-identifier-namespaces),
> [the local-identity surface](docs/engine/identity-and-api.md#the-local-identity-surface),
> [the cached-others path](docs/engine/identity-and-api.md#the-cached-others-path),
> and [the v36-current Lua-side reachability rules](docs/engine/identity-and-api.md#lua-side-reachability)
> with the three-mode `PlayerNamePrivate` caveat (display name /
> hex ID during replication / Windows machine name out-of-match)
> cross-linked to the relevant learnings.
> Heading retained here because `Known Unknowns / Investigation
> Needed → Player Identity Reference` was a sub-section in the
> original outline — kept so deep links still resolve.

### ScrollBox Crash — Root Cause & Resolution (SOLVED)

> **Migrated → [`docs/engine/widgets.md` → "ScrollBox crash — root cause"](docs/engine/widgets.md#scrollbox-crash--root-cause).**
> Full investigation timeline preserved (UE 5.1.1 attempt → UE
> 5.1.0 source-built → binary analysis → wrong-key-name
> false-friend → source-code analysis → fix). The fix INI line
> also lives in [`docs/engine/setup.md` → "DefaultEngine.ini"](docs/engine/setup.md#defaultengineini).
> Section retained as a stub (and as a SOLVED marker for the
> "Known Unknowns" section) so existing references still resolve.
