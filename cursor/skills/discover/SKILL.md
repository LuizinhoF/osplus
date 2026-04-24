---
name: discover
description: Reverse-engineering and feasibility investigation. Use when answering "is X possible in OS?", "can we hook Y?", "what's the data shape of Z?", or as Stage 3 of the dev cycle for a framed feature. Produces a Feasibility section in a feature doc, or a learning entry / KNOWLEDGEBASE update for standalone RE.
---

# Discover

You are a specialized sub-skill for reverse-engineering and feasibility investigation. You produce **evidence-backed verdicts**, not implementations. Your output is either a `## Feasibility` section in `docs/features/<slug>.md` (feature-driven mode) or a `docs/learnings/` entry / `KNOWLEDGEBASE.md` update (standalone mode).

The reason this skill exists: design and build phases are downstream of "do we even know how this works?" Skipping that question is the canonical OSPlus failure mode — features get designed against assumed-but-unverified facts, then Stage 5 hits a wall because the assumed hook doesn't exist or the assumed data shape is wrong. See [`docs/learnings/lifecycle-design-back-edges-and-confidence-tiers.md`](../../../docs/learnings/lifecycle-design-back-edges-and-confidence-tiers.md) for why this skill exists separately from `feature-design`.

## When to use

Use this skill when **any** of the following is true:

- Stage 3 of the dev cycle for a feature whose Brief just landed in `docs/features/<slug>.md`.
- A standalone RE question: "how does X work in OS?", "where is Y owned in the engine?", "what's the data shape of Z?"
- A feasibility check requested directly: "before we design this, can we even do it?"
- Stage 4 (`feature-design`) routed back here because the feature doc lacks a `## Feasibility` section.

Skip this skill (just answer / just implement) when:

- The question has a documented answer in `KNOWLEDGEBASE.md` or an existing feature doc's `## Feasibility` section. Read it instead of re-running the playbook.
- The change is mechanical (rename, log line, refactor) and doesn't touch unfamiliar engine territory.
- A spike result already exists for the specific assumption being tested.

If the question is "is something broken?" — that's `bug-investigate`, not this skill.

## Two modes

This skill operates in one of two modes depending on the trigger:

| Mode | Trigger | Output destination |
|---|---|---|
| **Feature-driven** | Stage 3 for a specific feature with a `docs/features/<slug>.md` brief | `## Feasibility` section of that feature doc |
| **Standalone** | Open RE question not tied to a current feature | Direct to `docs/learnings/<slug>.md` or `KNOWLEDGEBASE.md` |

The playbook below applies to both modes. The differences are in the output destination and in how findings are structured for write-out. See [`references/standalone-mode.md`](references/standalone-mode.md) for standalone-specific guidance.

---

## The playbook

Six steps. Each has an explicit **ask point** — this skill runs in the project's default-paired stance, so the agent stops and surfaces choices rather than barrelling through.

Full playbook detail (the technique→tool mapping, the assumption-list discipline, the verdict-writing rules) lives in [`references/playbook.md`](references/playbook.md). The skeleton below is what to follow when running the skill end-to-end.

### Step 1 — Search prior knowledge

Before any new investigation:

1. Grep `KNOWLEDGEBASE.md` for the subsystem / class / UFunction names involved.
2. Grep `docs/learnings/` (titles via `docs/learnings/README.md` index, then full files for hits).
3. Grep `docs/features/*.md` `## Feasibility` sections for prior investigations of the same area.
4. Check `docs/decisions/` — an accepted ADR may already constrain the answer.

**Ask point:** "Found these N relevant priors: [list]. Worth re-reading any in detail before continuing? Or proceed to listing unknowns?"

### Step 2 — Name the unknowns

From the brief (or the standalone question) plus prior knowledge, list what we don't know. Be **specific** — each unknown should be falsifiable:

- Bad: "Does emoting work?"
- Good: "Does `UEmoteWidget::ShowEmote` succeed when called outside an active match?"

The unknown list is the contract Stage 3 is investigating. Anything not on the list won't get verified, and Stage 5 may hit it as a wall later.

**Ask point:** "Here are the unknowns: [list]. Did I miss any? Any I should drop as out of scope?"

### Step 3 — Pick a technique per unknown

Map each unknown to the cheapest evidence-gathering technique. The technique→tool table:

| Need | Tool | Game running? |
|---|---|---|
| UFunction / UClass / property signatures | UE4SS `DumpAllObjects` / Lua `UEHelpers` | Yes (state matters) |
| Asset header / FName table | `parse_uasset.ps1` | No |
| Diff two cooked outputs | `compare_uexp.ps1` | No |
| Live property values during gameplay | UE4SS Lua hook + log | Yes (in match) |
| Engine internals (how UE 5.1 does X) | Read `F:\UE510\UnrealEngine-5.1.0-release\` | No |
| Snapshot game state | `tools/re/` (work in progress) | Yes |
| Analogous mods / community patterns | Web search | No |

(Full mapping with examples in [`references/playbook.md`](references/playbook.md).)

**Ask point:** "Plan: A via [technique], B via [technique], C via [technique]. Anything that needs the game running, you'll need to launch. Approve before I start?"

### Step 4 — Execute

Run techniques in order. Record findings as you go in the destination doc (feature doc `## Feasibility` section, or a draft for standalone).

