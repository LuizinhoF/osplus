# ADR 0003 — Knowledge substrate structure: multi-file subtrees + canonical glossary

| Field | Value |
|---|---|
| Status | `accepted` |
| Date | 2026-04-29 |
| Forcing feature | Authoring of `docs/game/OMEGA_STRIKERS_GAME.md` (1414-line player-side monolith) + maintainer observation that `KNOWLEDGEBASE.md` (~750 lines) is "long overdue" for restructure. The next feature that depends on either doc — `feat/unlockable-earning-emotes`, currently stashed — needs reads + updates that the monolithic shape obstructs. |
| Supersedes | — |
| Superseded by | — |

## Decision

Knowledge documentation in OSPlus is organized as **multi-file
subtrees per domain**, with a **canonical project-root glossary**
bridging the domains, **migrated topic-by-topic** off the existing
monoliths.

Concretely:

- **D-1** — Multi-file subtree per domain. `docs/game/` (player-side reality) and `docs/engine/` (engine internals) each contain a `README.md` index + per-topic files. Each domain optionally has an `overview.md` distilled-narrative entry doc.
- **G-1** — Single canonical glossary at `docs/glossary.md`. Bidirectional concept catalog mapping player concept ↔ engine representation(s) + identity key + open questions. Both domain subtrees link into it; nobody duplicates it.
- **M-1** — Topic-by-topic migration off existing monoliths. Each batch (3-5 topics) is its own branch. README status tables in each subtree track which topics are *migrated* vs *TBD*; until a topic migrates, the source monolith remains canonical for it.

This decision applies to **knowledge documentation** (game-domain
facts, engine-internals reference). It does not apply to
single-finding diaries (`docs/learnings/`), per-feature paper trails
(`docs/features/`), or operational runbooks (`docs/ops/`) — those
already follow appropriate patterns.

## Why these picks

- **D-1 over D-2 (single monolith) and D-3 (hybrid).** Monoliths
  silently fail in two directions: agents read only the first half of
  long files, and editing a focused topic requires diffing 1000+ line
  files where the change-locality is invisible. Hybrid (overview +
  deep-dive per-topic) sounds appealing but carries duplication risk —
  the same fact appears in both the overview and the deep-dive, and
  one of them rots first. Multi-file with a thin overview keeps the
  overview's narrative role distinct from the per-topic file's
  reference role. The pattern is also already proven elsewhere in this
  project: `docs/learnings/`, `docs/decisions/`, `docs/features/`,
  `docs/architecture/` are all multi-file with no monolith.

- **G-1 over G-2 (split appendices) and G-3 (inline-only).**
  Bidirectional cross-references that live in *two* places (an
  appendix in `docs/game/` and one in `docs/engine/`) are a double-
  maintenance trap; the same Striker-vs-`C_*_C` mapping would be
  written twice and drift. Inline-only cross-references handle the
  per-topic-file case but provide no central catalog where
  multi-context mappings (e.g. *Striker* having combat-Pawn /
  menu-vis / lobby-display / cosmetic representations) can be seen at
  once. A single canonical glossary is the smallest structure that
  handles both.

- **M-1 over M-2 (big-bang rewrite).** Big-bang rewrites are the
  classic way restructures fail: they accumulate scope, block other
  work, and produce one giant unreviewable PR. Topic-by-topic with a
  status table in each README makes the migration visibly incremental,
  lets feature work continue on the unmigrated topics (they fall back
  to the monolith), and surfaces drift early.

## What this commits us to

- **Subtree shape — committed.**
  - `docs/game/` and `docs/engine/` each contain a `README.md` (index + status table + reading orders + conventions) at minimum.
  - Per-topic files are kebab-case, flat (no nested subdirectories).
  - Each subtree's `README.md` lists every planned per-topic file, even if `TBD`, so future agents see the planned shape.
  - Each per-topic file ends with cross-references (related concepts in glossary, sibling per-topic files, related learnings).

- **Glossary shape — committed.**
  - One file at `docs/glossary.md`. Not split, not duplicated.
  - Entries earn their place by demonstrating real ambiguity (multi-context engine representation OR vocabulary mismatch). Clean 1:1 mappings live in per-topic files, not the glossary.
  - Each entry has the same shape: *player concept → engine representation(s) → identity key → cross-references*.
  - TBDs are first-class: better to flag uncertainty explicitly than to fabricate.

- **Migration sequence — committed.**
  - One branch per migration batch (3-5 related topics). Branch naming: `docs/game-migration-batch-N` or `docs/engine-migration-batch-N`.
  - Each batch: lift section out of monolith → improve structure on the way → replace monolith section with stub link → flip README status from `TBD` to `migrated` → update glossary cross-references.
  - Final migration (last topic per domain): delete the monolith and write a learning entry capturing what (if anything) was consciously dropped.
  - Until a topic is migrated, the source monolith remains canonical for it. The README status table is the source of truth for migration state.

