# OSPlus — Agent Briefing

OSPlus is a community-maintained mod layer for Omega Strikers. The product-level answer to "what is OSPlus and who is it for" lives in [`docs/product.md`](./docs/product.md); architectural choices are deliberated in [`docs/decisions/`](./docs/decisions/). Today the codebase ships an in-game chat (UE4SS Lua + cooked Blueprint widget) bridged via a Node.js sidecar to a public WebSocket relay (`wss://play-osplus.duckdns.org`) — chat is infrastructure that paid forward the sidecar+relay+pak pipeline, not the product itself.

Entry point for any AI coding agent in this repo. If you need depth, link to a doc; don't inline.

## Pre-work reading (in order)

1. This file.
2. [`docs/product.md`](./docs/product.md) — product definition. Audience, problem, wedge, anti-goals, hard constraints. Read at the start of every session.
3. [`docs/dev-cycle.md`](./docs/dev-cycle.md) — how features get from idea to shipped. The 6-stage lifecycle, back-edges, default-paired stance. Read before any feature work.
4. [`docs/game/`](./docs/game/) — **player-side reality of Omega Strikers**: screens, navigation, match lifecycle, in-match UX, player systems, design principles. The *what does the game look and feel like to the player* layer. Mandatory before designing any feature whose acceptance criteria mention what the player will see, do, or perceive — i.e. nearly all of them. Cross-references engine-internal names via `docs/glossary.md` but does not duplicate `docs/engine/`. Per-topic files under [`docs/game/README.md`](./docs/game/README.md); the original monolithic [`OMEGA_STRIKERS_GAME.md`](./docs/game/OMEGA_STRIKERS_GAME.md) is now a redirect index.
5. [`docs/glossary.md`](./docs/glossary.md) — bidirectional concept catalog bridging `docs/game/` (player-side) and `docs/engine/` (engine-side). Reference, not a narrative — consult when you encounter a term and want the canonical mapping (player concept ↔ engine class names + identity key + open questions). Small. Read once to know what's in it; deep-link into specific entries during work.
6. `docs/research/2026-agentic-stack.md` — why the agentic file structure looks the way it does.
7. [`docs/engine/`](./docs/engine/) — **engine + UE4SS reality of Omega Strikers**: UClasses, UFunctions, runtime data shapes, hook patterns, phase models. The bedrock every feature design eventually touches. Per-topic files; start with [`overview.md`](./docs/engine/overview.md) for first-contact, browse [`README.md`](./docs/engine/README.md) for the full index + reading orders. The original monolithic `KNOWLEDGEBASE.md` is now a redirect index — every section there points into this folder (or into `docs/architecture/` for OSPlus-internal architecture).
8. `docs/architecture/domain-boundaries.md` — product/domain ownership boundaries: which reusable concept owns a file/module/data contract vs which screen merely renders it. Mandatory before adding Lua modules, JSON files, BP functions, or sidecar messages for features that might be reused by more than one screen.
9. `docs/architecture/state-contract.md` — Lua/BP boundary contract. Mandatory before touching `mod/**/*.lua` or designing a feature.
10. `docs/architecture/mod-scripts.md` — Lua-script-internal architecture: what each script does, the per-tick discipline buckets, the "feature owns its engine integration" rule. Mandatory before touching `mod/**/*.lua` or adding a new feature module. Companion to `state-contract.md`: that doc is the cross-context contract; this one is the in-context structure.
11. [`docs/architecture/relay.md`](./docs/architecture/relay.md) — sidecar + cloud relay architecture: file-IPC contract between Lua and the sidecar, the WebSocket + REST split, the four-process Lua ↔ sidecar ↔ Caddy ↔ relay chain. Mandatory before touching `sidecar/**/*.js` or `server/**/*.js`. Operational runbook lives separately in `docs/ops/deploy-relay.md`.
12. `docs/UE_PROJECT_MIGRATION.md` — cooked-content paths after the OmegaStrikersMod → OSPlus rename.
13. `docs/ops/deploy-relay.md` — runbook for the OCI relay VM.
14. `docs/learnings/` — skim before solving anything that smells familiar.
15. `docs/decisions/` — scan for relevant ADRs before making any architectural choice.
16. `docs/features/` — per-feature paper trails. Check for prior work in the same area before designing.

## Workflow skills

Five skills in `.cursor/skills/` auto-activate by description match. If your current work matches a trigger and you haven't read the skill, you're skipping a step. Skills map onto stages of [`docs/dev-cycle.md`](./docs/dev-cycle.md).

