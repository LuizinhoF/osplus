# Discover — standalone mode

The `discover` skill normally runs as Stage 3 of the dev cycle for a specific feature. **Standalone mode** is when it runs without a feature attached — to answer an open RE question, build out general knowledge of an engine area, or proactively map territory before any feature needs it.

The playbook in `references/playbook.md` still applies. The differences are in scope, output destination, and ask-point shape.

## When standalone mode is the right choice

Use standalone mode when **any** of these is true:

- The user asks a question of the form "how does X work in OS?" without proposing a feature on top.
- An RE finding from a feature investigation is generally interesting and the user wants to chase it independently.
- You're building out coverage of an engine area (e.g. "let's understand the WBP_ReactionModal stack thoroughly") so future feature feasibility checks are cheaper.
- A learning entry contradicts current shipped code and needs verification.

Use feature-driven mode (the SKILL.md flow) when there's a `docs/features/<slug>.md` brief that's expecting a `## Feasibility` section. **If both apply** — the user asked a feature-shaped question — surface the choice: "I can investigate this as a standalone RE pass (output goes to learnings/KNOWLEDGEBASE) or as Stage 3 for a feature (we'd Frame it first into a feature doc). Which?"

## What changes vs. feature-driven mode

| Aspect | Feature-driven | Standalone |
|---|---|---|
| Trigger | `docs/features/<slug>.md` `## Brief` exists | Open question or proactive coverage |
| Step 1 prior-art search | Same |  Same |
| Step 2 unknowns | Derived from the brief | Derived from the question or scope statement |
| Step 3 plan | Estimated against the feature's urgency | Estimated against curiosity / coverage value |
| Step 4 evidence | Recorded into draft feasibility section | Recorded into a draft learning / KNOWLEDGEBASE addition |
| Step 5 verdict | Feature verdict (High/Med/Low) + Stage 5 recommendation | "Question answered" verdict — what we now know vs. what's still open |
| Step 6 promotion | Same — but the destination *is* the standalone learning, so promotion is the primary write, not a side effect |
| Output destination | `docs/features/<slug>.md` `## Feasibility` | `docs/learnings/<slug>.md` (new) or `KNOWLEDGEBASE.md` (append) |
| Recommended next step | Stage 4 design | Possibly: spawn a feature (escalate to Stage 1 Capture); add to ROADMAP `Open questions`; or simply close as documented |

## Scoping a standalone investigation

Before Step 1, pin down the scope explicitly. Standalone investigations have no brief to anchor them, so they can sprawl.

```
SCOPE
  Question: <1 sentence — the actual question being answered>
  Out of scope: <what we're NOT going to investigate even if it surfaces>
  Coverage target: <"answer the question and stop" | "map the area for future use">
  Time box: <agent's best estimate; ask user to confirm>
```

The time box is a guardrail. If standalone mode is taking 3x the box, surface it — the user may want to narrow scope or convert to a feature.

## Output destination decision

Where does a standalone investigation's output land?

| Finding shape | Destination |
|---|---|
| Single new fact about engine / UE4SS / OS internals | `docs/learnings/<slug>.md` (new entry) |
| Multiple related facts that map an area | `KNOWLEDGEBASE.md` new section (or expand existing); maybe also a learning summarizing the investigation |
| Correction to an existing learning | Update the existing learning; add a new one *only* if the new finding is independently useful |
| Correction to `KNOWLEDGEBASE.md` | Update the section; add a learning entry explaining what was wrong and how it was caught |
| Question turned out to be already answered (Step 1 win) | No new write; reply to the user with the existing source |
| Question turned out to be infeasible to answer with current tooling | Write a learning explaining the dead-end (which techniques you tried, what they didn't tell you, what would be needed to answer) — this prevents re-investigation |

Per project policy, `KNOWLEDGEBASE.md` writes are **always ask-first**, regardless of mode.

## Standalone-mode output format

Use this structured summary at the end of the investigation:

```
═══════════════════════════════════════════════
DISCOVER (standalone)
═══════════════════════════════════════════════

── SCOPE ──
Question: <restated>
Coverage target: <answer-and-stop | map-for-future-use>

── STEP 1: PRIOR ART ──
<from §1>

── STEP 2: UNKNOWNS ──
<from §2>

── STEP 3: PLAN ──
<from §3>

── STEP 4: EVIDENCE ──
<from §4>

── STEP 5: WHAT WE NOW KNOW ──
Resolved:
  - <Unknown 1>: <answer + confidence>
  - <Unknown 2>: <answer + confidence>
Still open:
  - <Anything not resolved + why>

── STEP 6: WRITES ──
Wrote: <paths to new learnings, KNOWLEDGEBASE diffs>
Skipped: <findings considered but not promoted, with one-line reason>

── NEXT STEP ──
[ ] Closed — knowledge captured, no further action.
[ ] Should become a feature — recommend adding to ROADMAP Open questions: "<framing>".
[ ] Needs follow-up investigation — list specific unknowns left open.
═══════════════════════════════════════════════
```

## When standalone investigation reveals a feature opportunity

If a standalone investigation surfaces an "oh, we should build X" — **don't quietly start designing it**. Surface it as a Stage 1 Capture candidate:

> "While investigating <area>, I noticed [thing]. This could become a feature: <one-liner brief shape>. Add to ROADMAP Open questions, or kill?"

Standalone mode does not become feature work without the user's explicit Stage 1 → Stage 2 transition. The discipline is: *standalone produces knowledge; features start at Capture.*
