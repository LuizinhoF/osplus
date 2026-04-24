# OSPlus — Agent Briefing

OSPlus is a community-maintained mod layer for Omega Strikers. The product-level answer to "what is OSPlus and who is it for" lives in [`docs/product.md`](./docs/product.md); architectural choices are deliberated in [`docs/decisions/`](./docs/decisions/). Today the codebase ships an in-game chat (UE4SS Lua + cooked Blueprint widget) bridged via a Node.js sidecar to a public WebSocket relay (`wss://play-osplus.duckdns.org`) — chat is infrastructure that paid forward the sidecar+relay+pak pipeline, not the product itself.

Entry point for any AI coding agent in this repo. If you need depth, link to a doc; don't inline.

## Pre-work reading (in order)

1. This file.
2. [`docs/product.md`](./docs/product.md) — product definition. Audience, problem, wedge, anti-goals, hard constraints. Read at the start of every session.
3. `docs/research/2026-agentic-stack.md` — why the agentic file structure looks the way it does.
4. `KNOWLEDGEBASE.md` — engine + game internals reference. Long; use as a reference, not a narrative.
5. `docs/architecture/state-contract.md` — Lua/BP boundary contract. Mandatory before touching `mod/**/*.lua` or designing a feature.
6. `docs/UE_PROJECT_MIGRATION.md` — cooked-content paths after the OmegaStrikersMod → OSPlus rename.
7. `docs/ops/deploy-relay.md` — runbook for the OCI relay VM.
8. `docs/learnings/` — skim before solving anything that smells familiar.
9. `docs/decisions/` — scan for relevant ADRs before making any architectural choice.

## Workflow skills

Three skills in `.cursor/skills/` auto-activate by description match. If your current work matches a trigger and you haven't read the skill, you're skipping a step.

- **`feature-design`** — "add X" / "implement X" for non-trivial features. Surfaces design axes before code is written. Stops for sign-off.
- **`bug-investigate`** — bugs / unexpected behavior. Prior-art lookup → reproduce → falsify → fix → write learning.
- **`release-checklist`** — ship a build / cut a release. Pre-flight → build chain → spot-check → smoke test → distribution → recorded run.

## External paths (non-discoverable)

- Game install: `F:\SteamLibrary\steamapps\common\OmegaStrikers\`
- UE editor project: `F:\Omegamod\OmegaStonkers 5.1\`
- Source-built UE 5.1.0: `F:\UE510\UnrealEngine-5.1.0-release\`

In-repo structure is discoverable via `ls`. `KNOWLEDGEBASE.md` (root) is the engine/game-internals reference.

## Toolchain — use these, don't reinvent

Always check this before writing any script. If a workflow seems missing, ask before authoring.

### Build & ship the mod
- `tools/setup/bootstrap.ps1` — first-time dev env setup. Idempotent.
- **Cooking is manual in the UE Editor**: `File → Cook Content for Windows`. `/Game/Mods/OSPlus` must be in *Project Settings → Packaging → Additional Asset Directories to Cook* or the cook is empty.
- `ue-assets/package_logicmod.ps1` — packs cooked content into `OSPlus.pak` in `LogicMods/`. Run after every cook.
- `build_dist.ps1` — assembles `dist/OSPlus.zip`. Refuses to build without `OSPlus.pak`.
- `dist/install.bat` — end-user installer. Distributed inside the zip.

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
- `DefaultEngine.ini` MUST have `CanUseUnversionedPropertySerialization=False` under `[Core.System]`. Without it, ScrollBox and other complex widgets crash on deserialization.
- DX11 / SM5 only. No Lumen, no virtual shadow maps, no mesh distance fields.
- BPModLoaderMod hardcodes `ModActor` at `/Game/Mods/<ModName>/ModActor`. Do not rename or move.
- UE4SS Lua has no networking — use sidecar + file IPC.

## Core principles

1. **Product definition is canon.** `docs/product.md` defines what OSPlus is and who it's for. Accepted ADRs in `docs/decisions/` define how it's built. Surface "this feature vs. the product / an ADR" conflicts instead of papering over them.
2. **No fabrication.** If you don't know a UFunction signature, a BP property, an OCI command — say so and probe (Lua dumps, `KNOWLEDGEBASE.md`, web search). Inventing plausible detail compounds into silent breakage. Applies to comments and log messages too.
3. **Lua/BP boundary respected.** UI-reactive → BP. Domain/operational → Lua. Display values → BP holds, Lua pushes. See `.cursor/rules/mod-architecture.mdc`.

"Don't reinvent harnesses" is enforced by `.cursor/rules/harnesses.mdc`. "Log findings before done" by `.cursor/rules/learnings-discipline.mdc`. Both `alwaysApply`.

## Git workflow

`main` stays green. Non-trivial work goes on a branch (`feat/`, `fix/`, `docs/`, `refactor/`, `chore/`, `experiment/`). Propose the branch name before creating it. Conventional commits (`feat(chat): add channel switcher`). Never force-push `main`. Full policy in `.cursor/rules/git-workflow.mdc`.

## Product, decisions, and roadmap

- **[`docs/product.md`](./docs/product.md)** — the north star. Audience, problem, wedge, anti-goals, success criteria, hard constraints. Everything else in the project is downstream of this doc. Read at session start; read before designing a feature; read before arguing for a new direction.
- **[`docs/decisions/`](./docs/decisions/)** — architectural decisions. ADRs carry options-considered + rationale. Three areas (identity model, profile storage, ephemeral state) are flagged as first-priority ADR work per the README — feature work touching those areas forces the ADR first. Enforced by `.cursor/rules/decision-discipline.mdc`.
- **[`docs/ROADMAP.md`](./docs/ROADMAP.md)** — Now / Next / Later / Won't-do, filtered through the product lens. "Next" is not a priority queue. Read before picking up new work.

The prior `docs/vision.md` — which encoded four "v1 locks" without recorded alternatives — has been archived to [`docs/decisions/_archive/vision-v1-superseded.md`](./docs/decisions/_archive/vision-v1-superseded.md) with a header explaining why. Do not treat the choices in that archive as current commitments; the ADR queue in `docs/decisions/README.md` supersedes them.

## When in doubt

- Engine question → `KNOWLEDGEBASE.md` → `docs/architecture/` → `.cursor/skills/ue4ss-modding/`.
- Build/deploy → Toolchain above → `docs/ops/`.
- Past gotcha → `docs/learnings/`.
- Why the agentic structure is this way → `docs/research/`.
