# Caddy holds zombie WS open after backend restart

| Field | Value |
|---|---|
| Date | 2026-04-19 |
| Area | sidecar / ops |
| Tags | websocket, caddy, reverse-proxy, keepalive, reconnect, presence |
| Status | confirmed |

## Symptom

After redeploying the relay (`server/deploy/ship.ps1` → systemd restart of `osplus-relay`), the running game's sidecar appeared to stay connected from its own perspective. `ws.send()` succeeded. But:

- The relay's `journalctl -u osplus-relay` never logged the next `[ROOM]` join.
- `inbox.jsonl` stayed empty — no `presence` frames ever came back.
- `/health` reported `connections: 1` — the zombie was the only thing the relay still saw, and it wasn't ours.
- Caddy's access log showed the sidecar's pre-restart WS upgrade still "in progress" with a multi-minute duration even though the relay had been bounced.

User-facing effect: chat still rendered locally (because Lua adds outgoing messages to its own history before forwarding), but the presence list never populated and other clients never received the messages.

## Root cause

`reverse_proxy 127.0.0.1:3000` in `server/deploy/Caddyfile` is a plain proxy, not WS-aware in the way most people assume. When the upstream `osplus-relay` service restarts:

1. Caddy's TCP socket to `127.0.0.1:3000` dies.
2. Caddy does **not** automatically tear down the *client-facing* WS socket. The browser/sidecar side stays in `OPEN` state.
3. `ws.send()` from the client succeeds — frames are written to a TCP socket Caddy still owns. They get buffered and silently dropped.
4. Since neither side sends protocol-level pings by default (the `ws` Node client doesn't, and we didn't configure server-side `WebSocket.Server` heartbeat either), nothing detects the dead path. The connection can sit in this half-open state for the full Caddy idle timeout (default several minutes).

Net effect: the sidecar's `currentRoom` and `currentUsername` are correct, the file IPC works, but every frame after the relay restart vanishes into Caddy's buffer.

## Fix

Added explicit application-level WS keep-alive in `sidecar/index.js`:

- On `open`, start a 15s `setInterval` that calls `socket.ping()` and arms a 10s pong timeout.
- On `pong`, clear the pong timeout.
- If pong doesn't arrive, call `socket.terminate()` — that fires `close`, which the existing reconnect path handles.
- On `close`, clear both timers.

Tunables: `WS_PING_INTERVAL_MS = 15000`, `WS_PONG_TIMEOUT_MS = 10000`. Worst case the sidecar reconnects ~25s after a relay restart instead of being dead until the user closes the game.

Rebuilt the SEA exe (`npm run build`) and copied it to `…\Mods\OSPlus\sidecar\OSPlus.exe`. Game restart required for the change to take effect because `main.lua` only spawns the sidecar at startup (`taskkill /f /im OSPlus.exe` then launches the new exe via `wscript.exe launch_hidden.vbs`).

## Lesson

If you sit behind any reverse proxy, **the WS client must heartbeat itself**. "Connection is open" from the client's perspective is not enough — it's a TCP-level fact about the link to the *proxy*, not to the actual backend. The proxy will not lie to you, but it also will not tell you the truth about the upstream. Application-level pings are the only signal that round-trips through the whole chain.

Corollary: also avoid relying on this for code paths that have to be correct mid-deploy. The current architecture takes a ~25s presence-list outage on every relay restart. If that ever matters, the next move is server-side `noServer` heartbeat (`wss.on('connection', ws => { ws.isAlive = true; ... })`) plus `ws.terminate()` for unresponsive clients, and a versioned `/health` to let clients eagerly reconnect on deploy.

## Related

- Files: `sidecar/index.js` (`startKeepalive` / `stopKeepalive` / `pong` handler), `server/deploy/Caddyfile`
- Prior learnings: `docs/learnings/oci-relay-deploy-gotchas.md`, `docs/learnings/chat-presence.md`
- Upstream: [`ws` library — How to detect and close broken connections](https://github.com/websockets/ws#how-to-detect-and-close-broken-connections)
