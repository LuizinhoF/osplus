# Discover — full playbook

The expanded version of the six-step playbook in `SKILL.md`. Read this when you're actually running the skill, not the SKILL.md alone — SKILL.md is the orchestration guide; this is the technique manual.

## Step 1 — Search prior knowledge

The compounding model only works if every investigation starts here. Treat Step 1 as the *most likely* place to find your answer, not a checkbox.

### What to search

| Source | Why | How |
|---|---|---|
| `docs/learnings/README.md` index | Cheapest filter — slug + one-liner per entry | Skim, then full-read hits |
| `docs/learnings/*.md` (full text) | Hit content, not just titles | Grep for class names, UFunction names, error substrings |
| `KNOWLEDGEBASE.md` | Engine + game internals reference | Grep + read surrounding section |
| `docs/features/*.md` `## Feasibility` sections | Prior Stage 3 work in the same area | Grep for class/UFunction/asset names |
| `docs/decisions/` accepted ADRs | Constraints that may already answer the question | Read ADRs in the relevant area; don't propose what's already decided |
| `docs/architecture/state-contract.md` | Lua/BP boundary | Read if the unknown is about state ownership or message flow |
| `docs/research/` | Background on the agentic stack and engine project | Usually only relevant if the question is meta |

### What to write

```
PRIOR ART
  Searched for: <terms — be specific so future Step 1s can grep your work>
  Found:
    - <path/to/source.md> — <1-sentence relevance>
    - <or "no direct match; closest is X but not relevant because Y">
  Decision:
    [ ] Documented answer applies — done. Write up using the documented answer; no new investigation.
    [ ] Related context narrows the unknowns — proceed informed.
    [ ] Nothing relevant — proceed cold.
```

If a documented answer applies fully, **use it**. Don't re-investigate to "verify." Verification of already-shipped knowledge is a different exercise and should be triggered by evidence of staleness, not by default.

## Step 2 — Name the unknowns

Each unknown must be **falsifiable** — there has to be a concrete observation that would resolve it as Yes, No, or Partially.

### Anti-patterns

- "Does this feature work?" — not falsifiable; needs to decompose.
- "Is the engine ready for this?" — too abstract.
- "How do we make this fast?" — performance question, not a feasibility question.

### Good shape

- "`UEmoteWidget::ShowEmote` accepts a `PMEmoteData*` and renders an emote in the active world."
- "Hook X fires once per match start, not once per pawn possess."
- "Cooked .pak from UE 5.1.0 (source build) loads correctly into the 5.1.0 game runtime — no schema mismatches."

### Categorize each unknown

For Step 3 to pick a technique, classify what *type* of unknown each is:

| Category | Example |
|---|---|
| Existence | Does class/UFunction/property X exist? |
| Signature | What params/return type does X have? |
| Lifecycle | When does X fire / become available / become invalid? |
| State shape | What's the layout of struct/object X at runtime? |
| Reachability | Can we call X from Lua? From this hook? In this context? |
| Cost | What's the overhead / latency / size of doing X? (rare in OSPlus, not RE-shaped) |
| Side effects | What else happens when we do X? |

Knowing the category drives Step 3.

## Step 3 — Pick a technique per unknown

Full technique table:

| Category of unknown | Cheapest technique | Backup if cheap one fails |
|---|---|---|
| Existence (class / UFunction) | UE4SS `DumpAllObjects` (or UEHelpers in Lua) — game running | Read engine source / UE4SS dumps from a prior session if stale |
| Signature (params / return) | UE4SS `DumpAllObjects --headers` — game running | Read engine source for matching base class |
| Lifecycle (when does X fire) | UE4SS Lua hook with logging — game running, in match | Read engine source for invocation sites |
| State shape (struct layout) | UE4SS Lua hook + property iteration — game running | `parse_uasset.ps1` for asset-side |
| State shape (asset on disk) | `parse_uasset.ps1` | UAssetGUI for visual inspection |
| Reachability from context | Hook + log call attempt — game running | Read engine source for visibility / virtual chain |
| Diff between two cooked outputs | `compare_uexp.ps1` | Manual hex diff |
| Engine internals | Read `F:\UE510\UnrealEngine-5.1.0-release\` source | Web search for matching UE 5.1 docs / forum threads |
| Mod / community pattern | Web search (UE4SS forums, modding Discords, GitHub) | None — if no public knowledge, treat as low-confidence |
| OSPlus shipped code does X | `Grep`/`Read` in our own `mod/`, `sidecar/`, `server/` | Read git history with `git log -p` |

### Coordination with the user

If a technique requires the game running, **don't assume it's running**. Ask: "I need the game launched and at the [main menu / in a match / on the post-match screen] for this. Ready when you are." Don't try to start a probe before that's confirmed.

### Plan template

```
PLAN
  Unknown 1: <restate>
    Technique: <tool> (game state: <required>)
    Expected output shape: <what you'll be looking at — header dump, hook log, asset bytes, etc.>
  Unknown 2: ...
  ...
  Estimated total time (your best guess): <minutes>
