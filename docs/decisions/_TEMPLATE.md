# ADR NNNN — <short title in imperative form>

| Field | Value |
|---|---|
| Status | `proposed` \| `accepted` \| `superseded` \| `deprecated` |
| Date | YYYY-MM-DD |
| Forcing feature | <branch name or feature description that made this decision necessary — "none, background cleanup" is a valid answer but requires extra justification below> |
| Supersedes | <ADR number or `—`> |
| Superseded by | <ADR number or `—`> |

## Context

What problem, constraint, or conflict forced this decision? Keep it to what is *actually* forcing a choice right now, not general background on the subsystem.

- What couldn't we do before this?
- What are we being asked to do that requires this?
- What prior decision does this interact with? (If any, link the ADR or `docs/decisions/_archive/` entry.)

## Options considered

**At least two real options are required.** An ADR with only one option is not a decision — it's a note. If you genuinely see only one path, write that up as a short note instead of using this template.

### Option A — <name>

- **What it is** — 1–3 sentences of concrete description. Not "use a database"; "add SQLite table `X(col1, col2)` indexed on `col1`."
- **Pros** — what this gets right.
- **Cons** — what this gets wrong, including the honest ones (cost, complexity, migration debt, future lock-in).
- **Cost to build** — how expensive is v1 of this?
- **Cost to change later** — how expensive is it to migrate off if we outgrow it or it fails?

### Option B — <name>

(Same structure.)

### Option C — <name>, if applicable

(Same structure.)

## Decision

The option we chose, stated as a single directive sentence. Then ≤5 sentences of rationale covering *why this option* and *why not the others*.

If the decision carries any conditions (e.g. "chosen for v1, revisit at N users"), name them explicitly — they become revisit triggers.

## Consequences

Be honest about both sides.

**What this commits us to:**
- Concrete behaviors, structures, or obligations this creates.
- Anything that becomes harder or forbidden as a result.

**What this rules out — at least until a future ADR supersedes this:**
- Features or capabilities we're foreclosing.
- Architectural moves we're preventing.

**Revisit triggers:**
- Specific conditions that should cause this ADR to be re-opened. Examples: "user count crosses 200," "Odyssey ships official API," "we add our second persistence-requiring feature."

## Related

- Relevant `docs/learnings/` entries.
- Code locations that implement this.
- Prior ADRs in the same area.

## Notes

Free-form. Anything that would help a future agent (or future you) understand why this document exists in this shape. Delete if empty.
