---
name: bug-investigate
description: Systematic bug investigation that searches prior art FIRST, reproduces minimally, falsifies hypotheses, then fixes and writes a learning. Use when something is broken, crashes, or behaves unexpectedly.
---

# Bug Investigate

You are a specialized sub-skill for bug investigation. You produce a structured **Investigation Document** that ends with either a fix-in-progress or a clear blocker for the user. The skill closes the loop with `learnings-discipline.mdc` — the rule says "write the learning"; this skill says "and look one up first, and use a process that produces a real finding worth logging."

The reason this skill exists: ad-hoc debugging tries N things in sequence without isolating which one mattered. The OCI relay deploy hit five separate failure modes in a row (firewall, Caddy, Node JIT, line endings, UE asset cooking) and *every one* could have been faster with prior-art lookup + falsification. See `docs/learnings/oci-relay-deploy-gotchas.md`.

## When to use

Use this skill when **any** of the following is true:

- A specific reported failure: crash, error, silent break, wrong output, unexpected UX.
- A regression: "this used to work."
- A reproducible "weird" behavior the user can't immediately explain.
- A failed deploy / build / install where the cause isn't obvious from the error message alone.

Skip this skill (just fix) when:

- The cause is staring at you in the error message and the fix is one line (typo, missing import, wrong path).
- The "bug" is actually missing functionality — that's a feature request, use `feature-design`.

If you're unsure, use it. The Phase 1 search alone takes ~2 minutes and frequently produces the entire answer.

---

## Phase 1: Prior-art lookup (do this FIRST, always)

Before any reproduction, hypothesizing, or fixing:

1. **Search `docs/learnings/`** for the symptom in two ways:
   - The error message verbatim (or its most distinctive substring).
   - The subsystem involved (`grep -ri chat docs/learnings/`, `grep -ri pak docs/learnings/`, `grep -ri sidecar docs/learnings/`, etc.).
2. **Skim `docs/learnings/README.md`** index for anything related — entry titles are the cheapest filter.
3. **Check the relevant code-conventions rule** for known footguns. Many "bugs" are actually a documented language footgun (e.g. `$LASTEXITCODE` not tripping `$ErrorActionPreference = "Stop"` — see `powershell-conventions.mdc`).
4. **Check `KNOWLEDGEBASE.md`** for any documented engine/UE quirks if the bug touches game-side behavior.

Produce:

```
PRIOR ART
  Searched for: <terms>
  Found:
    - <path/to/learning.md> — <1-sentence relevance>
    - <or "no direct match; closest is X">
  Decision:
    [ ] Documented fix applies — apply it. (Skip to Phase 4.)
    [ ] Related learning gives partial context — proceed with Phase 2 informed.
    [ ] Nothing relevant — proceed with Phase 2 cold.
```

If a documented fix applies, **use it**. Don't reinvent. Apply the fix, verify, and skip directly to Phase 4 (where you may *update* the existing learning if the fix needed adjustment).

---

## Phase 2: Reproduce minimally

You don't have a bug until you can reproduce it. "It happened once" is a report, not a bug.

```
REPRODUCTION
  Setup: <what state the system needs to be in — branch, build, game state, etc.>
  Steps:
    1. <minimal action>
    2. <minimal action>
    ...
  Expected: <what should happen>
  Observed: <what actually happens — verbatim error / log lines / screenshot reference>
  Reproducibility: <always | intermittent (Y/N runs) | cannot reproduce>
```

If you cannot reproduce after a reasonable attempt, STOP and surface that to the user with concrete questions:

- "Was it after a map transition?"
- "Was the relay running? Check `journalctl -u osplus-relay -n 50` from the time of the failure."
- "Do you have the Lua log file (`%LOCALAPPDATA%/UE4SS/.../osplus.log`) from that session?"

A bug you can't reproduce is a bug you can't fix; gathering more evidence is real work, not a delay.

**Minimization matters.** "Crashes after playing a full match" is a starting point; "crashes when chat sends a message during the post-match transition" is a bug you can fix in an hour. Cut everything that isn't load-bearing for the symptom.

