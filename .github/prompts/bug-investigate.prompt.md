---
description: "Systematic bug investigation: prior-art lookup FIRST, reproduce minimally, falsify hypotheses, then fix and write a learning. Use for crashes, regressions, unexpected behavior."
---

# /bug-investigate

You are entering the **bug-investigate** skill. Read the full specification now and follow it exactly:

[.cursor/skills/bug-investigate/SKILL.md](../../.cursor/skills/bug-investigate/SKILL.md)

Summary of what you must do (the file above is authoritative):

1. **Phase 1 — Prior art (NON-SKIPPABLE):** Search [docs/learnings/](../../docs/learnings/) for the symptom verbatim and by subsystem. Skim [docs/learnings/README.md](../../docs/learnings/README.md). Check the relevant code-conventions rule for known footguns. Check [KNOWLEDGEBASE.md](../../KNOWLEDGEBASE.md) for engine quirks. If a documented fix applies, use it.
2. **Phase 2 — Reproduce minimally:** Setup / steps / expected / observed / reproducibility. Cut everything that isn't load-bearing. If you can't reproduce, STOP and ask the user concrete questions.
3. **Phase 3 — Hypothesize + falsify:** Form 1-2 hypotheses, write the falsification observation **before** running the check. Run the falsification check before the confirmation check.
4. **Phase 4 — Fix, verify, write learning:** Apply [docs/learnings/_TEMPLATE.md](../../docs/learnings/_TEMPLATE.md), add to [docs/learnings/README.md](../../docs/learnings/README.md) index, add `-- See docs/learnings/<slug>.md` comment at fix site. **The investigation is not done until the learning is written.**

Non-negotiable rules (from the skill):

- Prior art first, always. Phase 1 is non-skippable.
- Falsify before confirm.
- No fix without a verified reproduction.
- One change at a time during diagnosis.
