# Reverse-Engineering Knowledge Base

This directory holds **curated, citable findings** about Omega Strikers — the things we've actually verified, not just speculated. It is the queryable memory the agent reaches for before doing fresh investigation.

## How this fits into the RE pipeline

```
data/re/raw/      ← gitignored. Raw dumps, pak listings, hook traces, snapshots.
data/re/index/    ← git-tracked. Lightweight indices generated from raw/ for fast lookup.
docs/re/          ← git-tracked. Curated markdown findings citing raw/ + index/ + code.
```

Raw dumps are the evidence. Indices are the search aid. Findings are the conclusions.
**A finding without a citation back to a raw artifact or to source code is not a finding.**

## Directory layout

```
docs/re/
├── README.md              ← you are here
├── architecture/          ← how the game is laid out: paks, content roots, naming
├── lifecycle/             ← startup, level load, match flow, GameInstance/GameMode
├── ui/                    ← HUDs, widgets, menus
├── player/                ← input, controllers, characters, camera
├── gameplay/              ← match rules, scoring, abilities, combat
├── networking/            ← replication, RPC, online subsystem
├── audio/                 ← Wwise integration, sound events
└── visuals/               ← VFX, materials, post-processing
```

Drop a finding into the most specific bucket. If a finding genuinely spans two areas, pick the bucket that owns the **decision it informs** and link the other.

## Finding format

Every finding is a single markdown file with YAML frontmatter:

```markdown
---
id: 0001-content-layout
title: Game content layout and pak strategy
status: confirmed
last-verified: 2026-04-04
sources:
  - data/re/raw/pak-inventory/CustomPings_P.list.txt
  - data/re/raw/pak-inventory/OmegaStrikers-Windows.list.txt
  - mod/OSPlus/scripts/chat.lua#L26
tags: [pak, asset-loading, mod-architecture]
related: []
---

# Game content layout and pak strategy

> **Scope:** what is and isn't shipped in the game's pak files; how our mod paks layer on top.
> **Purpose:** informs naming conventions, asset paths, and pak hygiene.

## Executive Summary
...

## Findings
...

## Implications for OSPlus
...

## Verification
- How to reproduce: <commands>
- Re-verify after: <event that would invalidate this, e.g. "any game patch">

## Remaining Unknowns
| Question | Impact | How to Resolve |
|---|---|---|
```

## Frontmatter contract

| Field | Required | Notes |
|---|---|---|
| `id` | yes | `NNNN-kebab-slug`. Sequential, never reused. Acts as stable handle for cross-references. |
| `title` | yes | Human-readable, matches the H1. |
| `status` | yes | `confirmed`, `hypothesis`, `partial`, `refuted`, `stale`. See below. |
| `last-verified` | yes | `YYYY-MM-DD`. The day someone (you or an agent) last re-ran the evidence and it still held. |
| `sources` | yes | List of paths. Use `path/to/file.ext#L<line>` for code, `path/to/dump.txt` for raw artifacts, plain URLs for external. **Every claim in the body must trace to one of these.** |
| `tags` | yes | Lowercase keywords. Stable taxonomy: `pak`, `asset-loading`, `umg`, `bp`, `lua`, `replication`, `wwise`, `mod-architecture`, etc. |
| `related` | yes | Other finding IDs (`["0003-startup-flow"]`). Empty list `[]` is valid. |

## Status taxonomy

- **confirmed** — verified against multiple sources or runtime behaviour. Safe to act on.
- **hypothesis** — best current explanation, not yet proven. Act on it cautiously, plan to confirm.
- **partial** — true within stated bounds; edges of the claim are unverified.
- **refuted** — was wrong. Keep the file (don't delete) so future investigations don't re-derive the dead end. Add an `## Update` block explaining what was wrong.
- **stale** — was confirmed but the game has patched since `last-verified` and we haven't re-checked.

## Rules

1. **Evidence first, conclusion second.** A finding's body shows the data, then interprets it. No "I think" without a citation.
2. **Cite raw artifacts, not memory.** If you ran `repak list X.pak`, save the output to `data/re/raw/...` first, then cite that file. Don't paraphrase from a closed terminal.
3. **One finding per file.** If a topic branches, create a new finding and link it via `related`.
4. **Update over duplicate.** New evidence about an existing finding goes into that finding as a dated `## Update YYYY-MM-DD` block. New ID only when the topic genuinely splits.
5. **Status drifts.** When the game patches, every `confirmed` finding silently becomes `stale` until re-verified. The `last-verified` date is what you trust, not the status alone.
6. **Tag for agents, not humans.** Tags are search keys. Use the established vocabulary. If you need a new tag, add it to the table in this README first.

## Index files

`data/re/index/` holds machine-generated, git-tracked summaries that agents grep before opening raw dumps:

- `data/re/index/pak-files.json` — all pak files, mount points, file counts (built from `data/re/raw/pak-inventory/`)
- `data/re/index/asset-paths.json` — flat list of every cooked asset path the game ships (built from the inventory)
- `data/re/index/findings.json` — built from `docs/re/**/*.md` frontmatter for fast retrieval by id/tag/status

Indices are regenerated by scripts in `tools/re/`. Don't hand-edit.