For each finding, capture:
- Technique used.
- Verbatim output (or distinctive substring).
- What it resolved or contradicted.

**Ask point:** After each surprising finding (one that contradicts an assumption or invalidates the plan): "This finding contradicts assumption X — change direction or note it and continue?"

### Step 5 — Write the verdict

Per assumption: was it resolved? With what confidence?

Aggregate per-assumption confidence into a feature verdict:

| Tier | Criteria |
|---|---|
| **High** | All load-bearing assumptions tested live or verified in shipped code; analogous pattern already works in OSPlus. |
| **Medium** | Most assumptions inferred from code-reading or analogous patterns; not yet tested in the specific context. |
| **Low** | Theoretical only; no direct evidence; relies on "should work" reasoning. |
| **Not feasible** | At least one load-bearing assumption was disproven, no workaround found. |

Write the verdict + confidence + assumption list into the destination doc. Recommend Stage 5 path: `full feature` (High) / `thin slice first` (Medium) / `spike first` (Low) / `shelve` (Not feasible).

**Ask point:** "Draft verdict: [tier]. Assumptions: [list]. Recommended Stage 5 path: [path]. Concur, or push back?"

### Step 6 — Promote findings (the compounding step)

Anything generally reusable (engine fact, UE4SS pattern, OS internal that future features will care about) → write a `docs/learnings/` entry or append to `KNOWLEDGEBASE.md`.

**Promotion default** (per project policy):

| Finding shape | Default action |
|---|---|
| Obviously general (engine quirk, UE4SS API behavior, OS internal not tied to one feature) | Auto-promote to `docs/learnings/` |
| Judgment call ("is this general enough?") | **Ask first** |
| High-stakes write (modifying `KNOWLEDGEBASE.md`) | **Ask first**, regardless of generality |

**Ask point:** "Finding [X] looks generally reusable — I'll write a learning entry. Finding [Y] could go either way — promote or keep feature-local?"

---

## The spike sub-loop

When Step 5 produces verdict = **Low**, the skill triggers the spike sub-loop. This is a controlled escape hatch for "we need real evidence, not more theorizing."

Spike pattern, branch naming, abort conditions, and report format live in [`references/spike-pattern.md`](references/spike-pattern.md). Run that reference before starting any spike work.

**Hard rule:** spike branches are throwaway. If you find yourself building the actual feature inside the spike, **stop**, return to Step 5 to re-rate confidence with the new evidence, and start a real Stage 5 branch.

---

## Output Format

### Feature-driven mode

Append to `docs/features/<slug>.md` `## Feasibility` section using the template structure (verdict + rationale + assumptions + evidence trail + promoted findings + recommended path).

End the session with a structured summary:

```
═══════════════════════════════════════════════
DISCOVER (feature: <slug>)
═══════════════════════════════════════════════

── STEP 1: PRIOR ART ──
<from §1>

── STEP 2: UNKNOWNS ──
<from §2>

── STEP 3: PLAN ──
<from §3>

── STEP 4: EVIDENCE ──
<from §4>

── STEP 5: VERDICT ──
Tier: <High | Medium | Low | Not feasible>
Recommended Stage 5 path: <path>
Assumptions: <list>

── STEP 6: PROMOTIONS ──
<learnings written / KNOWLEDGEBASE updates / "none">

── DESTINATION ──
docs/features/<slug>.md updated. Ready for Stage 4 (feature-design).
═══════════════════════════════════════════════
```

### Standalone mode

See [`references/standalone-mode.md`](references/standalone-mode.md) for the structured-summary shape (different — output goes to `docs/learnings/` or `KNOWLEDGEBASE.md` directly, no feature doc).

---

## Rules

1. **Search prior knowledge first.** Step 1 is non-skippable. The whole compounding model depends on not re-deriving what previous Stage 3s already learned.
2. **Assumptions are explicit, named, and testable.** Burying assumptions inside a verdict means Stage 5 hits them as walls. Each assumption is something a future loop-back can reference precisely.
3. **Confidence is honest, not optimistic.** When in doubt between two tiers, pick the lower one. Optimistic Medium that should have been Low is the failure mode.
4. **Verbatim outputs in evidence.** Paste the dump fragment, the parsed output, the log line. Paraphrasing loses the detail Stage 5 will need.
5. **Spike code is throwaway.** Do not let a spike turn into the implementation. Hard-stop and start a real branch.
6. **Compounding is the point.** Step 6 is not optional — the next feature investigating the same area is supposed to start with cheaper context.
7. **No design in this skill.** If you find yourself proposing how to build the feature, that's Stage 4 work. Stop and hand off.
8. **Default-paired everywhere.** Each ask point is real. Don't barrel through the playbook silently.
