#!/usr/bin/env bash
# install-relay.sh — one-shot installer for the relay on the OCI VM.
#
# Run AS ROOT (or with sudo) on the VM, FROM the directory that contains
# both this script AND ../index.js (i.e. after `ship.ps1` has uploaded
# the server tree to /tmp/osplus-deploy/).
#
# Idempotent: safe to re-run for redeploys.

set -euo pipefail

# --- Paths -------------------------------------------------------------------
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # /tmp/osplus-deploy/server
DST_DIR="/opt/osplus/relay"
CADDYFILE_SRC="$SRC_DIR/deploy/Caddyfile"
CADDYFILE_DST="/etc/caddy/Caddyfile"
UNIT_SRC="$SRC_DIR/deploy/osplus-relay.service"
UNIT_DST="/etc/systemd/system/osplus-relay.service"

echo "[install] source: $SRC_DIR"
echo "[install] target: $DST_DIR"

# --- Sanity checks -----------------------------------------------------------
[ "$EUID" -eq 0 ] || { echo "must run as root (use sudo)"; exit 1; }
[ -f "$SRC_DIR/index.js" ] || { echo "missing $SRC_DIR/index.js — did ship.ps1 run?"; exit 1; }
id osplus >/dev/null 2>&1 || { echo "user 'osplus' missing — run bootstrap-vm.sh first"; exit 1; }
command -v node >/dev/null  || { echo "node missing — install nodejs first"; exit 1; }
command -v caddy >/dev/null || { echo "caddy missing — install caddy first"; exit 1; }

# --- Sync code into /opt/osplus/relay ----------------------------------------
echo "[install] syncing code → $DST_DIR"
mkdir -p "$DST_DIR"
cp -f "$SRC_DIR/index.js"            "$DST_DIR/index.js"
cp -f "$SRC_DIR/package.json"        "$DST_DIR/package.json"
cp -f "$SRC_DIR/package-lock.json"   "$DST_DIR/package-lock.json" 2>/dev/null || true
chown -R osplus:osplus "$DST_DIR"

# --- npm install (production deps only) --------------------------------------
echo "[install] npm install --production"
sudo -u osplus -H bash -c "cd '$DST_DIR' && npm install --omit=dev --no-audit --no-fund"

# --- Caddyfile ---------------------------------------------------------------
echo "[install] installing Caddyfile"
mkdir -p /var/log/caddy
# Recursive — ensures any pre-existing log files (from earlier deploys or
# failed runs) also get owned by caddy. Without -R, files left over from a
# root-run reload stay owned by root and Caddy can't open them.
chown -R caddy:caddy /var/log/caddy
cp -f "$CADDYFILE_SRC" "$CADDYFILE_DST"
caddy validate --config "$CADDYFILE_DST" --adapter caddyfile
# `restart` (not `reload`) on the Caddyfile change. Reload tries to be
# graceful but can hang for minutes on first-time cert issuance for a new
# domain; restart applies the new config cleanly and lets the cert workflow
# happen inside the running daemon afterwards.
systemctl restart caddy

# --- systemd unit ------------------------------------------------------------
echo "[install] installing systemd unit"
cp -f "$UNIT_SRC" "$UNIT_DST"
systemctl daemon-reload
systemctl enable osplus-relay
systemctl restart osplus-relay

# --- Status ------------------------------------------------------------------
sleep 1
echo
echo "[install] === osplus-relay status ==="
systemctl status osplus-relay --no-pager -l | head -15
echo
echo "[install] === recent logs ==="
journalctl -u osplus-relay -n 10 --no-pager
echo
echo "[install] === health probe ==="
curl -s http://127.0.0.1:3000/health || echo "(health failed)"
echo
echo "[install] done. Public URL: https://play-osplus.duckdns.org"
echo "[install] WebSocket:        wss://play-osplus.duckdns.org"
