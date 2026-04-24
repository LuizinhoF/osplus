# OSPlus — Copilot instructions

This file is the GitHub Copilot mirror of the policies in [.cursor/rules/](../.cursor/rules/). The `.cursor/rules/*.mdc` files are the **source of truth**; this file (and the per-language files in [.github/instructions/](instructions/)) exist so the same policies apply when working in VS Code + Copilot instead of Cursor.

The agent briefing in [AGENTS.md](../AGENTS.md) is loaded automatically and covers project layout, toolchain, and reading order. Read it first if you haven't.

## Always-on rules (apply to every change in this repo)

When working in this repo, follow the conventions in these files. Read the linked file the first time it becomes relevant in a session and apply it for the rest of the work:

- [.cursor/rules/code-conventions.mdc](../.cursor/rules/code-conventions.mdc) — cross-cutting: comment policy (WHY not WHAT), `[CATEGORY] message` logging format, wire-protocol naming per boundary, error response shape.
- [.cursor/rules/git-workflow.mdc](../.cursor/rules/git-workflow.mdc) — feature branches off `main`, conventional commits, never force-push `main`, propose branch names before creating them, ask before push/PR/history-rewrite.
- [.cursor/rules/harnesses.mdc](../.cursor/rules/harnesses.mdc) — use existing build/deploy/dev scripts (`build_dist.ps1`, `package_logicmod.ps1`, `deploy.ps1`, `server/deploy/ship.ps1`, `tools/setup/bootstrap.ps1`); propose before authoring new automation.
- [.cursor/rules/learnings-discipline.mdc](../.cursor/rules/learnings-discipline.mdc) — non-trivial findings get a [docs/learnings/](../docs/learnings/) entry before the task is "done"; update stale [KNOWLEDGEBASE.md](../KNOWLEDGEBASE.md) / [AGENTS.md](../AGENTS.md) when invalidated.

## Per-language conventions (auto-attach by file glob)

Copilot loads these from [.github/instructions/](instructions/) when a matching file is in context. Each file is a thin pointer to its `.cursor/rules/` source of truth:

- Lua under `mod/**/*.lua` → [lua-conventions.mdc](../.cursor/rules/lua-conventions.mdc) + [mod-architecture.mdc](../.cursor/rules/mod-architecture.mdc)
- Node under `sidecar/**`, `server/**` → [node-conventions.mdc](../.cursor/rules/node-conventions.mdc)
- PowerShell under `**/*.ps1`, `**/*.psm1` → [powershell-conventions.mdc](../.cursor/rules/powershell-conventions.mdc)

## Workflow skills (invoke when the trigger fires)

Cursor auto-activates skills from their `description` field. Copilot doesn't, so the same skills live as both:

- [.cursor/skills/<name>/SKILL.md](../.cursor/skills/) — source of truth, full content.
- [.github/prompts/<name>.prompt.md](prompts/) — invocable as `/<name>` in VS Code chat; each prompt delegates to its `.cursor/skills/` source.

The trigger conditions are documented in [AGENTS.md](../AGENTS.md) → "Workflow skills". Knowing they exist matters; reading the skill when the trigger fires matters more.

| Skill | Trigger | Source |
|---|---|---|
| `feature-design` | non-trivial "add X" / "implement X" requests | [.cursor/skills/feature-design/SKILL.md](../.cursor/skills/feature-design/SKILL.md) |
| `bug-investigate` | bug reports, regressions, unexpected behavior | [.cursor/skills/bug-investigate/SKILL.md](../.cursor/skills/bug-investigate/SKILL.md) |
| `release-checklist` | "ship a build" / "cut a release" | [.cursor/skills/release-checklist/SKILL.md](../.cursor/skills/release-checklist/SKILL.md) |
| `ue4ss-modding` | UE4SS Lua, BPModLoaderMod, ModActor patterns, custom paks | [.cursor/skills/ue4ss-modding/SKILL.md](../.cursor/skills/ue4ss-modding/SKILL.md) |
| `ue-ui-umg-slate` | UMG, widgets, UserWidget, BindWidget, Common UI | [.cursor/skills/ue-ui-umg-slate/SKILL.md](../.cursor/skills/ue-ui-umg-slate/SKILL.md) |
| `ue-serialization-savegames` | save/load, USaveGame, FArchive, persistence | [.cursor/skills/ue-serialization-savegames/SKILL.md](../.cursor/skills/ue-serialization-savegames/SKILL.md) |

## Maintenance

The `.cursor/` files are canonical. When updating a rule or skill, **edit the `.cursor/` file** — the `.github/` mirrors are pointers and rarely need to change. The only times to touch `.github/` files are:

- A new rule or skill is added to `.cursor/` → add a matching pointer here.
- A rule or skill is renamed/moved/deleted → update the pointer.
- The set of file globs for a language changes → update the `applyTo:` frontmatter.