- **AGENTS.md slot — committed (already done in foundation commit).** `docs/glossary.md` is item 5 of pre-work reading; `docs/engine/` is named as the planned migration target for `KNOWLEDGEBASE.md`; "When in doubt" routes engine questions through the glossary first.

- **Default for new knowledge docs — committed.** New domain docs use the multi-file subtree pattern from day 1. New cross-domain ambiguities get glossary entries. If a future ADR proposes a different pattern for a specific domain, that ADR supersedes this one for that domain.

## What this rules out (until superseded)

- **New 500+ line knowledge monoliths** at the project root or as solo
  docs. (Single-finding diaries and ADRs themselves don't count —
  those have their own appropriate forms.) New large knowledge
  artifacts must use the multi-file subtree pattern from authoring.
- **Bidirectional appendices** inside subtrees (e.g.
  `docs/game/engine-cross-reference.md` + `docs/engine/game-cross-reference.md`).
  Use the central glossary.
- **Indefinite coexistence** of monolith + per-topic files for the
  same content. The migration status table forces termination — each
  topic eventually migrates and the monolith eventually disappears.
- **Skipping the README status table.** A subtree without a populated
  README is invisible to agents and rots silently.

## Revisit when

- A domain's subtree grows past ~20 per-topic files → reopen D
  (consider hierarchical subdirectories within the subtree, or split
  the domain).
- The glossary grows past ~30 entries → reopen G (consider splitting
  by axis, or moving heavy entries into per-topic deep-dives with
  glossary-entry stubs).
- A migration stalls for >3 months with un-migrated topics in the
  monolith → reopen M (consider whether the boundary-defining
  decisions in the README were wrong, or whether the migration
  cadence is broken).
- A new domain emerges that doesn't fit *game* or *engine* (e.g. a
  *protocol* / *backend-api* domain that's neither player-side nor
  UE-side) → not a supersession; just add a new subtree following the
  same pattern.

## Considered and rejected

- **D-2** — Single monolith per domain. The status quo on the day this
  ADR was drafted; the pattern that produced both the 750-line KB and
  the 1414-line OMEGA_STRIKERS_GAME.md. Failure mode known and lived.
- **D-3** — Hybrid: monolith narrative + per-topic deep-dives.
  Duplication risk; same fact lives in two places and one rots first.
- **D-4** — Pure flat multi-file with no overview/narrative entry.
  Loses the "first-time read for context" path; agents either skim the
  README and miss context or read every file (expensive).
- **G-2** — Split bidirectional appendices (one in `docs/game/`, one
  in `docs/engine/`). Double-maintenance trap; mappings drift between
  the two appendices.
- **G-3** — Inline cross-references only, no central catalog. Handles
  per-topic-file links but doesn't surface multi-context mappings
  (e.g. *Striker* across combat / select / lobby / cosmetic) in any
  one place.
- **G-4** — No glossary; rely on grep + naming conventions. Fails on
  engine-vs-player vocabulary mismatches (grep "Core" finds nothing
  about the puck because the engine name is "Rock").
- **M-2** — Big-bang rewrite. Classic restructure-failure pattern;
  blocks other work; produces unreviewable diffs.
- **M-3** — Leave existing monoliths as-is; only use subtrees for new
  docs. Locks in the worst of both worlds — monolith failure mode
  preserved on the high-traffic legacy docs.

## Related

- **Forced by:** `docs/game/OMEGA_STRIKERS_GAME.md` (the 1414-line
  monolith authored 2026-04-29) + maintainer's "KB is long overdue"
  observation in the same session.
- **Relies on:** none — orthogonal to ADR 0001 (identity) and 0002 (storage).
- **Supersedes:** none — this is a new decision area.
- **Code locations** (post-acceptance):
  - `docs/glossary.md` — canonical concept catalog (committed `9775d9a`).
  - `docs/game/README.md` — game-subtree index + status table (committed `9775d9a`).
  - `docs/engine/README.md` — engine-subtree index + status table (committed `9775d9a`).
  - `AGENTS.md` — pre-work reading + "When in doubt" updates (committed `9775d9a`).
  - Per-topic files under `docs/game/` and `docs/engine/` — to be created on migration branches.

## Notes

- This ADR is mildly retroactive: the foundation commit (`9775d9a`)
  landed the structural decision before the ADR existed. The honest
  alternative — write the ADR first, then implement — would have
  prevented the inversion. Lesson for future structural decisions:
  draft the ADR before any commits, even when the discussion in chat
  feels like sufficient sign-off. The ADR is the permanent record;
  chat is not.
- The `_archive/vision-v1-superseded.md` was the closest prior
  artifact to a knowledge-doc structural decision and got it wrong by
  recording locks without alternatives. This ADR is what that should
  have looked like.
- The `docs/architecture/` subtree is a partial precedent — it's
  multi-file but has no `README.md` index and no glossary
  cross-references. It pre-dates this ADR. A small follow-up to align
  it (add a `README.md`, link relevant glossary entries) is reasonable
  but not blocking.
