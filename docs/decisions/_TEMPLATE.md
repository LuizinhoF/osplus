# ADR NNNN — <short title in imperative form>

| Field | Value |
|---|---|
| Status | `proposed` \| `accepted` \| `superseded` \| `deprecated` |
| Date | YYYY-MM-DD |
| Forcing feature | <branch name or feature description that made this decision necessary — "none, background cleanup" requires extra justification below> |
| Supersedes | <ADR number or `—`> |
| Superseded by | <ADR number or `—`> |

## Decision

What was picked, in 2–4 sentences. Then a tight bulleted list naming the option codes (e.g. **A-1**, **S-B**) and what each one concretely is in one line.

If the decision interacts with a prior ADR (extends, narrows, or amends), name that here in one sentence. Don't bury it.

## Why these picks

One paragraph per pick. Name the runner-up and why we didn't take it. **Do not** repeat full pros/cons of every rejected option here — those go under *Considered and rejected* as one-liners.

- **Pick X over Y.** One paragraph. The honest reason, not a marketing reason.
- **Pick Z over W.** Same.

## What this commits us to

Concrete, scannable. Schema, routes, file paths, runtime obligations, code-comment commitments, deploy-script changes. Anything an implementer should be able to read this and execute without re-reading the rest of the doc.

- Schema: `table_name(col1 PK, col2, ...)` — one line per table.
- Routes: `METHOD /path` + auth posture + one-line behavior.
- File paths the user-facing client touches.
- Code-comment guarantees at specific call sites.
- Deploy-script or operational changes.

## What this rules out (until superseded)

What features, architectural moves, or future ADRs this forecloses. Tight bullets.

## Revisit when

Specific triggers that should reopen this ADR. Not vague ("when it gets bad") — concrete ("user count > 150 sustained", "second schema-changing feature lands", "first incident of X in production").

## Considered and rejected

One line per option that didn't make it. Format: `**Option-code** — name. One-clause reason.`

The "real options" requirement (≥ 2 honestly considered) is satisfied by this section, not by writing an essay on each. If you don't have at least one entry here, you don't have a decision — you have a note.

- **X-1** — Option name. Reason rejected in ≤15 words.
- **X-2** — Option name. Reason rejected in ≤15 words.

## Related

- **Forced by:** link to feature doc.
- **Relies on:** ADRs this ADR depends on.
- **Supersedes:** ADRs (or archive entries) this replaces.
- **Code locations** (post-acceptance):
  - `path/to/module` — what gets built/changed.

## Notes

Optional. Short. For lessons captured during this ADR's drafting that should outlive the doc — what almost tripped us up, what a future agent should know that isn't in the Decision/Why sections. Delete if empty.

---

## Length guidance

A typical ADR following this template lands around **80–120 lines**. If it's pushing 200+, you're probably re-litigating the options inside the body — move to the *Considered and rejected* one-liners and trust the reader.

Sections that **should be tight**:
- *Decision* — picks visible at a glance.
- *Why these picks* — one paragraph per pick, no quad-bulleted Pros/Cons/Cost-build/Cost-change.
- *Considered and rejected* — one line each.

Sections that **may grow** when the decision genuinely warrants it:
- *What this commits us to* — schemas, routes, and file paths take space; that's fine.
- *Notes* — only if there's a real lesson; don't pad.

If the decision has multiple sub-decisions (e.g. ADR 0002 has S/T/M/R/A), keep the same shape — bullets within sections, one paragraph per pick under *Why these picks*. Resist the urge to write a dedicated subsection per sub-decision.
