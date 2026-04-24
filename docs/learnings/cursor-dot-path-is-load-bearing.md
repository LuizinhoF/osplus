# The `.cursor/` path is load-bearing; renaming it silently disables the whole agentic layer

| Field | Value |
|---|---|
| Date | 2026-04-23 |
| Area | docs |
| Tags | cursor, agentic-setup, rules, skills, hooks, mcp |
| Status | confirmed |

## Symptom

After the agentic foundation rebuild, the folder holding rules / skills / hooks / MCP config was renamed from `.cursor/` to `cursor/` (no leading dot) to "keep auto-context clean." The first fresh-chat test of the newly-designed 6-stage workflow then behaved as if none of the agentic infrastructure existed:

- `alwaysApply: true` rules did not load into the chat.
- Skills did not auto-activate by description match.
- Project-level hooks in `.cursor/hooks.json` did not fire.
- The per-contributor MCP config at `.cursor/mcp.json` was not discovered.

The content was all there on disk under `cursor/` — it was just invisible to Cursor's runtime, which turned every agent interaction into "manually crawl the docs" mode.

## Root cause

Cursor's entire agentic auto-attachment model is keyed on the literal `.cursor/` path (the leading dot is part of the hook point, not a cosmetic convention). Specifically:

- `.cursor/rules/*.mdc` — the path where rule frontmatter (`alwaysApply`, `globs`, `description`) is interpreted.
- `.cursor/skills/<name>/SKILL.md` — the path Cursor scans for description-based skill invocation.
- `.cursor/hooks.json` + `.cursor/hooks/` — the path project-level hook registration reads.
- `.cursor/mcp.json` — the per-project MCP server config discovery path.

Renaming the folder to `cursor/` (without the dot) moved every one of those surfaces off the paths the runtime looks at. The content was syntactically valid and internally self-consistent; it was just mounted at a path nothing checked. This is a silent disable, not a noisy failure — there is no "rules folder not found" warning because, from Cursor's perspective, a project without a `.cursor/` folder is a valid unconfigured project.

The original hypothesis that the rename would "prevent context pollution" was also misdirected: context pollution is controlled by *per-rule frontmatter* (`alwaysApply: false`, `globs: <pattern>`, description-only activation), not by the folder's path. The rename was a sledgehammer that broke the machinery instead of tuning it.

## Fix

Reverted the folder back to `.cursor/`. Git saw the move as pure renames (identical content) so history stayed clean. Path references across the repo were rewritten from `cursor/...` back to `.cursor/...` in:

- `AGENTS.md` (7 references)
- `docs/dev-cycle.md` (10 references in the skills/rules lookup table)
- `docs/features/README.md` + `docs/learnings/*.md` (cross-links to skills)
- `.cursor/skills/feature-design/SKILL.md` + `.cursor/skills/discover/references/*.md` (internal cross-links)
- `docs/research/2026-agentic-stack.md` (adopted-layout diagram + descriptive text; new dated section added for the revert)
- `.cursor/hooks/block-mcp-commit.ps1` (comment mentioning `cursor/mcp.json` simplified to just `.cursor/mcp.json`)
- `.gitignore` (`cursor/mcp.json` → `.cursor/mcp.json`)

Historical references in dated-log entries (`docs/research/cold-start-log.md`) were intentionally left as-is — they correctly describe what happened at their dates.

## Lesson

The `.cursor/` path is not a naming convention — it's the contract between the repo and Cursor's runtime. Every piece of agentic infrastructure (rules, skills, hooks, MCP config) is keyed on it. If you want to control what loads into context for a given chat, edit the **frontmatter** of individual rules (`alwaysApply`, `globs`, `description`-only invocation), not the folder's path.

Concrete rule: **Never relocate `.cursor/` or any of its children to change Cursor's behavior.** If the agentic layer isn't behaving the way you want, the lever is per-rule frontmatter, not the filesystem.

## Related

- Files: `.cursor/`, `AGENTS.md`, `docs/research/2026-agentic-stack.md` (2026-04-23 revert section)
- Prior learning (why the folder was touched in the first place): `docs/learnings/product-architecture-coupling-via-premature-locks.md`
- Follow-up: audit `.cursor/rules/*.mdc` with `alwaysApply: true` and consider downgrading any that don't need to ride in every chat. Tracked separately from this revert.
