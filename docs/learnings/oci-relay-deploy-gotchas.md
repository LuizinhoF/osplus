# oci-relay-deploy-gotchas

| Field | Value |
|---|---|
| Date | 2026-04-04 |
| Area | ops |
| Tags | oci, oracle-cloud, deploy, caddy, nodejs, systemd, iptables, duckdns, lets-encrypt |
| Status | confirmed |

## Symptom

Initial deploy of the Node.js relay to an OCI Always Free VM (Ubuntu 22.04, `play-osplus.duckdns.org`) hit five distinct failure modes in sequence. Each looked unrelated; together they form the reproducible "first time on OCI" gauntlet. **A sixth was added on 2026-04-29 when shipping the profile/auth feature** — see § "6. ship scripts hardcode a per-file list, miss new module subdirs."

## Root cause

Five separate issues, all encountered while standing up `ship.ps1` → `install-relay.sh` → working `wss://play-osplus.duckdns.org/health`:

### 1. Two firewall layers (OCI Security List + OS `iptables`)

Public IP timed out from a browser even after `curl localhost:80` worked on the VM. Two distinct firewalls:

- **Cloud-level**: OCI Security List ingress rules for ports 80 and 443 must be added *and saved* in the OCI console. The "Add" form looks committed before the actual save click. Easy to miss.
- **OS-level**: Ubuntu's default `iptables` has a `REJECT` rule near the end of the `INPUT` chain. ACCEPT rules for 80/443 must be **inserted before** the REJECT, not appended. Default `iptables -A` appends; needs `iptables -I INPUT <line>` with the right line number, then `netfilter-persistent save`.

### 2. CRLF line endings on shell scripts

`install-relay.sh` was edited on Windows and `scp`'d to Linux as-is. Bash failed with `$'\r': command not found` and `set: pipefail invalid option name`. The `\r` characters were being interpreted as part of each command name.

### 3. DNS pointed at home IP, not VM

`dig play-osplus.duckdns.org` from the VM resolved to the developer's home IP (138.118.171.58), not the VM's public IP. Caddy's automatic Let's Encrypt issuance hung silently for 25+ minutes because the ACME HTTP-01 challenge was being routed to the wrong machine. DuckDNS A record had been set up earlier for a different purpose and never updated.

### 4. Caddy log file permission

After the first successful start attempt, Caddy failed with `permission denied` writing `/var/log/caddy/play-osplus.log`. The directory existed but was owned by `root`, while Caddy runs as the `caddy` user. `chown -R caddy:caddy /var/log/caddy` fixed it.

### 5. `MemoryDenyWriteExecute=true` vs Node.js V8 JIT

`osplus-relay.service` was hardened with the standard systemd hardening directives, including `MemoryDenyWriteExecute=true`. Node.js promptly core-dumped with SIGTRAP on every restart. V8's JIT compiler needs writable+executable memory pages to compile hot code; `MemoryDenyWriteExecute` denies exactly that. Caddy then reported `502 Bad Gateway` to the user.

### 6. Ship scripts hardcode a per-file list, miss new module subdirs