- **`discover`** — Stage 3 (Feasibility / RE). "Is X possible in OS?", "can we hook Y?", or feasibility check for a framed feature. Produces `## Feasibility` in a feature doc, or a learning entry / `docs/engine/` update for standalone RE. Spike pattern for Low-confidence verdicts.
- **`feature-design`** — Stage 4. "Add X" / "implement X" for non-trivial features. **Requires Stage 3 to have run** (precondition checks the feature doc). Surfaces design axes before code is written. Stops for sign-off.
- **`bug-investigate`** — bug-fix lane (separate from feature lifecycle). Prior-art lookup → reproduce → falsify → fix → write learning.
- **`correct-knowledge`** — discipline. Triggers when an investigation finds a doc claim that's wrong, incomplete, or absent. Walks the cascade across `docs/engine/`, `docs/architecture/`, `docs/game/`, `docs/glossary.md`, `AGENTS.md`, and `KNOWLEDGEBASE.md` so the canonical reference moves with the learning entry. Procedural backstop for `learnings-discipline.mdc` and `decision-discipline.mdc`.
- **`release-checklist`** — Stage 6 (Land). Ship a build / cut a release. Pre-flight → build chain → spot-check → smoke test → distribution → recorded run.

## External paths (non-discoverable)

- Game install: `F:\SteamLibrary\steamapps\common\OmegaStrikers\`
- UE editor project: `F:\Omegamod\OmegaStonkers 5.1\`
- Source-built UE 5.1.0: `F:\UE510\UnrealEngine-5.1.0-release\`

In-repo structure is discoverable via `ls`. The engine/game-internals reference lives at [`docs/engine/`](./docs/engine/) (per-topic files; start with [`overview.md`](./docs/engine/overview.md)). The original `KNOWLEDGEBASE.md` (root) is now a redirect index — every section there is a stub pointing at the new home in `docs/engine/` or `docs/architecture/`.

## Toolchain — use these, don't reinvent

Always check this before writing any script. If a workflow seems missing, ask before authoring.

### Build & ship the mod
- `tools/setup/bootstrap.ps1` — first-time dev env setup. Idempotent.
- **Cooking is manual in the UE Editor**: `File → Cook Content for Windows`. `/Game/Mods/OSPlus` must be in *Project Settings → Packaging → Additional Asset Directories to Cook* or the cook is empty.
- `ue-assets/package_logicmod.ps1` — packs cooked content into `OSPlus.pak` in `LogicMods/`. Run after every cook.
- `build_dist.ps1` — assembles `dist/OSPlus.zip`. Refuses to build without `OSPlus.pak`.
- `dist/install.bat`, `dist/install.sh` — end-user installers. Distributed inside the zip.
- `dist/uninstall.bat`, `dist/uninstall.sh` — end-user uninstallers. Remove OSPlus and ask before removing shared UE4SS/local data.

### Local dev loop
- `deploy.ps1` — fast Lua-only sync to the game install. Does NOT update the pak.

### Relay (server)
- `server/deploy/ship.ps1` — push `server/` to OCI VM, run `install-relay.sh`, restart services. Host: `136.248.104.200`.
- `server/deploy/install-relay.sh` — runs on the VM (called by `ship.ps1`). Installs Node.js + Caddy, lays down systemd units, enables auto-TLS for `play-osplus.duckdns.org`.
- `osplus-relay.service` does **not** use `MemoryDenyWriteExecute=true` — V8 JIT needs writable+executable pages.

### Reverse engineering / debug
- `parse_uasset.ps1`, `compare_uexp.ps1` — ad-hoc scratch helpers. Hardcoded paths.
- `tools/re/` — emerging RE toolkit (in progress).

## Engine constraints (the ones that bite)

- Unreal Engine **5.1.0** runtime. Cook with the source-built 5.1.0 editor (not 5.1.1 from Epic launcher) — schema mismatches silently corrupt complex widgets.
- **UE4SS 3.0.1** runtime. Anchor every UE4SS docs/issues lookup to this version — the Lua marshaling layer changes between releases (e.g. UFunction out-param shapes, multicast-delegate binding) and quoting newer-version threads at face value has burned us before (issues fixed in 3.1+ may *not* be fixed for us). Bump this line on upgrade and re-run any spike that depended on the old version's behavior. See `.cursor/rules/lua-conventions.mdc` "UE4SS build" + "Lua-not-C++ reflex".
- `DefaultEngine.ini` MUST have `CanUseUnversionedPropertySerialization=False` under `[Core.System]`. Without it, ScrollBox and other complex widgets crash on deserialization.
- DX11 / SM5 only. No Lumen, no virtual shadow maps, no mesh distance fields.
- BPModLoaderMod hardcodes `ModActor` at `/Game/Mods/<ModName>/ModActor`. Do not rename or move.
- UE4SS Lua has no networking — use sidecar + file IPC.

## Core principles

1. **Product definition is canon.** `docs/product.md` defines what OSPlus is and who it's for. Accepted ADRs in `docs/decisions/` define how it's built. Surface "this feature vs. the product / an ADR" conflicts instead of papering over them.
2. **No fabrication.** If you don't know a UFunction signature, a BP property, an OCI command — say so and probe (Lua dumps, [`docs/engine/`](./docs/engine/), web search). Inventing plausible detail compounds into silent breakage. Applies to comments and log messages too.
3. **Lua/BP boundary respected.** UI-reactive → BP. Domain/operational → Lua. Display values → BP holds, Lua pushes. See `.cursor/rules/mod-architecture.mdc`.
4. **Contributor-legible authoring.** Prefer the least surprising home for each artifact: UE project assets for asset-like authored content, Lua/JSON for runtime bridges, metadata, and localization. When placement is ambiguous, record why in the feature doc. See `docs/architecture/domain-boundaries.md`.
5. **Default-paired stance.** The agent stops at every non-trivial decision point and surfaces choices, not just at stage transitions. See [`docs/dev-cycle.md`](./docs/dev-cycle.md).

"Don't reinvent harnesses" is enforced by `.cursor/rules/harnesses.mdc`. "Log findings before done" by `.cursor/rules/learnings-discipline.mdc`. Both `alwaysApply`.

## Git workflow

`main` stays green. Non-trivial work goes on a branch (`feat/`, `fix/`, `docs/`, `refactor/`, `chore/`, `experiment/`). Propose the branch name before creating it. Conventional commits (`feat(chat): add channel switcher`). Never force-push `main`. Full policy in `.cursor/rules/git-workflow.mdc`.

## Product, decisions, lifecycle, and roadmap

- **[`docs/product.md`](./docs/product.md)** — the north star. Audience, problem, wedge, anti-goals, success criteria, hard constraints. Everything else in the project is downstream of this doc. Read at session start; read before designing a feature; read before arguing for a new direction.
- **[`docs/dev-cycle.md`](./docs/dev-cycle.md)** — the 6-stage lifecycle (Capture → Frame → Feasibility → Design → Build → Land), back-edges, default-paired stance. The "how we work" doc.
- **[`docs/features/`](./docs/features/)** — per-feature paper trails. Each feature gets one file with Brief / Feasibility / Design / Outcome sections, filled progressively as it moves through the lifecycle. Shelved features stay; their value is *why* they didn't pan out.
- **[`docs/decisions/`](./docs/decisions/)** — architectural decisions. ADRs carry options-considered + rationale. Three areas were flagged as first-priority ADR work per the README — identity model (closed by ADR 0001) and profile + capture storage (closed by ADR 0002) are now decided; ephemeral state ownership remains open and is forced by the next feature that depends on persistent ephemeral state. Enforced by `.cursor/rules/decision-discipline.mdc`.
- **[`docs/ROADMAP.md`](./docs/ROADMAP.md)** — Now / Next / Later / Won't-do, filtered through the product lens. "Next" is not a priority queue. Read before picking up new work.

The prior `docs/vision.md` — which encoded four "v1 locks" without recorded alternatives — has been archived to [`docs/decisions/_archive/vision-v1-superseded.md`](./docs/decisions/_archive/vision-v1-superseded.md) with a header explaining why. Do not treat the choices in that archive as current commitments; the ADR queue in `docs/decisions/README.md` supersedes them.

## When in doubt

- How do I work on a feature? → [`docs/dev-cycle.md`](./docs/dev-cycle.md).
- Term doesn't make sense / "what does X map to in code?" → [`docs/glossary.md`](./docs/glossary.md).
- Engine question → [`docs/glossary.md`](./docs/glossary.md) (concept ↔ engine bridge) → [`docs/engine/`](./docs/engine/) → `docs/architecture/` → `.cursor/skills/ue4ss-modding/`.
- Is X possible in OS? → `.cursor/skills/discover/`.
- Build/deploy → Toolchain above → `docs/ops/`.
- Past gotcha → `docs/learnings/`.
- Why the agentic structure is this way → `docs/research/`.
