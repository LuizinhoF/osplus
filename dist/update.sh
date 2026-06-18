#!/usr/bin/env bash
set -euo pipefail

REPO="${OSPLUS_REPO:-LuizinhoF/osplus}"
ASSET_NAME="${OSPLUS_ASSET_NAME:-OSPlus.zip}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"

echo "======================================"
echo "           OSPlus - Updater"
echo "======================================"
echo

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

download_file() {
    local url="$1"
    local dest="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$dest" "$url"
    else
        die "Need curl or wget to download the latest OSPlus release."
    fi
}

extract_zip() {
    local zip_path="$1"
    local dest="$2"

    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$zip_path" -d "$dest"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$zip_path" "$dest" <<'PY'
import sys
import zipfile

zip_path, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_path) as archive:
    archive.extractall(dest)
PY
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$zip_path" -C "$dest"
    else
        die "Need unzip, python3, or bsdtar to extract the latest OSPlus release."
    fi
}

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

zip_path="$tmp_dir/$ASSET_NAME"
extract_dir="$tmp_dir/package"
mkdir -p "$extract_dir"

echo "Downloading latest OSPlus release..."
echo "  $DOWNLOAD_URL"
download_file "$DOWNLOAD_URL" "$zip_path"

echo "Extracting package..."
extract_zip "$zip_path" "$extract_dir"

installer="$extract_dir/install.sh"
[[ -f "$installer" ]] || die "Downloaded package does not contain install.sh"

echo "Running installer..."
bash "$installer" "$@"

echo
echo "[OK] OSPlus is up to date."