```

The estimate matters because it lets the user say "skip the longest one if its assumption isn't load-bearing for the verdict."

## Step 4 — Execute

Run techniques. **Record findings as you go**, not at the end. Mid-investigation memory is unreliable.

### What to record per finding

```
FINDING <N> (Unknown: <which one>)
  Technique: <tool used>
  Performed: <what you ran — exact command, exact hook, etc.>
  Output (verbatim or distinctive substring):
    ```
    <paste — code block, dump fragment, log line>
    ```
  Resolves unknown? <Yes — confirms | Yes — falsifies | Partial: <what's still open> | No — inconclusive>
  Surprises: <anything unexpected, even if not directly relevant>
```

### When to stop and ask

- A finding contradicts a prior assumption (yours or the brief's).
- A technique fails with an error you don't immediately understand (don't iterate blindly — surface and pair).
- The investigation is taking ≥3x your estimate — surface time pressure to the user.
- A finding suggests the brief is asking the wrong question.

### When to keep going silently (rare)

Only when the finding confirms the expected outcome and resolves an unknown cleanly. Even then, log the finding before moving on.

## Step 5 — Write the verdict

Confidence tiers (repeated from SKILL.md for in-context reference):

| Tier | Criteria — **all** must be true |
|---|---|
| **High** | All load-bearing assumptions tested live or verified in shipped code; analogous pattern works in OSPlus today; no surprise findings during Step 4. |
| **Medium** | Most assumptions inferred from code-reading or analogous patterns; not yet tested in the specific context; minor surprises during Step 4 that didn't change direction. |
| **Low** | Theoretical only; one or more assumptions rely on "should work" reasoning; or major surprises during Step 4. |
| **Not feasible** | At least one load-bearing assumption was disproven during Step 4, no alternate path identified. |

When in doubt between two tiers, pick the lower one. Optimistic Medium that should have been Low is how Build hits walls.

### Verdict template (write into the destination doc)

```markdown
## Feasibility

**Verdict:** <High | Medium | Low | Not feasible>
**Confidence rationale:** <2 sentences>

**Assumptions:**
- <Assumption 1 — testable claim>
- <Assumption 2>
- ...

**Evidence trail:**
- <Finding 1 condensed: technique, what it showed, what it resolved>
- <Finding 2>
- ...

**Promoted findings:** <list links to learnings/KNOWLEDGEBASE updates, or `—`>

**Recommended Stage 5 path:** <full feature | thin slice first | spike first | shelve>
**Justification:** <1 sentence linking the recommendation to the verdict>
```

## Step 6 — Promote findings

Per project policy (`auto when obvious, ask when judgment-call`):

### Auto-promote (no ask required)

A finding is "obviously general" if **all** of these hold:

- The fact is about engine, UE4SS, or OS internals — not about how the current feature wants to use it.
- It would be relevant to a future feature investigating the same subsystem.
- It can be stated in 1-3 sentences without referencing the current feature.

For these, write a `docs/learnings/<slug>.md` entry following `docs/learnings/_TEMPLATE.md`. Add to the index table in `docs/learnings/README.md`. No ask.

### Ask first

- The finding might be feature-specific — surface and ask "promote or keep local?"
- The promotion target is `KNOWLEDGEBASE.md` (any KNOWLEDGEBASE write is high-stakes — many agents read it as canon, so wrong/unclear additions compound).
- The finding contradicts an existing learning or KNOWLEDGEBASE section — ask before overwriting/superseding.

### Promotion ask template

```
PROMOTION CANDIDATES
  Finding A: <one-line summary>
    Suggested target: docs/learnings/<slug>.md (new entry)
    Confidence: high — auto-promoting unless you object.

  Finding B: <one-line summary>
    Suggested target: KNOWLEDGEBASE.md → "<section>" (append)
    Confidence: medium — asking first because <reason>. Promote, keep local, or rephrase?
```

After sign-off (or auto): write the entries. Update `docs/learnings/README.md` index for new learnings. Cross-link from the feature doc's `## Feasibility` → `Promoted findings`.

The investigation is not done until Step 6 is complete. Hard rule.
