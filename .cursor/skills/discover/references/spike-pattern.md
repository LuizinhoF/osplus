# Discover — spike pattern

The escape hatch for **Low-confidence** verdicts in Step 5. A spike is a throwaway hack whose entire purpose is to validate **one** uncertain assumption with real evidence.

The reason this pattern exists: when the verdict is Low ("should work, no direct evidence"), continuing into Stage 4 (Design) is malpractice — design effort is wasted if Build later proves the foundation false. Spikes resolve the foundation question first, then Stage 3 re-rates with real evidence.

## When to spike (and when not to)

Spike when **all** of these hold:

- The Step 5 verdict came back **Low**.
- There's a specific, isolated assumption whose disproof would invalidate the feature.
- A throwaway implementation can test that assumption in less than ~2 hours.
- The user agrees a spike is the right next move (paired stance — surface the option, don't barrel into a branch).

Do NOT spike when:

- The verdict is Medium or above — those go to Stage 5 with a thin slice or full implementation, not a spike.
- The unknown can be resolved by a Step 4 technique (dump / source-read / hook + log) you haven't tried yet — exhaust those first; spikes are more expensive.
- Multiple assumptions are uncertain — that's a sign Stage 3 isn't done. Go back to Step 2 and decompose, then spike the load-bearing one.
- The "spike" you're imagining is actually the feature — that's not a spike, that's Stage 5.

## The pattern

### Branch naming

```
spike/<feature-slug>/<one-assumption>
```

One assumption per branch. If you need to test two things, that's two spikes (potentially in parallel branches off the same point), not one branch testing both.

Examples:
- `spike/in-game-profile-mvp/playerstate-readable-from-modactor`
- `spike/community-event-emote-pack/showemoticon-out-of-match`
- `spike/queue-status-overlay/menu-widget-attachable-pre-match`

### What goes in the spike branch

- The **minimum** code that exercises the assumption.
- Diagnostic logging that records what happened.
- No tests, no clean abstractions, no "while I'm here" cleanup.
- No production-ready error handling — when the spike crashes, the crash *is* evidence.
- A `SPIKE_NOTES.md` at the root of the spike branch (or in the spike-relevant directory) summarizing what's being tested.

### What does NOT go in the spike branch

- The actual feature implementation (even partial).
- Refactors to "make spiking easier" that touch shared code paths.
- Anything that anyone reviewing the diff might mistake for production-bound work.
- Commits that merge cleanly into `main` (intentionally — keep them obviously throwaway).

## Running a spike

1. **Branch off** the current Stage 3 working state (typically off `main` or off whatever branch the feature would be implemented on, before any feature code exists).
2. **Write the minimum code** to exercise the one assumption. Add the logging that will tell you what happened.
3. **Deploy via the normal harness** (`deploy.ps1` for Lua-only spikes; full cook + pak only if absolutely needed — most spikes don't need the full pipeline).
4. **Run the game**, trigger the path, observe the logs.
5. **Decide:** assumption confirmed? Falsified? Inconclusive?
6. **Write the spike report** (see template below).
7. **Return to Step 5** of the playbook with the new evidence — re-rate confidence.

## When to abort a spike

Abort and re-pair with the user when:

- Setup is taking longer than the spike itself was supposed to take.
- The spike requires changes to shared code that you're not sure are safe.
- The spike's first run produces a different failure than the assumption was about (you've stumbled into a different problem — surface it before chasing).
- You realize mid-spike that the assumption isn't actually load-bearing.

A clean abort is normal and not a failure. Spikes are cheap so we can abort them.

## Spike report template

Paste this section into the feature doc's `## Feasibility` (under `Evidence trail`) when the spike concludes. Then delete the spike branch (the report holds the value, the code does not).

```markdown
**Spike: <one-assumption>** (`spike/<feature-slug>/<one-assumption>`)

- **Hypothesis tested:** <restate the assumption being validated>
- **What was built:** <1-2 sentences — what the spike code actually did>
- **What happened:** <verbatim relevant log output / behavior observed>
- **Verdict on the assumption:** <Confirmed | Falsified | Partial: <what's still uncertain> | Inconclusive: <what would resolve it>>
- **New unknowns discovered:** <anything the spike surfaced that wasn't in the original Step 2 list — these may need their own spikes or evidence>
- **Implication for the feature verdict:** <does Step 5 verdict change? to what tier? recommended Stage 5 path?>
- **Branch disposition:** <`deleted` (default) | `kept open: <reason>`>
```

## After the spike

Once the report is written and the verdict re-rated:

| New verdict | What happens next |
|---|---|
| **High** (assumption confirmed cleanly) | Proceed to Stage 4 (Design) with full feature scope |
| **Medium** (assumption confirmed with caveats) | Proceed to Stage 4, but design for a thin slice first |
| **Low still** (spike was inconclusive — rare) | Pair with the user: try a different spike angle, or shelve |
| **Not feasible** (assumption falsified, no workaround visible) | Update feature doc → `## Outcome: shelved`. Write a learning. The spike's value was preventing a wasted Stage 4-5. |

The spike branch gets deleted in all four cases (the report in the feature doc holds the knowledge). Exceptions:

- The spike branch is staying open because a follow-up spike on the same code is imminent.
- The spike code accidentally produced something independently useful (a debug helper, a dump utility) — extract that into a real branch under `tools/re/`, then delete the spike branch.

## Anti-patterns

The spike pattern is easy to abuse. Recognize these:

- **Spike-as-implementation.** "I'll just make it actually work while I'm here." The moment you're polishing or generalizing, you've left spike territory. Stop, return to Step 5, start a real Stage 5 branch.
- **Multi-assumption spike.** Testing two things at once means a partial result tells you nothing. One assumption per spike.
- **Production code in spike branches.** The diff should look obviously throwaway. If it doesn't, the spike isn't really a spike.
- **Skipping the report.** The spike's value isn't the code — it's the evidence captured back into Stage 3. No report = no value, regardless of what the code did.
- **Spike before exhausting cheap evidence.** If a dump or source-read could have answered the question, you wasted the spike effort.
