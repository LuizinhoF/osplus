# Deploying the OSPlus Relay

The relay is the WebSocket server that brokers chat and ping messages between
players in a match. It runs on a single OCI Always-Free VM behind Caddy
(reverse proxy + auto-TLS via Let's Encrypt).

This document covers:

- The deployed topology
- How to ship a code change (the 95% case)
- How to rebuild the VM from scratch (the 1% case)
- Operational basics: status, logs, restart, rollback

## Topology

```
                                  ┌──────────────────────────────────┐
  Game client (mod + sidecar)     │  OCI VM — 136.248.104.200        │
  ────────────────────────────    │  Ubuntu 22.04, AMD E2.1.Micro    │
                                  │                                  │
  sidecar reads relay_url from    │  ┌────────────────────────────┐  │
  sidecar/config.json:            │  │ Caddy (systemd)            │  │
                                  │  │ :80, :443                  │  │
   wss://play-osplus.duckdns.org  │  │ - LetsEncrypt auto-cert    │  │
              │                   │  │ - Reverse proxy → :3000    │  │
              ▼                   │  │ - WS upgrade transparent   │  │
   ┌──────────────────┐    443    │  └─────────────┬──────────────┘  │
   │ Internet / TLS   │───────────│                ▼                  │
   └──────────────────┘           │  ┌────────────────────────────┐  │
                                  │  │ Node relay (systemd)       │  │
                                  │  │ user: osplus               │  │
                                  │  │ bind: 127.0.0.1:3000       │  │
                                  │  │ /opt/osplus/relay/index.js │  │
                                  │  └────────────────────────────┘  │
                                  └──────────────────────────────────┘
```

## Endpoints

| Purpose | URL |
|---|---|
| WebSocket (clients) | `wss://play-osplus.duckdns.org` |
| Health probe        | `https://play-osplus.duckdns.org/health` |
| SSH                 | `ssh -i ~/.ssh/osplus_oci.key ubuntu@136.248.104.200` |

## Shipping a code change (the common case)

From the project root, on your local Windows machine:

```powershell
.\server\deploy\ship.ps1
```

What this does:

1. SSHes to the VM, wipes `/tmp/osplus-deploy/`.
2. SCPs `server/index.js`, `server/package.json`, `server/package-lock.json`,
   and the entire `server/deploy/` folder up to the VM.
3. Runs `sudo bash /tmp/osplus-deploy/server/deploy/install-relay.sh` on the VM.
4. The installer copies the code into `/opt/osplus/relay/`, runs
   `npm install --omit=dev`, validates the Caddyfile, reloads Caddy, and
   restarts the `osplus-relay` systemd unit.

You should see the relay's startup log lines and a `/health` JSON response
at the end. If anything fails, the script aborts and you can re-run after
fixing.

## Operational basics

All of these run inside an SSH session on the VM.

### Status

```bash
sudo systemctl status osplus-relay --no-pager
sudo systemctl status caddy --no-pager
```

### Live logs

```bash
sudo journalctl -u osplus-relay -f          # relay
sudo tail -f /var/log/caddy/play-osplus.log # caddy access log
```

### Restart

```bash
sudo systemctl restart osplus-relay
```

### Health probe

```bash
curl -s https://play-osplus.duckdns.org/health | jq .
# or from the VM itself:
curl -s http://127.0.0.1:3000/health | jq .
```

Returns:

```json
{
  "status": "ok",
  "uptime_sec": 12345,
  "rooms": 3,
  "connections": 7
}
```

### Setting an auth token (later)

When we add basic shared-secret auth, override the systemd Environment:

```bash
sudo systemctl edit osplus-relay
```

In the editor, add:

```ini
[Service]
Environment=RELAY_TOKEN=some-long-random-string
```

Save. Then `sudo systemctl restart osplus-relay`. Update the sidecar config
to append `?t=some-long-random-string` to its `relay_url`.

### Rolling back

The deploy is "last-write-wins" — there's no built-in rollback. Two options:

1. `git checkout <prev-sha> -- server/` locally, then `.\server\deploy\ship.ps1`.
2. Keep a backup directory on the VM:

   ```bash
   sudo cp -r /opt/osplus/relay /opt/osplus/relay.bak
   ```
   Restore with `sudo rm -rf /opt/osplus/relay && sudo mv /opt/osplus/relay.bak /opt/osplus/relay && sudo systemctl restart osplus-relay`.

When the relay grows past trivial, swap this out for a proper blue/green or
git-based deploy.

## Rebuilding the VM from scratch

Worst case: the VM is corrupted, accidentally terminated, or you want to
start clean. Re-run Tracks 1+2 of the original deployment guide
(`docs/ops/initial-vm-setup.md` — TODO, currently in chat history) to
provision a new VM, then ship.

### Cloud-side (OCI console, ~10 min)

1. Compute → Instances → Create instance.
2. Image: Ubuntu 22.04 (or 24.04 LTS).
3. Shape: `VM.Standard.A1.Flex` (4 OCPU / 24 GB) if available, else `VM.Standard.E2.1.Micro`.
4. Networking: assign public IPv4, attach to existing VCN.
5. SSH keys: upload `~/.ssh/osplus_oci.pub`.
6. Open Security List ingress for TCP/80 and TCP/443 (source `0.0.0.0/0`).

### OS-side (~5 min)

SSH in, then:

```bash
# Update + base tools
sudo apt update && sudo apt upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt install -y curl wget gnupg ca-certificates iptables-persistent

# OS firewall (the gotcha — Oracle's image REJECTs everything except 22 by default)
sudo iptables -D INPUT -p tcp -m state --state NEW --dport 80  -j ACCEPT 2>/dev/null
sudo iptables -D INPUT -p tcp -m state --state NEW --dport 443 -j ACCEPT 2>/dev/null
R=$(sudo iptables -L INPUT --line-numbers | awk '/REJECT/{print $1;exit}')
sudo iptables -I INPUT $R -p tcp -m state --state NEW --dport 443 -j ACCEPT
sudo iptables -I INPUT $R -p tcp -m state --state NEW --dport 80  -j ACCEPT
sudo netfilter-persistent save

# Swap (gives the 1 GB micro headroom for npm install spikes)
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Node 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Caddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy

# Service user
sudo useradd -r -m -s /bin/bash -d /opt/osplus osplus
sudo mkdir -p /opt/osplus/relay /opt/osplus/logs
sudo chown -R osplus:osplus /opt/osplus
sudo chmod 750 /opt/osplus
```

### DNS

Update the A record for `play-osplus.duckdns.org` at https://www.duckdns.org
to point at the new VM's public IP.

### Ship

From your local machine, edit `server/deploy/ship.ps1` to set the new
`-VmHost` default, then:

```powershell
.\server\deploy\ship.ps1
```

## Future work (not yet implemented)

- **Auth.** Currently anyone can connect and join any 4-char room.
  Mitigations in place: 4 KB payload cap, 5 conns/IP, 5 msg/sec rate limit,
  strict message validation. Real auth (token or Odyssey-bound) ships next.
- **Persistence.** Relay state is in-memory. Server restart drops all rooms.
  Acceptable for chat/ping; not acceptable for the future profile system —
  that gets its own process + SQLite.
- **Monitoring.** No external uptime monitor yet. Add UptimeRobot or
  similar pointing at `/health` once the relay has real users.
- **Backup.** Caddy auto-renews TLS certs and stores them in
  `/var/lib/caddy`. Consider snapshotting that path if cert revival becomes
  expensive.