---

## Phase 3: Hypothesize + falsify

Form 1-2 hypotheses about cause. **For each hypothesis, write the observation that would falsify it** before running any check.

```
HYPOTHESES
  H1: <plausible cause in 1 sentence>
    Falsifies if: <concrete observation that would prove H1 wrong>
    Check: <what you'll do/grep/read to make that observation>

  H2: <alternative plausible cause>
    Falsifies if: <...>
    Check: <...>
```

Then run the checks. **Run the falsification check before the confirmation check** — it's cheaper to be told you're wrong than to convince yourself you're right.

```
RESULTS
  H1: [confirmed | falsified | inconclusive]
    Evidence: <what you observed>
  H2: [confirmed | falsified | inconclusive]
    Evidence: <what you observed>
```

If both are inconclusive, you don't have enough hypotheses — go form better ones, don't start trying fixes blind. Common second-pass moves:

- Add logging at the suspected boundary, reproduce again with the new logs.
- Bisect: when did this last work? `git log --oneline` between then and now.
- Strip layers: does the bug reproduce with the relay bypassed (sidecar logs only)? With the sidecar bypassed (file IPC manually inspected)? With UE bypassed (run sidecar standalone)?

---

## Phase 4: Fix + verify + write learning

```
FIX
  Change: <files modified, in 1-2 sentences>
  Why this addresses the cause: <link the fix to the confirmed hypothesis>

VERIFICATION
  Reproduction case from Phase 2 now: <PASS / FAIL>
  Side effects checked: <related code paths you confirmed didn't regress>

LEARNING
  Action: [new entry | update existing entry: <path>]
  Slug: <short-kebab-slug>
  Trigger condition met (per learnings-discipline.mdc):
    [ ] >30 min debugging
    [ ] new engine/platform fact
    [ ] new failure mode
    [ ] tool/harness/build/deploy change
    [ ] prior doc was wrong
```

Then **actually write or update the learning** per `docs/learnings/_TEMPLATE.md`, add it to the index in `docs/learnings/README.md`, and add an in-code comment at the fix site (`-- See docs/learnings/<slug>.md`).

**The investigation is not done until the learning is written.** This is the rule, not a suggestion.

If no trigger condition was met (genuinely trivial fix), say so explicitly:

```
LEARNING
  None — fix was trivial (typo / one-char change / no new fact discovered).
  Trigger conditions: none met.
```

---

## Output Format

Your final output MUST follow this structure:

```
═══════════════════════════════════════════════
INVESTIGATION: <bug name / symptom>
═══════════════════════════════════════════════

── PHASE 1: PRIOR ART ──
<from §1>

── PHASE 2: REPRODUCTION ──
<from §2>
(skipped if Phase 1 found a documented fix)

── PHASE 3: HYPOTHESES ──
<from §3>
(skipped if Phase 1 found a documented fix)

── PHASE 4: FIX + LEARNING ──
<from §4>

═══════════════════════════════════════════════
```

---

## Rules

1. **Prior art first, always.** Phase 1 is non-skippable. Documented fixes exist *because someone burned time finding them*; not using them re-burns that time.
2. **Falsify before confirm.** For each hypothesis, write the disproof condition before checking. This is the antidote to "tried 5 things in sequence without isolating which mattered."
3. **No fix without reproduction.** "I think this might be it" without a verified reproduction is a guess. Guesses ship as new bugs.
4. **Minimize the repro.** Every irrelevant step in the reproduction is a place future-you wastes time.
5. **One change at a time during diagnosis.** Don't simultaneously update the relay AND patch the sidecar AND restart the game while trying to identify a cause. You'll never know which one mattered.
6. **The investigation ends at the learning.** No exceptions for "I'll write it tomorrow." If you don't have time to write it, you don't have time to call the bug fixed.
7. **Update existing entries when relevant.** If a learning already exists for a related symptom and your investigation refined or extended it, *update* that entry rather than creating a duplicate. Cross-link from the index.
