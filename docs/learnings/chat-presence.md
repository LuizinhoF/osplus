# chat-presence

| Field | Value |
|---|---|
| Date | 2026-04-18 |
| Area | relay |
| Tags | chat, presence, websocket, room-membership, json-array-workaround |
| Status | confirmed |

## Symptom

No symptom — this is the design rationale for the v16 presence feature so the next person doesn't have to re-derive it.

## Root cause / context

Pre-v16, players had no way to see who else was connected to the team chat. This made join/leave invisible and made empty rooms feel indistinguishable from broken rooms.

## Design

End-to-end pipeline, push-based, server is source of truth:

1. **Lua** resolves the player name via `resolvePlayerName()` (PlayerNamePrivate fast path with PMPlayerPublicProfile fallback — see `docs/learnings/playernameprivate-transient-account-id.md`), caches it as `cachedPlayerName`, and includes it in the `room_change` IPC message: `{type:"room_change", room, username}`. See `mod/OSPlus/scripts/chat.lua` `tryJoinRoom` and `mod/OSPlus/scripts/ipc.lua` `writeRoomChange`.
2. **Sidecar** caches `currentUsername` from any `room_change`, then includes it in every `join` message to the relay (including reconnect re-joins). See `sidecar/index.js` `joinRoom` and the `ws.on("open")` re-join path.
3. **Relay** sanitizes the username (strips C0 controls + DEL, trims, caps at `MAX_USERNAME_LEN=32`, falls back to `Anonymous`), stores it on `ws._username`, and after any room membership change calls `broadcastPresence(room)` which emits `{type:"presence", room, members}` to every member of that room (including the joiner so they see themselves immediately). See `server/index.js`.
4. **Sidecar** has no presence-specific code — the `presence` message falls through the existing `appendToInbox(str)` path because it isn't `joined`/`left`/`error`.
5. **Lua** `ipc.lua` matches `msg.type == "presence"` in `readInbox`, splits the `members` string on `\n`, and calls `chat.setPresence(list)`. `chat.setPresence` caches the list in `M.presence` and pushes a formatted Rich Text string to the BP via `widget:SetPresence(text)`.

## Wire-format wart: `members` is a string, not an array

`mod/OSPlus/scripts/json.lua` is intentionally flat-objects-only — it has no array decoder. Rather than extend the JSON library (and risk breaking the existing IPC paths that depend on it), the relay sends `members` as a single string with usernames joined by `\n`:

```json
{"type":"presence","room":"ABCDEFGHT0","members":"Alice\nBob\nCharlie"}
```

This is safe because `sanitizeUsername` strips ALL C0 controls including `\n` and `\t`, so `\n` is unambiguous as a delimiter. Lua splits with `gmatch("[^\n]+")` in `ipc.lua`. The `chat.setPresence` API surface still takes a Lua array (`{string}`) — the wire-format detail doesn't leak past `ipc.lua`.

If we ever need a richer presence payload (e.g., per-member metadata for future per-player colors), the right move is to extend `json.lua` to support arrays and arrays-of-objects, then change the wire format. Don't keep piling delimiters into strings.

## Lifecycle / cleanup

- `removeFromRoom(ws)` (called on `leave`, `close`, and at the start of `join` for room switches) calls `broadcastPresence` to the survivors before nulling `ws._room`. Empty rooms are deleted before broadcasting (early return), so no presence message is sent to a now-empty room.
- Lua's `leaveRoom()` clears `M.presence = {}` and re-pushes empty so the widget doesn't briefly show stale members from the previous room when joining a new one.
- `chat.reset()` (called from `RegisterLoadMapPostHook`) also clears `M.presence`.

## Backwards compat

A pre-v16 sidecar talking to a v16 relay sends `join` without `username` — relay falls back to `Anonymous` for that connection. Presence broadcasts still go out and the user just appears as `Anonymous` to everyone (including themselves). Not a hard error.

A v16 sidecar talking to a pre-v16 relay sends `username` in `join` — old relay ignores unknown fields. No presence broadcast happens. Lua never sees a `presence` message and renders an empty presence list. Acceptable degraded mode until the relay is redeployed.

## Lesson

When introducing a new server-pushed message type to a system with a hand-rolled Lua JSON decoder, **check what the decoder actually supports before designing the wire format**. The flat-objects-only constraint in `json.lua` is documented in its own header comment; missing it cost a small amount of rework on this feature.

## Related

- Files: `server/index.js` (`broadcastPresence`, `sanitizeUsername`, `removeFromRoom`), `sidecar/index.js` (`currentUsername`, `joinRoom`), `mod/OSPlus/scripts/ipc.lua` (`writeRoomChange`, presence inbox case), `mod/OSPlus/scripts/chat.lua` (`setPresence`, `M.presence`, `presenceTag`, `resolvePlayerName`)
- Architecture: `docs/architecture/state-contract.md` — `M.presence` and `PresenceList` are added to the audit table
- Related learning: `docs/learnings/ue-richtextblock-named-rows.md` — the `<Sender>` tag the presence formatter uses is documented there