When the profile/auth persistence module landed on 2026-04-28 it added a new `server/api/` subdirectory (`api/index.js`, `api/middleware/auth.js`, `api/profile/{index,schema}.js`). The first deploy after the merge to `main` succeeded all the way through `npm install --production` (added 38 packages cleanly including `better-sqlite3`'s prebuilt) but `osplus-relay.service` then went into a restart loop with:

```
Error: Cannot find module './api'
Require stack:
- /opt/osplus/relay/index.js
    at Object.<anonymous> (/opt/osplus/relay/index.js:38:23)
```

`server/index.js` line 38: `const { createApi } = require("./api")`. The `api/` folder existed locally but never made it to the VM because **both `ship.ps1` and `install-relay.sh` enumerate the files to copy by name**, not by glob or by tree-sync:

- `ship.ps1` lines 49-53: `$filesToShip = @($serverDir\index.js, $serverDir\package.json, $serverDir\package-lock.json)` — and a separate `scp -r deploy/` call. Nothing about `api/`.
- `install-relay.sh` lines 33-35: three explicit `cp -f "$SRC_DIR/<file>" "$DST_DIR/<file>"` lines for the same three files. Same omission.

`npm install` succeeded because `better-sqlite3` is in `package.json` regardless of whether the *consuming code* exists. The consumer (`server/api/index.js`) never reached the VM, so the `require("./api")` in the entry point failed at module-load time. Caddy then reported 502 to anyone hitting the public endpoint.

The systemic problem: `ship.ps1` + `install-relay.sh` are a **paired hardcoded enumeration**. Adding a new sibling file or directory under `server/` requires editing both scripts in lockstep — and a feature branch landing without that lockstep edit ships a broken relay even though the local dev test passed (because local dev runs `node index.js` against the full repo tree). The lockstep requirement is now documented at the comment-block in both scripts, but the long-term fix is a single rsync-style sync (next refactor).

## Fix

- **Cloud firewall**: Document the "save twice" gotcha; both ingress rules now exist for the production VM.
- **OS firewall**: `install-relay.sh` inserts ACCEPT rules with `iptables -I INPUT <N>`, then `netfilter-persistent save`.
- **Line endings**: Two layers of defense:
  - `.gitattributes` at the repo root forces LF for shell scripts.
  - `ship.ps1` runs `sed -i 's/\r$//'` on `*.sh` after upload, in case a contributor's git config still wrote CRLF locally.
- **DNS**: DuckDNS A record for `play-osplus.duckdns.org` updated to the VM's public IP. (DuckDNS updater script is *not* yet automated on the VM — currently set manually. See "Open follow-ups.")
- **Caddy logs**: `install-relay.sh` runs `chown -R caddy:caddy /var/log/caddy` after creating the directory.
- **Node.js hardening**: `osplus-relay.service` removes `MemoryDenyWriteExecute=true`. The other hardening directives (`NoNewPrivileges`, `PrivateTmp`, `ProtectHome`, `ProtectSystem=strict` etc.) stay.
- **Module subdirectories on deploy**: `ship.ps1` adds an explicit `scp -r api/` step alongside the `deploy/` upload. `install-relay.sh` adds an `rm -rf "$DST_DIR/api" && cp -rf "$SRC_DIR/api" "$DST_DIR/api"` block. Both edited in the same commit per `.cursor/rules/harnesses.mdc`. Both files now carry an inline comment naming the sibling-script lockstep requirement so the next agent adding a sibling dir sees both edit points.

## Lesson

- **OCI's two-layer firewall is the single most common "why doesn't it work" trap on Always Free.** Test from outside the VM, not just `localhost`.
- **Always normalize line endings on cross-platform deploy paths.** Don't trust `git config core.autocrlf` to be the same on every contributor's machine.
- **systemd hardening directives have application-specific compat costs.** `MemoryDenyWriteExecute` breaks any JIT runtime — Node.js, JVM, .NET tiered compilation, modern Python with JIT enabled. Audit by app, not by template.
- **Let's Encrypt failures look like "Caddy is hanging."** If `caddy reload` takes more than ~30 seconds, the most likely cause is DNS pointing somewhere other than the machine you're issuing the cert from.
- **Hardcoded copy-lists in deploy scripts are a feature-coupling timebomb.** Whenever the source tree adds a new sibling file or directory that the entry point requires, paired enumeration scripts (`ship.ps1` + `install-relay.sh`) must be edited in lockstep — and a feature branch can land green locally while shipping a broken relay because the lockstep edit was forgotten. Two short-term mitigations are now in place (inline comments in both scripts naming each other; this section as the public diagnostic). The long-term fix is to replace per-file enumeration with a tree-sync (rsync with explicit excludes for `node_modules/`, `data/`, etc.), which is the next refactor of this deploy harness.

## Open follow-ups

Not part of the fix, tracked here so the next session sees them:

- DuckDNS auto-updater script on the VM (so a public IP change doesn't silently expire DNS).
- Move from DuckDNS to a real domain before broader release (production credibility, no third-party dependency for DNS).
- Add basic auth/token to the relay (currently unauthenticated — fine for closed testing, not for public).
- Replace the per-file enumeration in `ship.ps1` + `install-relay.sh` with a single rsync-style tree sync (with explicit excludes for `node_modules/`, `data/`, `.git/`). Eliminates the lockstep-edit bear trap that produced gotcha § 6.

## Related

- Files: `server/deploy/install-relay.sh`, `server/deploy/ship.ps1`, `server/deploy/Caddyfile`, `server/deploy/osplus-relay.service`, `.gitattributes`
- Runbook: `docs/ops/deploy-relay.md`
