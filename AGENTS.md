# OSPlus — Agent Briefing

OSPlus is a mod platform for Omega Strikers. Today it ships an in-game chat (UE4SS Lua + cooked Blueprint widget) and a Node.js sidecar that bridges the game to a public WebSocket relay (`wss://play-osplus.duckdns.org`). The long-horizon vision is a SteamID-bound profile/social platform on top — locked architectural commitments in `docs/vision.md`.

This file is the entry point for any AI coding agent working in this repo. Keep it under ~150 lines. If you need depth, link to a doc instead of inlining.

## Pre-work reading (in this order)

1. This file — toolchain, layout, principles.
2. `docs/research/2026-agentic-stack.md` — why the agentic file structure looks the way it does. Read once per onboarding, then trust it.
3. `KNOWLEDGEBASE.md` — engine facts, game internals, hard-won Lua patterns. Long; treat as reference, not narrative.
4. `docs/architecture/state-contract.md` — the Lua/BP boundary contract for the mod. Mandatory before touching `mod/**/*.lua` or BP feature design.
5. `docs/UE_PROJECT_MIGRATION.md` — the OmegaStrikersMod → OSPlus rename, current cooked-content paths.
6. `docs/ops/deploy-relay.md` — runbook for the OCI relay VM.
7. `docs/learnings/` — every non-trivial finding from past work. Skim before solving any problem that smells familiar.

For deeper expertise on demand: `.cursor/skills/` (UE4SS Lua, UMG/Slate, UE serialization) auto-activate when relevant.

## Repository map

```
mod/OSPlus/scripts/   Lua source for the in-game mod (UE4SS). Authoritative source.
ue-assets/            Cooking helpers and the .pak builder.
sidecar/              Node.js process the user runs locally; bridges file IPC ↔ relay WS.
server/               Node.js relay (deployed to OCI) + deploy scripts + Caddy config.
dist/                 Output of build_dist.ps1: end-user installer (install.bat + .pak + UE4SS).
tools/setup/          Dev-environment bootstrap (repak, UAssetGUI, etc).
tools/re/             Reverse-engineering helpers (work in progress).
docs/                 All durable knowledge. See structure below.
.cursor/rules/        Behavior policies. Auto-loaded by Cursor.
.cursor/skills/       On-demand expertise. Model invokes by description.
KNOWLEDGEBASE.md      Engine + game internals reference (to be split into docs/ later).
```

