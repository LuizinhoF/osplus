# <Short title — what would you grep for in 6 months?>

| Field | Value |
|---|---|
| Date | YYYY-MM-DD |
| Area | one of: mod / sidecar / relay / build / ue-editor / re / ops / docs |
| Tags | comma-separated, lowercase, hyphenated. e.g. `chat, match-detection, ue4ss-pcall` |
| Status | `confirmed` / `working-theory` / `superseded-by-<learning-slug>` |

## Symptom

What was observed. Specific. The thing a future agent would search for.

> Example: "Chat widget vanished mid-match around the 3-minute mark and didn't return until the next match started. No errors in the UE4SS log."

## Root cause

What was actually wrong. Not "we changed X and it worked" — *why* did the original break.

> Example: "Match detection used `PlayerController.Pawn ~= nil` as a gate. During KOs and round resets the local Pawn is briefly nil before respawn. The poll caught one of those windows and treated it as match-end."

## Fix

What changed. Cite files and the smallest meaningful diff or commit.

> Example: "Switched the gate to `GameState_Game_C.CurrentMatchSeed ~= 0`. Seed is server-replicated, stable for the entire match. See `mod/OSPlus/scripts/chat.lua` `readMatchSeed()` and the `endMatch` re-arm. Bumped `config.lua` VERSION to `v15-chat-seed-gate`."

## Lesson

What to do differently next time. One or two sentences. The transferable insight.

> Example: "Local-player state (Pawn, PlayerController flags) blips during normal game events. For 'is the match still happening' questions, prefer server-replicated game state values over local-player presence."

## Related

- Files: `path/to/file.lua`, `path/to/other.md`
- Prior learnings (if this supersedes or extends one): `docs/learnings/<other-slug>.md`
- Upstream sources / docs / discussions, if any.
