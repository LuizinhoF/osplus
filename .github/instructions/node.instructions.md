---
applyTo: "{sidecar,server}/**/*.{js,mjs}"
---

# OSPlus Node — apply these conventions

Source of truth: [.cursor/rules/node-conventions.mdc](../../.cursor/rules/node-conventions.mdc).

Key invariants to keep in mind while editing:

- **CommonJS only** (`require` / `module.exports`). No ESM, no mixing — sidecar SEA build depends on this.
- **Minimum runtime deps.** New runtime dependency requires explicit conversation. `server/index.js` uses only `http` + `ws`; `sidecar/index.js` uses only `fs`, `path` + `ws`.
- **Wire boundary validation** on the relay: rate-limit → JSON parse → type allowlist (`VALID_TYPES`) → per-type field validation → handler. Bad input is logged + dropped, never thrown out of `ws.on("message")`.
- **Lifecycle:** handle `SIGTERM`/`SIGINT` cleanly, watchdog if lifetime depends on another process, log resolved config on startup.
- **Logging:** `console.log("[CATEGORY] message")`. Server adds ISO timestamp prefix; sidecar does not.

Cross-cutting (comment policy, wire-protocol naming per boundary, error response shape) lives in [.cursor/rules/code-conventions.mdc](../../.cursor/rules/code-conventions.mdc) — apply alongside.