Game install lives outside the repo at `F:\SteamLibrary\steamapps\common\OmegaStrikers\`. The UE editor project lives at `F:\Omegamod\OmegaStonkers 5.1\` and is built against a source build of UE 5.1.0 at `F:\UE510\UnrealEngine-5.1.0-release\`.

## Toolchain — use these, do not reinvent

Always check this list before writing any new script. If a workflow seems missing, ask before authoring — there's likely an existing script doing it.

### Build & ship the mod
- `tools/setup/bootstrap.ps1` — first-time dev env setup (downloads repak, UAssetGUI, verifies UE paths). Idempotent.
- **Cooking is manual in the UE Editor**: `File → Cook Content for Windows`. `/Game/Mods/OSPlus` must be in *Project Settings → Packaging → Additional Asset Directories to Cook*, otherwise the cook is empty.
- `ue-assets/package_logicmod.ps1` — packs cooked OSPlus content into `OSPlus.pak`, drops it in `LogicMods/`. Run after every cook.
- `build_dist.ps1` — assembles `dist/OSPlus.zip` (Lua + sidecar SEA + pak + UE4SS bundle + installer + README). Refuses to build without `OSPlus.pak`.
- `dist/install.bat` — end-user installer. Auto-elevates, auto-detects game path, migrates legacy installs, strips MotW. Distributed inside the zip.

### Local dev loop
- `deploy.ps1` — fast Lua-only sync from `mod/OSPlus/scripts/` to the game install. Use this between cook cycles when iterating on Lua. Does NOT update the pak.

### Relay (server)
- `server/deploy/ship.ps1` — push `server/` to the OCI VM, run `install-relay.sh`, restart services. Default host: `136.248.104.200`, key at `~/.ssh/osplus_oci.key`.
- `server/deploy/install-relay.sh` — runs on the VM. Installs Node.js + Caddy, lays down systemd units, enables auto-TLS for `play-osplus.duckdns.org`. Called by `ship.ps1`, never run directly from Windows.
- `server/deploy/Caddyfile` and `server/deploy/osplus-relay.service` — the deployed config. `osplus-relay.service` does **not** use `MemoryDenyWriteExecute=true` because Node.js V8 JIT needs writable+executable pages.

### Reverse engineering / debug
- `parse_uasset.ps1` — generic .uasset header parser. Useful but ad-hoc; not a stable harness.
- `compare_uexp.ps1` — one-off binary diff for cooked outputs. Hardcoded paths; treat as scratch.
- `tools/re/` — emerging reverse-engineering toolkit (snapshot, hook, dump). Still being built out.

## Engine constraints (the ones that bite)

- Unreal Engine **5.1.0** runtime. Cook with the source-built 5.1.0 editor (not 5.1.1 from Epic launcher) — schema mismatches will silently corrupt complex widgets.
- `DefaultEngine.ini` MUST have `CanUseUnversionedPropertySerialization=False` under `[Core.System]`. Without it, ScrollBox and other complex widgets crash on deserialization. See `KNOWLEDGEBASE.md` for the full RCA.
- DX11 / SM5 only. No Lumen, no virtual shadow maps, no mesh distance fields.
- BPModLoaderMod hardcodes `ModActor` at `/Game/Mods/<ModName>/ModActor`. Do not rename or move it.
- UE4SS Lua has no networking — use sidecar + file IPC. See `KNOWLEDGEBASE.md` "Network Relay Architecture."

## Core principles

1. **Don't reinvent harnesses.** The Toolchain section above is exhaustive for active scripts. If you think you need a new one, propose it first.
2. **Author vision is canon.** OSPlus is a *platform*, not a one-off mod. Designs that make sense for "this feature" but break "the platform" are wrong. Surface the conflict instead of papering over it.
3. **No fabrication.** If you don't know something — a UFunction signature, a BP property, an OCI command, an engine version — say so and probe (Lua dumps, `KNOWLEDGEBASE.md`, `docs/`, web search). Inventing plausible-looking detail is the worst possible failure mode in this codebase because it compounds.
4. **Lua/BP boundary respected.** Every piece of mod state has one canonical owner. UI-reactive → BP. Domain/operational → Lua. Display values → BP holds, Lua pushes. See `.cursor/rules/mod-architecture.mdc` and `docs/architecture/state-contract.md` before touching either side.
5. **Findings get logged before "done."** Every non-trivial debug, every new engine fact, every gotcha → `docs/learnings/<slug>.md`. Use the template. This is enforced by `.cursor/rules/learnings-discipline.mdc`.

## Git workflow

`main` stays green. Speculative or multi-file work goes on a branch (`feat/`, `fix/`, `docs/`, `refactor/`, `chore/`, `experiment/`). Before starting non-trivial work, propose a branch name and create it — don't silently commit to `main`. Conventional commit messages (`feat(chat): add channel switcher`). Never force-push `main`. Full policy in `.cursor/rules/git-workflow.mdc`.

## Vision

Four locked architectural commitments drive what gets built and how:

1. **Identity** = claimed SteamID + game-derived display name.
2. **Profile module** = REST API, SQLite, in-process with the relay (`server/profile/`), separable later.
3. **Profile schema** starts identity-only and grows on demand — fields are added by the feature that needs them, in the same branch.
4. **Ephemeral state** lives on the relay (not the client, not a separate service).

Full rationale, what each lock rules out, and the remaining `[TBD]`s: `docs/vision.md`. **Read it before designing any feature that touches identity, profile, persistence, or shared session state.**

If a feature seems to require *changing* a lock, stop and surface the conflict — locks change with conversation, not by drift.

## When in doubt

- Engine question → `KNOWLEDGEBASE.md` first, `docs/architecture/` second, `.cursor/skills/ue4ss-modding/` third.
- Build/deploy question → Toolchain section above, then `docs/ops/`.
- Past gotcha → `docs/learnings/`.
- Why is this structured this way? → `docs/research/`.
- Anything about Cursor itself (rules, skills, this file) → `docs/research/2026-agentic-stack.md`.
