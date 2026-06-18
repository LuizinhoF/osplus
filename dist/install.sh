#!/usr/bin/env bash
set -euo pipefail

echo "======================================"
echo "           OSPlus - Installer"
echo "======================================"
echo

THIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR_NAME="OmegaStrikers"
GAME_PATH="${1:-}"
GAME_APPID=""

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

ok() {
    echo "[OK] $*"
}

add_library_from_vdf() {
    local vdf="$1"
    local steamapps
    steamapps="$(dirname -- "$vdf")"
    if [[ -d "$steamapps/common" ]]; then
        printf '%s\n' "$(dirname -- "$steamapps")"
    fi
    while IFS= read -r line; do
        case "$line" in
            *'"path"'*)
                local p
                p="$(printf '%s\n' "$line" | sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/')"
                p="${p//\\\\//}"
                [[ -n "$p" && -d "$p/steamapps" ]] && printf '%s\n' "$p"
                ;;
        esac
    done < "$vdf"
}

detect_game_path() {
    local roots=(
        "$HOME/.steam/steam"
        "$HOME/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    )

    local libs_tmp
    libs_tmp="$(mktemp)"
    for root in "${roots[@]}"; do
        [[ -f "$root/steamapps/libraryfolders.vdf" ]] || continue
        add_library_from_vdf "$root/steamapps/libraryfolders.vdf" >> "$libs_tmp"
    done

    while IFS= read -r lib; do
        [[ -n "$lib" ]] || continue
        local direct="$lib/steamapps/common/$GAME_DIR_NAME"
        if [[ -f "$direct/OmegaStrikers.exe" ]]; then
            GAME_PATH="$direct"
            local manifest
            for manifest in "$lib"/steamapps/appmanifest_*.acf; do
                [[ -f "$manifest" ]] || continue
                if grep -qi '"name"[[:space:]]*"Omega Strikers"' "$manifest"; then
                    GAME_APPID="$(basename "$manifest" | sed -E 's/appmanifest_([0-9]+)\.acf/\1/')"
                    break
                fi
            done
            rm -f "$libs_tmp"
            return 0
        fi

        for manifest in "$lib"/steamapps/appmanifest_*.acf; do
            [[ -f "$manifest" ]] || continue
            if grep -qi '"name"[[:space:]]*"Omega Strikers"' "$manifest"; then
                local install_dir appid candidate
                install_dir="$(sed -nE 's/.*"installdir"[[:space:]]+"([^"]+)".*/\1/p' "$manifest" | head -n 1)"
                appid="$(basename "$manifest" | sed -E 's/appmanifest_([0-9]+)\.acf/\1/')"
                candidate="$lib/steamapps/common/$install_dir"
                if [[ -n "$install_dir" && -f "$candidate/OmegaStrikers.exe" ]]; then
                    GAME_PATH="$candidate"
                    GAME_APPID="$appid"
                    rm -f "$libs_tmp"
                    return 0
                fi
            fi
        done
    done < <(sort -u "$libs_tmp")

    rm -f "$libs_tmp"
    return 1
}

if [[ -z "$GAME_PATH" ]]; then
    if ! detect_game_path; then
        echo "[!] Could not auto-detect Omega Strikers install path."
        echo "    Please enter the full path to your OmegaStrikers folder."
        echo "    Example: /home/you/.steam/steam/steamapps/common/OmegaStrikers"
        echo
        read -r -p "Game path: " GAME_PATH
    fi
fi

[[ -f "$GAME_PATH/OmegaStrikers.exe" ]] || die "OmegaStrikers.exe not found at: $GAME_PATH"

BIN_DIR="$GAME_PATH/OmegaStrikers/Binaries/Win64"
MODS_DIR="$BIN_DIR/Mods"
MOD_DIR="$MODS_DIR/OSPlus"
SCRIPTS_DIR="$MOD_DIR/Scripts"
SIDECAR_DIR="$MOD_DIR/sidecar"
DATA_DIR="$MOD_DIR/data"
PAK_ROOT="$GAME_PATH/OmegaStrikers/Content/Paks"
PAK_DIR="$PAK_ROOT/LogicMods"
UE4SS_SRC="$THIS_DIR/ue4ss-files"

[[ -d "$BIN_DIR" ]] || die "Game Binaries/Win64 folder not found at: $BIN_DIR"

ok "Found Omega Strikers at:"
echo "     $GAME_PATH"
echo

echo "[migrate] Cleaning old OSPlus prototype artifacts if present..."
rm -rf "$MODS_DIR/OmegaStrikersTest"
rm -f "$PAK_DIR/OmegaStrikersMod.pak"
rm -f "$PAK_ROOT/CustomPings_P.pak"

if [[ -f "$BIN_DIR/UE4SS.dll" ]]; then
    ok "UE4SS already installed in Win64, skipping UE4SS deploy"
    echo
else
    echo "Installing UE4SS v3.0.1 (flat layout)..."
    [[ -f "$UE4SS_SRC/UE4SS.dll" ]] || die "Bundled UE4SS files missing. Expected: $UE4SS_SRC/UE4SS.dll"
    mkdir -p "$MODS_DIR"
    cp -f "$UE4SS_SRC/dwmapi.dll" "$BIN_DIR/"
    cp -f "$UE4SS_SRC/UE4SS.dll" "$BIN_DIR/"
    cp -f "$UE4SS_SRC/UE4SS-settings.ini" "$BIN_DIR/"
    cp -f "$UE4SS_SRC/UE4SS-LICENSE.txt" "$BIN_DIR/"
    cp -R "$UE4SS_SRC/Mods/." "$MODS_DIR/"
    ok "UE4SS deployed"
    echo
fi

echo "Installing mod files..."
rm -rf "$SCRIPTS_DIR" "$DATA_DIR/emotes" "$DATA_DIR/localization/screens"
mkdir -p "$SCRIPTS_DIR" "$SIDECAR_DIR" "$DATA_DIR" "$DATA_DIR/emotes" "$DATA_DIR/localization/screens" "$PAK_DIR"

echo "  [1/5] Copying Lua scripts..."
cp -f "$THIS_DIR"/mod/scripts/*.lua "$SCRIPTS_DIR/"

echo "  [2/5] Copying runtime data..."
cp -R "$THIS_DIR/mod/data/." "$DATA_DIR/"

echo "  [3/5] Copying sidecar..."
pkill -f 'OSPlus\.exe|OmegaStrikersChat\.exe' >/dev/null 2>&1 || true
cp -f "$THIS_DIR/mod/sidecar/OSPlus.exe" "$SIDECAR_DIR/"
cp -f "$THIS_DIR/mod/sidecar/launch_hidden.vbs" "$SIDECAR_DIR/"
chmod +x "$SIDECAR_DIR/OSPlus.exe" 2>/dev/null || true
if [[ ! -f "$SIDECAR_DIR/config.json" ]]; then
    cp -f "$THIS_DIR/mod/sidecar/config.json" "$SIDECAR_DIR/"
fi

echo "  [4/5] Copying Blueprint pak..."
cp -f "$THIS_DIR/mod/OSPlus.pak" "$PAK_DIR/"

echo "  [5/5] Enabling mod in mods.txt..."
MODS_TXT="$MODS_DIR/mods.txt"
touch "$MODS_TXT"
grep -v -E '^[[:space:]]*(OSPlus|OmegaStrikersTest)[[:space:]]*:' "$MODS_TXT" > "$MODS_TXT.tmp" || true
mv "$MODS_TXT.tmp" "$MODS_TXT"
printf 'OSPlus : 1\n' >> "$MODS_TXT"
ok "OSPlus enabled"

echo
echo "======================================"
echo " Installation complete!"
echo "======================================"
echo
echo " Launch Omega Strikers normally from Steam."
echo
echo " On Proton/Steam Deck, OSPlus skips the Windows VBS launcher and starts"
echo " the sidecar exe directly from inside the game's compatibility layer."
echo
echo " IMPORTANT: set this Steam Launch Option for Omega Strikers on Linux:"
echo '   WINEDLLOVERRIDES="dwmapi=n,b" %command%'
echo
echo " This makes Proton load OSPlus's local dwmapi.dll proxy so UE4SS starts."
echo
echo " Config:"
echo "   $SIDECAR_DIR/config.json"
if [[ -n "$GAME_APPID" ]]; then
    echo
    echo " Runtime logs usually land under:"
    echo "   <steam-library>/steamapps/compatdata/$GAME_APPID/pfx/drive_c/users/steamuser/AppData/Local/OSPlus"
fi
echo
