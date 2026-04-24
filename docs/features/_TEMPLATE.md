# <Feature name>

| Field | Value |
|---|---|
| Slug | `<short-kebab-slug>` |
| Status | `framed` \| `feasibility` \| `designed` \| `building` \| `shipped` \| `shelved` |
| Created | YYYY-MM-DD |
| Last updated | YYYY-MM-DD |
| Owner | <agent + you, or just you if exploration is human-led> |
| Branch | <feature branch name once Stage 5 starts, or `—`> |

---

## Brief
*(Stage 2 — Frame. Filled when the feature passes Capture triage.)*

**Problem:** <1-2 sentences. What is the user-facing problem this feature addresses? Concrete, not abstract.>

**Audience:** <Which slice of the OSPlus audience does this serve? Newbies? Veterans? All? Reference `docs/product.md` audience definition.>

**Wedge fit:** <How does this serve the in-game-profile + community-events wedge? If it doesn't, justify why we're building it anyway.>

**Anti-goal check:** <Confirm this doesn't violate any anti-goal in `docs/product.md`. Name the anti-goals you checked, not just "passes.">

**Loose success criteria:** <2-4 signal-based outcomes. Not metrics — signals. "A newbie player tries OSPlus and reports the profile felt useful within their first 3 matches.">

**Out of scope:** <What this feature explicitly does NOT do. Anything someone might assume it gives them but doesn't.>

---

## Feasibility
*(Stage 3 — Discover. Filled by the `discover` skill before Design.)*

**Verdict:** `High` \| `Medium` \| `Low` \| `Not feasible`

**Confidence rationale:** <1-2 sentences explaining the verdict. What evidence carries weight, what's still inferred.>

**Assumptions (named, not buried):**
- <Specific testable claim, e.g. "`UEmoteWidget::ShowEmote` is callable from any `UWorld`, including outside a match.">
- <Each assumption is something a Stage 5 wall could land on. If you can't think of any, you're under-investigating.>

**Evidence trail:**
- <Technique used + finding. e.g. "DumpAllObjects in main menu: `UEmoteWidget` exists, `ShowEmote` UFunction visible. Did NOT verify call succeeds out-of-match.">
- <Verbatim outputs are fine and encouraged.>
- <Link to spike branch if one was run: `spike/<feature>/<assumption>`.>

**Promoted findings (generally reusable, written to KNOWLEDGEBASE / learnings):**
- <Path to the learning entry or KNOWLEDGEBASE section, with a one-line summary. `—` if none.>

**Recommended Stage 5 path:** `full feature` \| `thin slice first` \| `spike first` \| `shelve`

---

## Design
*(Stage 4 — Feature design. Filled by the `feature-design` skill after Stage 3 verdict + sign-off.)*

**Approach (1 paragraph):** <Plain-language description of the chosen implementation. References the chosen option per axis.>

**Axes considered:**
- <Axis name>: chose <option> over <alternatives> because <1 sentence>.
- <Axis name>: chose <option> over <alternatives> because <1 sentence>.

**Decisions deferred to ADR:**
- <If any architectural decision was hit, link the ADR (`docs/decisions/NNNN-slug.md`) here. `—` if none.>

**Files that will change:** <List the modules/files Stage 5 will touch.>

**Files that will NOT change but matter:** <Boundaries to respect.>

---

## Outcome
*(Stage 6 — Land. Filled when the feature ships, gets shelved, or gets forked.)*

**Result:** `shipped` \| `shelved` \| `forked`

**Date:** YYYY-MM-DD

**Summary:** <1-3 sentences. What landed, what didn't, what surprised you.>

**Branch / commit / release:** <Link the merge commit, release zip, etc. `—` for shelved.>

**Learning written:** [`docs/learnings/<slug>.md`](../learnings/<slug>.md) (or `—` if no trigger condition was met, but explain why)

**What's open after this:**
- <Anything explicitly left for a follow-up feature (creates Stage 1 entries).>
- <Anything that didn't make it but should be revisited if conditions change.>

---

## Notes

Free-form scratch space. Use for in-flight thinking that doesn't fit the structured sections, links to relevant chats / sessions, screenshots, etc. Delete if empty when shipping.
