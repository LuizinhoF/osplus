# sidecar-cache-desired-state-before-ws-open

| Field | Value |
|---|---|
| Date | 2026-04-20 |
| Area | sidecar |
| Tags | sidecar, websocket, reconnect, identity, room-state |
| Status | confirmed |

## Symptom

Room and identity updates emitted from Lua via file IPC could be silently lost if they arrived while the sidecar WebSocket was still connecting or reconnecting. The sidecar would come back online without the desired room, match scope, or profile identity cached, which breaks any feature that depends on reconnect replays rather than repeated Lua emits.

## Root cause

The sidecar treated `currentRoom` as both the **desired** connection state and the **active** transport state. `joinRoom()` returned early unless `ws.readyState === OPEN`, so a `room_change` arriving while disconnected never updated `currentRoom` at all. The same pattern applied to profile identity: if the socket was down, there was no cached state to flush later.

That is the wrong ownership model for a bridge process. File IPC is the source of truth for what the sidecar *should* be connected as; the WebSocket is only the mechanism used to realize that state when the transport is available.

## Fix

Changed the sidecar to cache desired state immediately and flush it opportunistically when the socket is open:

- `sidecar/index.js` now stores `currentRoom`, `currentMatch`, `currentSteamId`, and `currentUsername` before checking socket readiness.
- Added `sendIdentity()` so `profile_identity` IPC messages are cached and replayed on reconnect.
- Extended the existing join flow to carry both `match` and `steamId`, so reconnects restore match-wide emote scope and sender identity without waiting for a fresh Lua event.

**2026-06-18 reconfirmation:** chat audience routing touched this path again and restored the same invariant for the live sidecar shape: `joinRoom(room)` assigns `currentRoom` before checking WebSocket readiness, while `room_change` caches `currentUsername` and `currentTeam` before calling it. See `docs/learnings/chat-match-wide-room-audience-routing.md`.

## Lesson

In sidecar-style bridge processes, cache **desired state before transport readiness checks**. A WebSocket reconnect path should replay the latest intended room/identity state from cache; it should not depend on upstream producers re-emitting the same event after every transient disconnect.

## Related

- Files: `sidecar/index.js`, `mod/OSPlus/scripts/ipc.lua`, `mod/OSPlus/scripts/main.lua`, `server/index.js`
- Prior learnings (if this supersedes or extends one): `docs/learnings/sidecar-ws-keepalive.md`
