# Learnings

Every non-trivial finding from working on OSPlus lands here. The discipline is enforced by `.cursor/rules/learnings-discipline.mdc`.

## What counts as a learning

Write an entry whenever **at least one** of these is true:

- The work involved more than ~30 minutes of debugging.
- A new engine/game fact was discovered (UFunction signature, BP property, lifecycle quirk).
- A new failure mode was found (a thing that crashed, broke silently, or behaved unexpectedly).
- A new tool, harness, or workflow step was introduced or significantly changed.
- A previously-believed fact turned out to be wrong.

If you're unsure, write the entry. The cost of a 5-minute log is far less than the cost of a future agent re-deriving the answer.

## How to write one

1. Copy `_TEMPLATE.md` to `<short-slug>.md` in this directory. Use kebab-case. The slug is what someone will grep for in six months.
2. Fill in every field. Empty sections mean the learning is incomplete.
3. Update any other doc the learning invalidates (`KNOWLEDGEBASE.md`, `AGENTS.md` toolchain section, etc.) — the learning entry is *additive*, not a substitute for fixing stale docs.
4. Link from the relevant code (a comment pointing to `docs/learnings/<slug>.md`) when the lesson is about a specific code location.

## Index

Add new entries here, newest first.

| Date | Slug | Area | One-line summary |
|---|---|---|---|
| 2026-04-04 | [chat-match-detection-via-seed](chat-match-detection-via-seed.md) | mod | Match detection switched from `Pawn` presence to server-replicated `CurrentMatchSeed`. |
| 2026-04-04 | [oci-relay-deploy-gotchas](oci-relay-deploy-gotchas.md) | ops | Five-failure-mode gauntlet: firewall layers, CRLF, DNS, log perms, JIT vs `MemoryDenyWriteExecute`. |
| 2026-04-04 | [ue-cook-additional-asset-dirs](ue-cook-additional-asset-dirs.md) | ue-editor | "Cook Content for Windows" needs `/Game/Mods/OSPlus` in *Additional Asset Directories to Cook*. |
