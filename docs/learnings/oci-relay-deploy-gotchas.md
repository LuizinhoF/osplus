# oci-relay-deploy-gotchas

| Field | Value |
|---|---|
| Date | 2026-04-04 |
| Area | ops |
| Tags | oci, oracle-cloud, deploy, caddy, nodejs, systemd, iptables, duckdns, lets-encrypt |
| Status | confirmed |

## Symptom

Initial deploy of the Node.js relay to an OCI Always Free VM (Ubuntu 22.04, `play-osplus.duckdns.org`) hit five distinct failure modes in sequence. Each looked unrelated; together they form the reproducible "first time on OCI" gauntlet.

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

## Fix

- **Cloud firewall**: Document the "save twice" gotcha; both ingress rules now exist for the production VM.
- **OS firewall**: `install-relay.sh` inserts ACCEPT rules with `iptables -I INPUT <N>`, then `netfilter-persistent save`.
- **Line endings**: Two layers of defense:
  - `.gitattributes` at the repo root forces LF for shell scripts.
  - `ship.ps1` runs `sed -i 's/\r$//'` on `*.sh` after upload, in case a contributor's git config still wrote CRLF locally.
- **DNS**: DuckDNS A record for `play-osplus.duckdns.org` updated to the VM's public IP. (DuckDNS updater script is *not* yet automated on the VM — currently set manually. See "Open follow-ups.")
- **Caddy logs**: `install-relay.sh` runs `chown -R caddy:caddy /var/log/caddy` after creating the directory.
- **Node.js hardening**: `osplus-relay.service` removes `MemoryDenyWriteExecute=true`. The other hardening directives (`NoNewPrivileges`, `PrivateTmp`, `ProtectHome`, `ProtectSystem=strict` etc.) stay.

## Lesson

- **OCI's two-layer firewall is the single most common "why doesn't it work" trap on Always Free.** Test from outside the VM, not just `localhost`.
- **Always normalize line endings on cross-platform deploy paths.** Don't trust `git config core.autocrlf` to be the same on every contributor's machine.
- **systemd hardening directives have application-specific compat costs.** `MemoryDenyWriteExecute` breaks any JIT runtime — Node.js, JVM, .NET tiered compilation, modern Python with JIT enabled. Audit by app, not by template.
- **Let's Encrypt failures look like "Caddy is hanging."** If `caddy reload` takes more than ~30 seconds, the most likely cause is DNS pointing somewhere other than the machine you're issuing the cert from.

## Open follow-ups

Not part of the fix, tracked here so the next session sees them:

- DuckDNS auto-updater script on the VM (so a public IP change doesn't silently expire DNS).
- Move from DuckDNS to a real domain before broader release (production credibility, no third-party dependency for DNS).
- Add basic auth/token to the relay (currently unauthenticated — fine for closed testing, not for public).

## Related

- Files: `server/deploy/install-relay.sh`, `server/deploy/ship.ps1`, `server/deploy/Caddyfile`, `server/deploy/osplus-relay.service`, `.gitattributes`
- Runbook: `docs/ops/deploy-relay.md`
