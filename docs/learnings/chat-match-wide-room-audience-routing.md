# Chat audiences need match-wide rooms

| Field | Value |
|---|---|
| Date | 2026-06-18 |
| Area | relay |
| Tags | chat, spectators, audience-routing, room-state, websocket |
| Status | confirmed |

## Symptom

Custom-game spectators could use OSPlus chat, but they were stuck sending to whichever team-scoped room the client joined. Players also had no path to send a message to everyone in the match; the room itself encoded "my team only."

## Root cause

The chat room code combined `CurrentMatchSeed` with local `AssignedTeam`, producing one relay room per team. The sidecar can join exactly one room at a time, so a client could not be present in both team rooms and a match-wide room without a larger multi-room sidecar/relay redesign. The room was carrying two meanings at once: "which match is this?" and "who should receive this message?"

## Fix

Split those meanings:

- `chat.lua` now derives the relay room from match seed only.
- Chat messages carry `audience` (`team` or `all`) plus `targetTeam` for team-targeted sends.
- `ipc.lua` carries those flat fields through the file mailbox.
- `sidecar/index.js` forwards the local `team` on join and caches room metadata before transport readiness checks so reconnects replay the intended state.
- `server/index.js` stores each connection's team and filters team-targeted chat at broadcast time.

Default unprefixed sends stay team-scoped for players. `/all ...` sends to everyone. `/t1 ...` and `/t2 ...` send to a specific team.

Implementation edge case: JavaScript `Number(null)` is `0`, so `normalizeTeam`
must explicitly treat `null`, `undefined`, and `""` as no team before numeric
coercion. Without that guard, spectators join as team 1 and receive team-1-only
messages.

Custom-game test follow-up (2026-06-19): the game-side `AssignedTeam` field is
`EAssignedTeam` with `TeamZero=0`, `TeamOne=1`, `TeamTwo=2`. Relay routing uses
compact indices (`0` for Team 1, `1` for Team 2), so Lua must map raw `1 -> 0`
and `2 -> 1`; raw `0` means no routable player team. Because spectators also
need to join without a team, Lua cannot simply wait forever for a non-zero team.
It should join the match-wide room and periodically re-emit `room_change` while
in-match if team or username metadata changes.

Policy correction (2026-06-19): explicit `/team1` and `/team2` targeting is
not a player power for contacting the enemy team. Players may use their own
team chat or `/all`; only spectators may choose either team directly. Enforce
this both in Lua command parsing and on the relay, because old clients may
still send a forbidden `targetTeam`.

## Lesson

Do not encode recipient audience into the room identifier when a feature needs more than one audience in the same match. Use the room for shared match membership and put recipient intent on the message.

## Related

- Files: `mod/OSPlus/scripts/chat.lua`, `mod/OSPlus/scripts/ipc.lua`, `sidecar/index.js`, `server/index.js`, `docs/architecture/relay.md`
- Extends: `docs/learnings/relay-room-code-regex-vs-derived-codes.md`, `docs/learnings/sidecar-cache-desired-state-before-ws-open.md`
