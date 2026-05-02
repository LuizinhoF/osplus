---
name: correct-knowledge
description: Update OSPlus reference docs (`docs/engine/`, `docs/architecture/`, `docs/game/`, `docs/glossary.md`, `AGENTS.md`, `KNOWLEDGEBASE.md`) when an investigation surfaces a doc claim that was wrong, incomplete, or absent. Use when evidence contradicts an existing doc claim, when a probe / RE pass reveals a fact the canonical references never captured, or when `learnings-discipline.mdc` / `decision-discipline.mdc` say "if the learning/ADR invalidates anything, update those docs too."
---

# Correct knowledge

This skill closes a specific failure mode: an investigation discovers something new (or contradicts something old), the *finding* lands in `docs/learnings/<slug>.md`, and the *canonical reference* — the doc the next agent will actually read first — keeps the stale claim.

The learning is the diary. Reference docs are what people read at the start of the next session. **Both must move together** or knowledge silently re-rots in the second-and-third places it lives.

`learnings-discipline.mdc` and `decision-discipline.mdc` already mandate this in prose ("update those docs too"). This skill is the procedural version: a non-skippable checklist that turns the rule into a workflow.

## When to use

Trigger this skill when **any** of these is true:

- An investigation produced a fact that contradicts a claim in any of: `KNOWLEDGEBASE.md`, `AGENTS.md`, `docs/engine/`, `docs/architecture/`, `docs/game/`, `docs/glossary.md`, `docs/product.md`, `docs/ROADMAP.md`, code comments, or another active doc.
- A probe / RE pass surfaced a fact the canonical reference docs never captured (the *absent* case — common after `discover` skill runs).
- A learning entry being written has an "Anti-rule overturned" / "Refutes prior learning" / superseding section — the source of the prior claim must also move.
- An ADR's *What this commits us to* / *What this rules out* section invalidates a claim in product, engine, or architecture docs.
- A `bug-investigate` Phase 4 ticked the **"prior doc was wrong"** trigger condition.

Skip this skill when:

- The work introduced something genuinely new with no overlap to existing claims (a learning entry alone is enough — there's nothing to "correct").
- The change is a typo or pure-wording fix.
- The "doc" is a third-party resource (UE4SS upstream issues, OS source dumps, official Wiki). Those aren't ours to update; capture the corrected interpretation in a learning instead.

If unsure: run the Phase 2 grep. If it returns hits, you're in scope.

---

## Phase 1 — Capture the delta

Write down the three things below in 1–3 lines each. This is the input to every later step.

```
DELTA
  Old claim: <verbatim quote from the doc, OR "absent" with a one-sentence description of the gap>
  Source:    <doc path + line, OR "no canonical doc covered this">
  New fact:  <the corrected / new claim>
  Evidence:  <log line, probe output, source-dump path, ADR section, etc.>
```

If you can't write the verbatim old claim, you don't yet know what to correct — go re-grep before continuing.

---

## Phase 2 — Find every place the claim lives

OSPlus docs deliberately repeat key facts across audiences (engine ↔ game ↔ architecture ↔ glossary). One stale claim usually has 1–3 echoes. The job is to find them all.

Run all of these. None alone is enough.

```bash
# 1. Distinctive substring of the OLD claim — catches verbatim copies.
rg -i "<distinctive substring>" docs/ AGENTS.md KNOWLEDGEBASE.md

# 2. Concept / class / function name — catches paraphrased echoes.
rg -i "<concept term>" docs/engine/ docs/architecture/ docs/game/ docs/glossary.md

# 3. Code comments referencing stale doc paths or stale facts.
rg -i "<concept term>" mod/ sidecar/ server/

# 4. Cross-doc redirect indexes — these silently rot when targets move.
rg -i "<concept term>" docs/engine/README.md docs/game/README.md docs/learnings/README.md docs/decisions/README.md
```

Then build the hit list with classification:

```
HITS
  - <path>:<line>  WRONG       — <one-line note on what's stale>
  - <path>:<line>  INCOMPLETE  — <one-line note on what's missing>
  - <path>:<line>  STALE LINK  — points at a file moved or renamed
  - <path>          ABSENT      — canonical home for this knowledge, currently empty on the topic
```

Classify every hit. The classification drives the fix.

---

## Phase 3 — Decide the canonical home

Before editing, name where the corrected knowledge *should* live going forward. The repo has a deliberate separation:

| Knowledge type | Canonical home |
|---|---|
| UE / engine runtime fact (UClass, UFunction, lifecycle, hook patterns) | `docs/engine/<topic>.md` |
| OSPlus-internal architecture (mod scripts, sidecar↔relay contract, IPC shape) | `docs/architecture/<topic>.md` |
| Player-side game reality (screens, match flow, in-match UX) | `docs/game/<topic>.md` |
| Cross-bridge between game and engine concepts (player term ↔ engine class) | `docs/glossary.md` |
| Toolchain / harness / build / deploy step | `AGENTS.md` *Toolchain* + `.cursor/rules/harnesses.mdc` (keep both in sync) |
| Workflow / agent discipline | `.cursor/rules/<rule>.mdc` |
| Per-investigation finding (the diary) | `docs/learnings/<slug>.md` |
| Architectural decision | `docs/decisions/NNNN-<slug>.md` (per `decision-discipline.mdc`) |

If no existing file is the right home, create one — but under the right top-level folder. **Do not** drop new content into `AGENTS.md` or `KNOWLEDGEBASE.md` as the *primary* home; both are indexes / briefings, not stores.

`KNOWLEDGEBASE.md` (root) is now a **redirect index** — every section points into `docs/engine/` or `docs/architecture/`. If a stale claim lives in `KNOWLEDGEBASE.md` itself rather than a redirect target, the fix is to *move* it, not edit it in place.

---

## Phase 4 — Make the corrections

For each hit from Phase 2, apply the fix that matches its classification:

- **WRONG** → edit the line in place. Preserve surrounding structure. Add `> See [docs/learnings/<slug>.md](...)` underneath when the correction is non-obvious or contested. Don't delete-and-retype paragraphs; targeted line edits keep diffs reviewable.
- **INCOMPLETE** → add the missing piece in the section that already covers the topic. Don't open a new section if an existing one is the right place.
- **ABSENT** → write the new content in the canonical home from Phase 3. If the home file doesn't exist yet, create it under the right folder *and* add a link from that folder's `README.md` index.
- **STALE LINK** → update the link target. If the old path is referenced from many places, fix the link rather than reverting the move.

**Cascade rules** — these are the ones easy to forget:

1. If `AGENTS.md` *Pre-work reading* mentions a doc whose claim you just changed, re-read that doc's blurb and confirm the description still matches.
2. If a `docs/engine/README.md` or `docs/game/README.md` index summarizes the file, update the summary too — readers hit the index first.
3. If a code comment cites the old doc location (`-- See docs/learnings/<slug>.md` style), keep the comment but verify the slug still resolves. Update if renamed.
4. If the correction invalidates a code-conventions example (`.cursor/rules/*-conventions.mdc`), update the rule.
5. If the correction belongs in `docs/glossary.md` (a player concept ↔ engine class mapping), update the glossary entry — that file is the bridge; outdated mappings there poison every cross-domain lookup.

---

## Phase 5 — Write or update the learning

Per `learnings-discipline.mdc`, the canonical-doc fix does **not** replace the learning entry. The learning captures *how the correction was found*; the doc captures *what is now true*. Both compound.

- Trigger condition met (one of: >30 min debugging, new engine fact, new failure mode, tool change, **prior doc was wrong**) → write a new entry at `docs/learnings/<slug>.md` per `_TEMPLATE.md`. Add the row to `docs/learnings/README.md` (newest first).
- Existing learning extends or refines a prior one → update in place rather than duplicate. If it supersedes, mark the prior entry `Status: superseded-by-<new-slug>`.
- The learning's narrative names the *prior claim* and the *new claim* explicitly — future readers will grep for either wording.

If the learning was already written before this skill ran (common during `bug-investigate` or `discover`), skip to Phase 6 — the learning trigger is already satisfied.

---

## Phase 6 — Verify

One re-grep, same terms as Phase 2. Anything left?

```bash
rg -i "<distinctive substring of OLD claim>" docs/ AGENTS.md KNOWLEDGEBASE.md
```

If hits remain, either:

- The hit is a *deliberate* historical reference (an ADR's *Considered and rejected* section, an archived learning) — annotate it inline as "preserved for context, see <new home>" and move on.
- The hit was missed in Phase 4 — fix it now.

Then verify the cascade checklist:

- [ ] All Phase 2 hits resolved (WRONG fixed, INCOMPLETE filled, ABSENT seeded, STALE LINK updated).
- [ ] Canonical home from Phase 3 contains the new knowledge.
- [ ] Index files (`README.md` per doc folder) updated where the correction is summarized.
- [ ] Learning entry exists and is linked from `docs/learnings/README.md`.
- [ ] No code comments left pointing at moved/renamed docs.
- [ ] If an ADR triggered this, *What this commits us to* cross-links to the new doc location.
- [ ] If `docs/glossary.md` carries a mapping for the corrected concept, the glossary line is current.

---

## Output format

Final summary:

```
═════════════════════════════════════
KNOWLEDGE CORRECTION: <one-line description>
═════════════════════════════════════

DELTA
  <from Phase 1>

HITS                   <count: WRONG / INCOMPLETE / ABSENT / STALE LINK>
  <list from Phase 2 with classification>

CANONICAL HOME
  <chosen path from Phase 3>

CHANGES
  - <file>: <one-line description of the edit>
  - ...

LEARNING
  [ new:     docs/learnings/<slug>.md ]
  [ updated: docs/learnings/<slug>.md ]
  [ none — trigger conditions not met ]

VERIFY
  [ ] re-grep clean
  [ ] indexes updated
  [ ] code comments / cross-links resolved
═════════════════════════════════════
```

---

## Rules

1. **Both move together.** A learning entry without a canonical-doc fix is a future re-derivation. A canonical-doc fix without a learning entry loses the *why*. The skill is not done until both exist.
2. **One canonical home per fact.** If the same fact appears verbatim in two places, one is the home and the other is a redirect / cross-link. Don't fork the source of truth — rot compounds.
3. **Verbatim before paraphrase.** When quoting the old claim in Phase 1, copy the wording exactly. Paraphrasing the stale claim is how the same drift recurs.
4. **Cascade is the bug.** This skill exists because docs rot silently in the *second* and *third* places they live, not the first. Phase 2's grep + Phase 4's cascade rules are non-skippable.
5. **Don't expand scope.** This skill corrects the specific stale claim in scope. Adjacent doc cleanup is a separate task; surface it but don't merge it in.
