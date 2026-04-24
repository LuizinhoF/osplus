# playernameprivate-machine-name-out-of-match

| Field | Value |
|---|---|
| Date | 2026-04-20 |
| Area | mod |
| Tags | chat, player-identity, ue4ss, playerstate, machine-name |
| Status | confirmed |

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