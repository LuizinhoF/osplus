# playernameprivate-machine-name-out-of-match

| Field | Value |
|---|---|
| Date | 2026-04-20 |
| Area | mod |
| Tags | chat, player-identity, ue4ss, playerstate, machine-name |
| Status | confirmed (observation) / **superseded for local-player display name** by `identity-display-name-substrate-replaces-heuristics.md` (2026-04-28) |

> **Update 2026-04-28:** the three-mode behavior of `PlayerState.PlayerNamePrivate` documented below (friendly name / account ID / machine name) is real and unchanged. The three-layer rejection prescribed as the fix is **no longer the recommended approach for local-player display name resolution.** Reason: the rejection is a blocklist over hostnames, and Windows decorates `COMPUTERNAME` with workgroup/DNS-style suffixes in some out-of-match contexts (we observed `DESKTOP-EJ47PRO-D197` while `COMPUTERNAME=DESKTOP-EJ47PRO`), so strict equality fails and the bad value leaks through. It also fails closed on legitimate names that happen to match the heuristic. The substrate path (Prometheus ID → `PMPlayerPublicProfile.Username`) sidesteps the entire problem class. See `identity-display-name-substrate-replaces-heuristics.md`.
>
> The heuristics ARE still active in `chat.lua` for inbound **remote** chat sender names — that path doesn't have a substrate equivalent and the heuristics there are still load-bearing.

## Symptom

OSPlus captured and propagated a value like `DESKTOP-EJ47PRO-D197` as the player's chat/profile display name. That string was the local Windows machine name, not the player's in-game name.

## Root cause

`PlayerState.PlayerNamePrivate` on Omega Strikers has at least three observed modes depending on context and timing:

1. Friendly in-game display name during a live real/custom match.
2. Raw lowercase-hex account ID during the early replication window and in practice mode.
3. Local Windows machine name in some out-of-match contexts.

The first profile/emote groundwork pass only rejected the account-ID shape. Anything else non-empty was treated as a friendly name, so the machine name was cached locally, sent through sidecar identity updates, and stored by the relay profile module.

## Fix

Added a three-layer rejection path:

- `mod/OSPlus/scripts/identity.lua` now rejects the exact local machine name (`COMPUTERNAME` / `HOSTNAME`) in addition to account IDs, and falls back to a synthetic runtime label `Player-<steamId suffix>` instead of reusing the bad value.
- `sidecar/index.js` refuses to cache or send machine-name/account-ID values as profile display names, and only uses the synthetic fallback for runtime room joins.
- `server/index.js` refuses to persist or repair usernames from account-ID, machine-name, or synthetic fallback values, so a bad client value cannot become the relay's authoritative display name.

## Lesson

For UE identity fields, "not an account ID" is not the same thing as "safe game-derived display name". When a field's meaning changes across menu, practice, and live-match contexts, reject known-bad shapes explicitly and use a synthetic fallback until a confirmed game name is available.

## Related

- Files: `mod/OSPlus/scripts/identity.lua`, `sidecar/index.js`, `server/index.js`, `KNOWLEDGEBASE.md`
- Prior learnings (if this supersedes or extends one): `docs/learnings/playernameprivate-transient-account-id.md`