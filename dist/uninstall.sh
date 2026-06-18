#!/usr/bin/env bash
set -euo pipefail

echo "======================================"
echo "           OSPlus - Uninstaller"
echo "======================================"
echo

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
        echo
        read -r -p "Game path: " GAME_PATH
    fi
fi

[[ -f "$GAME_PATH/OmegaStrikers.exe" ]] || die "OmegaStrikers.exe not found at: $GAME_PATH"

BIN_DIR="$GAME_PATH/OmegaStrikers/Binaries/Win64"
MODS_DIR="$BIN_DIR/Mods"
MOD_DIR="$MODS_DIR/OSPlus"
PAK_ROOT="$GAME_PATH/OmegaStrikers/Content/Paks"
PAK_DIR="$PAK_ROOT/LogicMods"
MODS_TXT="$MODS_DIR/mods.txt"

ok "Found Omega Strikers at:"
echo "     $GAME_PATH"
echo

echo "Stopping OSPlus sidecar if it is running..."
pkill -f 'OSPlus\.exe|OmegaStrikersChat\.exe' >/dev/null 2>&1 || true

echo "Removing OSPlus mod files..."
rm -rf "$MOD_DIR"
rm -f "$PAK_DIR/OSPlus.pak"
rm -f "$PAK_DIR/OmegaStrikersMod.pak"
rm -f "$PAK_ROOT/CustomPings_P.pak"

if [[ -f "$MODS_TXT" ]]; then
    grep -v -E '^[[:space:]]*(OSPlus|OmegaStrikersTest)[[:space:]]*:' "$MODS_TXT" > "$MODS_TXT.tmp" || true
    mv "$MODS_TXT.tmp" "$MODS_TXT"
fi

echo
read -r -p "Remove UE4SS too? Only choose yes if no other UE4SS mods use this install. [y/N] " purge_ue4ss
case "${purge_ue4ss:-N}" in
    y|Y|yes|YES)
        rm -f "$BIN_DIR/dwmapi.dll" "$BIN_DIR/UE4SS.dll" "$BIN_DIR/UE4SS-settings.ini" "$BIN_DIR/UE4SS-LICENSE.txt"
        rm -rf "$MODS_DIR/BPModLoaderMod" "$MODS_DIR/shared"
        ok "UE4SS files removed"
        ;;
    *)
        ok "UE4SS left installed"
        ;;
esac

if [[ -n "$GAME_APPID" ]]; then
    local_data_guess="$(dirname -- "$GAME_PATH")/../compatdata/$GAME_APPID/pfx/drive_c/users/steamuser/AppData/Local/OSPlus"
    if [[ -d "$local_data_guess" ]]; then
        echo
        read -r -p "Remove local OSPlus logs/config/token too? Reinstalling will create a new token. [y/N] " purge_data
        case "${purge_data:-N}" in
            y|Y|yes|YES)
                rm -rf "$local_data_guess"
                ok "Local OSPlus data removed"
                ;;
            *)
                ok "Local OSPlus data left in place"
                ;;
        esac
    fi
fi

echo
echo "======================================"
echo " Uninstall complete!"
echo "======================================"
echo
